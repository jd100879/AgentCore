#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { chromium } from "playwright";

/**
 * Post a message to ChatGPT and extract JSON response
 *
 * Uses Playwright DIRECTLY (not MCP) to:
 * - Load authenticated ChatGPT session
 * - Post message
 * - Wait for response
 * - Extract JSON code block
 * - Return it
 *
 * This runs as a separate process so it doesn't burn the bridge agent's context.
 */

function usage(exitCode = 1) {
  console.error(`
post-and-extract.mjs

Post a message to ChatGPT and extract the JSON response.

Usage:
  node scripts/chatgpt/post-and-extract.mjs \\
    --message-file tmp/batch-request.txt \\
    --out tmp/batch-response.json \\
    [--timeout 60000]

Requires:
- .flywheel/chatgpt.json (conversation URL)
- .browser-profiles/chatgpt-state.json (auth state)

This uses Playwright directly (not MCP) to avoid context burn.
`);
  process.exit(exitCode);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith("--")) {
        args[key] = true;
      } else {
        args[key] = next;
        i++;
      }
    }
  }
  return args;
}

async function postAndExtract(conversationUrl, message, storageStatePath, timeout = 60000) {
  const browser = await chromium.launch({
    headless: false,  // Use headed mode to avoid detection
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-web-security'
    ]
  });

  const context = await browser.newContext({
    storageState: storageStatePath,
    viewport: { width: 1280, height: 800 },
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
  });

  const page = await context.newPage();

  try {
    console.error(`Navigating to: ${conversationUrl}`);
    await page.goto(conversationUrl, { waitUntil: "domcontentloaded", timeout: 30000 });

    console.error("Waiting for input...");
    const input = page.locator('[contenteditable="true"]').last();
    await input.waitFor({ state: "visible", timeout: 10000 });

    // Wait for messages to load
    await page.waitForTimeout(2000);

    // Guard #1: Capture baseline count BEFORE sending to avoid race condition
    console.error("Capturing baseline message count...");
    await page.waitForTimeout(500);  // Wait for page to stabilize
    const baselineCount = await page.locator('[data-message-author-role="assistant"]').count();
    console.error(`Baseline assistant messages: ${baselineCount}`);

    console.error(`Posting message (${message.length} chars)...`);
    await input.evaluate((el, text) => {
      el.textContent = text;
      el.dispatchEvent(new Event("input", { bubbles: true }));
    }, message);

    await page.waitForTimeout(1000);

    // Press Enter to send (more reliable than clicking button)
    await input.press('Enter');

    console.error("Waiting for new assistant message...");

    // Wait for new message to appear (count increments)
    const messageLocator = page.locator('[data-message-author-role="assistant"]');
    let newMessageAppeared = false;
    const waitStart = Date.now();

    while (!newMessageAppeared && (Date.now() - waitStart < 10000)) {
      const currentCount = await messageLocator.count();
      if (currentCount > baselineCount) {
        newMessageAppeared = true;
        console.error(`New message appeared (count: ${currentCount})`);
      } else {
        await page.waitForTimeout(500);
      }
    }

    if (!newMessageAppeared) {
      throw new Error("Timeout waiting for new assistant message to appear");
    }

    console.error("Waiting for response to complete...");

    // Two-signal gate: Wait for "Stop generating" button to disappear AND text to stabilize
    // Guard #2: Make stop button check best-effort (selector brittleness)
    const stopButton = page.locator('button').filter({ hasText: /stop generating/i });

    const startTime = Date.now();
    let responseComplete = false;
    let lastMessageText = "";
    let stableCount = 0;

    while (!responseComplete && (Date.now() - startTime < timeout)) {
      await page.waitForTimeout(3000);  // Longer poll interval

      // Signal 1: Stop generating button gone (best-effort)
      const isGenerating = await stopButton.isVisible().catch(() => false);

      if (!isGenerating) {
        // Signal 2: Message text stable (primary gate)
        const lastMessage = page.locator('[data-message-author-role="assistant"]').last();
        const currentText = await lastMessage.innerText().catch(() => "");

        if (currentText === lastMessageText && currentText.length > 0) {
          stableCount++;
          if (stableCount >= 3) {
            // Text stable for 3 checks (9 seconds total)
            responseComplete = true;
            console.error(`Response stable for ${stableCount * 3}s, extracting...`);
          }
        } else {
          console.error(`Text changed: ${lastMessageText.length} -> ${currentText.length} chars`);
          lastMessageText = currentText;
          stableCount = 0;
        }
      } else {
        console.error("Still generating...");
        stableCount = 0;
      }
    }

    if (!responseComplete) {
      throw new Error(`Timeout waiting for response after ${timeout}ms`);
    }

    console.error("Extracting JSON response...");

    // Extract from last assistant message container
    const lastMessage = page.locator('[data-message-author-role="assistant"]').last();
    let fullText = await lastMessage.innerText().catch(() => "");

    // Guard #3: Fallback to textContent if innerText fails or is empty
    if (!fullText || fullText.length === 0) {
      console.error("innerText empty, trying textContent...");
      fullText = await lastMessage.textContent().catch(() => "");
    }

    if (!fullText || fullText.length === 0) {
      throw new Error("Could not extract any text from last assistant message");
    }

    // Guard #4: Use global regex and take LAST match (not first)
    const allMatches = [...fullText.matchAll(/```json\s*([\s\S]*?)\s*```/gi)];  // Case-insensitive

    let jsonText;
    if (allMatches.length === 0) {
      // Fallback: try without 'json' label
      const genericMatches = [...fullText.matchAll(/```\s*([\s\S]*?)\s*```/g)];
      if (genericMatches.length === 0) {
        // No code fences at all - try parsing entire response as JSON
        console.error('No code fences found, attempting to parse entire response as JSON');
        // Remove "JSON" label if present at start
        let cleaned = fullText.replace(/^JSON\s*/i, '').trim();

        // Try to extract just the JSON array/object
        // Find first [ or { and match its closing bracket
        const firstBracket = cleaned.match(/^(\[|\{)/);
        if (firstBracket) {
          // Find matching closing bracket
          let depth = 0;
          let inString = false;
          let escape = false;
          for (let i = 0; i < cleaned.length; i++) {
            const char = cleaned[i];
            if (escape) {
              escape = false;
              continue;
            }
            if (char === '\\') {
              escape = true;
              continue;
            }
            if (char === '"') {
              inString = !inString;
              continue;
            }
            if (inString) continue;

            if (char === '[' || char === '{') depth++;
            if (char === ']' || char === '}') {
              depth--;
              if (depth === 0) {
                jsonText = cleaned.substring(0, i + 1);
                break;
              }
            }
          }
          if (!jsonText) jsonText = cleaned;  // Fallback
        } else {
          jsonText = cleaned;
        }
      } else {
        console.error(`No 'json' fence found, using last generic fence (${genericMatches.length} total)`);
        jsonText = genericMatches[genericMatches.length - 1][1];
      }
    } else {
      jsonText = allMatches[allMatches.length - 1][1];
    }

    console.error(`Attempting to parse JSON (${jsonText.length} chars)`);

    // Parse the extracted JSON
    let json;
    try {
      json = JSON.parse(jsonText);
    } catch (e) {
      throw new Error(`Extracted text is not valid JSON: ${e.message}\nExtracted:\n${jsonText.substring(0, 200)}...`);
    }

    return json;

  } finally {
    // Don't close browser - keep it open for reuse
    // await browser.close();
    console.error("Browser kept open for reuse");
  }
}

(async function main() {
  const args = parseArgs(process.argv);

  if (args.help || args.h) usage(0);

  const messageFile = args["message-file"];
  const outPath = args.out;
  const timeout = parseInt(args.timeout || "60000", 10);

  if (!messageFile) {
    console.error("Missing required --message-file");
    usage(1);
  }

  // Read message
  const message = fs.readFileSync(messageFile, "utf8");

  // Read config
  const configPath = ".flywheel/chatgpt.json";
  if (!fs.existsSync(configPath)) {
    console.error(`Config not found: ${configPath}`);
    process.exit(1);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const conversationUrl = config.crt_url;

  // Check for storage state
  const storageStatePath = ".browser-profiles/chatgpt-state.json";
  if (!fs.existsSync(storageStatePath)) {
    console.error(`Storage state not found: ${storageStatePath}`);
    console.error("Run: node scripts/init-chatgpt-storage-state.mjs");
    process.exit(1);
  }

  console.error("=== ChatGPT Post and Extract ===");
  console.error(`Conversation: ${conversationUrl}`);
  console.error(`Message length: ${message.length} chars`);
  console.error(`Timeout: ${timeout}ms`);
  console.error("");

  const response = await postAndExtract(conversationUrl, message, storageStatePath, timeout);

  const output = JSON.stringify(response, null, 2);

  if (outPath) {
    const abs = path.isAbsolute(outPath) ? outPath : path.join(process.cwd(), outPath);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, output + "\n", "utf8");
    console.error(`✓ Response written to: ${abs}`);
  } else {
    process.stdout.write(output + "\n");
  }

  process.exit(0);
})().catch((err) => {
  console.error(`ERROR: ${err.message}`);
  process.exit(1);
});
