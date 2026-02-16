#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";
import { chromium } from "playwright";

/**
 * Browser Worker - keeps ONE browser open and processes messages
 *
 * This solves the window popup problem by:
 * 1. Opening browser ONCE and hiding it immediately
 * 2. Keeping it alive and processing messages in a loop
 * 3. Never closing the browser until the process exits
 */

const STORAGE_STATE = ".browser-profiles/chatgpt-state.json";
const REQUEST_FILE = ".flywheel/browser-request.json";
const RESPONSE_FILE = ".flywheel/browser-response.json";
const READY_FILE = ".flywheel/browser-ready.txt";

console.error("=== Browser Worker Starting ===");

// Validate storage state exists and is complete
if (!fs.existsSync(STORAGE_STATE)) {
  console.error(`✗ ERROR: Storage state file not found: ${STORAGE_STATE}`);
  console.error("");
  console.error("Run this to create it:");
  console.error("  node scripts/init-chatgpt-storage-state.mjs");
  console.error("");
  process.exit(1);
}

// Check storage state has authentication cookies
let storageData;
try {
  storageData = JSON.parse(fs.readFileSync(STORAGE_STATE, 'utf8'));
  const cookieCount = storageData.cookies?.length || 0;

  console.error(`✓ Storage state found: ${STORAGE_STATE}`);
  console.error(`  Cookies: ${cookieCount}`);

  // ChatGPT requires substantial authentication - check for minimum cookies
  if (cookieCount < 10) {
    console.error("");
    console.error(`✗ WARNING: Storage state appears incomplete (only ${cookieCount} cookies)`);
    console.error("  Expected: 10+ cookies for authenticated session");
    console.error("");
    console.error("This will likely result in unauthenticated browser.");
    console.error("Run: node scripts/init-chatgpt-storage-state.mjs");
    console.error("");
    process.exit(1);
  }

  // Check for chatgpt.com cookies specifically
  const chatgptCookies = storageData.cookies.filter(c =>
    c.domain && (c.domain.includes('chatgpt.com') || c.domain.includes('openai.com'))
  );

  if (chatgptCookies.length === 0) {
    console.error("");
    console.error("✗ ERROR: No ChatGPT cookies found in storage state");
    console.error("Run: node scripts/init-chatgpt-storage-state.mjs");
    console.error("");
    process.exit(1);
  }

  console.error(`  ChatGPT/OpenAI cookies: ${chatgptCookies.length}`);

} catch (err) {
  console.error(`✗ ERROR: Failed to parse storage state: ${err.message}`);
  console.error("Run: node scripts/init-chatgpt-storage-state.mjs");
  process.exit(1);
}

// Launch browser ONCE - visible so user can see ChatGPT responses
const browser = await chromium.launch({
  headless: false,
  args: [
    '--disable-blink-features=AutomationControlled',
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-dev-shm-usage',
    '--disable-web-security'
  ]
});

const context = await browser.newContext({
  storageState: STORAGE_STATE,
  viewport: { width: 1280, height: 800 },
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
});

const page = await context.newPage();

console.error("✓ Browser context created with authentication");
console.error("✓ Browser opened (visible)");
console.error("");
console.error("Worker ready. Watching for requests at:", REQUEST_FILE);
console.error("Press Ctrl+C to stop.");
console.error("");

// Write ready signal
fs.writeFileSync(READY_FILE, Date.now().toString() + "\n");

// Process loop
let pollCount = 0;
while (true) {
  pollCount++;
  if (pollCount % 10 === 0) {
    // Log every 5 seconds (10 polls * 500ms)
    console.error(`[POLLING] Checking for requests... (poll #${pollCount})`);
  }

  // Check for request file
  if (fs.existsSync(REQUEST_FILE)) {
    try {
      const request = JSON.parse(fs.readFileSync(REQUEST_FILE, "utf8"));

      // Delete request file immediately to prevent reprocessing
      fs.unlinkSync(REQUEST_FILE);

      console.error(`[${new Date().toISOString()}] Processing request: ${request.conversation_url}`);

      // Navigate to conversation
      await page.goto(request.conversation_url, { waitUntil: "domcontentloaded", timeout: 30000 });

      // Wait for input
      const input = page.locator('[contenteditable="true"]').last();
      await input.waitFor({ state: "visible", timeout: 10000 });
      await page.waitForTimeout(1000);

      // Capture baseline
      const baselineCount = await page.locator('[data-message-author-role="assistant"]').count();

      // Post message
      await input.evaluate((el, text) => {
        el.textContent = text;
        el.dispatchEvent(new Event("input", { bubbles: true }));
      }, request.message);

      await page.waitForTimeout(1000);
      await input.press('Enter');

      // Wait for response
      const messageLocator = page.locator('[data-message-author-role="assistant"]');
      let newMessageAppeared = false;
      const waitStart = Date.now();

      while (!newMessageAppeared && (Date.now() - waitStart < 10000)) {
        const currentCount = await messageLocator.count();
        if (currentCount > baselineCount) {
          newMessageAppeared = true;
        } else {
          await page.waitForTimeout(500);
        }
      }

      if (!newMessageAppeared) {
        throw new Error("Timeout waiting for response");
      }

      // Wait for completion
      const stopButton = page.locator('button').filter({ hasText: /stop generating/i });
      let stopButtonGone = false;
      const startTime = Date.now();

      while (!stopButtonGone && (Date.now() - startTime < 120000)) {
        await page.waitForTimeout(3000);
        const isGenerating = await stopButton.isVisible().catch(() => false);
        if (!isGenerating) {
          stopButtonGone = true;
        }
      }

      // Wait for initial DOM settle
      await page.waitForTimeout(5000);

      // Verify text stability (check every 3 seconds, max 3 checks)
      const lastMessage = page.locator('[data-message-author-role="assistant"]').last();
      let lastText = await lastMessage.innerText().catch(() => "");
      let stableChecks = 0;
      let emptyChecks = 0; // Guard #9: Count consecutive empty checks
      const maxStabilityChecks = 3;

      console.error(`  Initial text length: ${lastText.length} chars`);

      while (stableChecks < maxStabilityChecks) {
        await page.waitForTimeout(3000);

        const currentText = await lastMessage.innerText().catch(() => "");

        if (currentText === lastText && currentText.length > 0) {
          stableChecks++;
          emptyChecks = 0; // Reset empty counter when we have content
          console.error(`  Text stable (check ${stableChecks}/${maxStabilityChecks})`);
          if (stableChecks >= 2) {
            // Stable for 2 checks (6 seconds) is enough
            break;
          }
        } else if (currentText.length === 0 && lastText.length === 0) {
          // Guard #9: Empty message detection
          emptyChecks++;
          console.error(`  Text empty (check ${emptyChecks}/2)`);
          if (emptyChecks >= 2) {
            // Empty for 2 checks (6 seconds) - likely a failed/duplicate request
            console.error("  Message remains empty after stability wait - treating as empty response");
            break;
          }
        } else {
          console.error(`  Text changed: ${lastText.length} -> ${currentText.length} chars`);
          lastText = currentText;
          stableChecks = 0;
          emptyChecks = 0;
        }
      }

      console.error(`  Final text length: ${lastText.length} chars`);

      // Guard #9 fallback: If last message is empty, try second-to-last
      let rawText = lastText;
      if (!rawText || rawText.length === 0) {
        console.error("  Last message empty - trying second-to-last message");
        const allMessages = await page.locator('[data-message-author-role="assistant"]').all();
        if (allMessages.length >= 2) {
          rawText = await allMessages[allMessages.length - 2].innerText().catch(() => "");
          console.error(`  Second-to-last message: ${rawText.length} chars`);
        }
      }

      // Extract JSON if present
      let extracted_json = null;
      let parse_ok = false;

      // Try 1: Look for ```json fences
      const jsonMatch = rawText.match(/```json\s*([\s\S]*?)\s*```/i);
      if (jsonMatch) {
        try {
          extracted_json = JSON.parse(jsonMatch[1]);
          parse_ok = true;
        } catch (e) {}
      }

      // Try 2: Look for code blocks in DOM (ChatGPT renders JSON in <pre><code>)
      if (!parse_ok) {
        try {
          const codeBlocks = await lastMessage.locator('pre code').all();
          if (codeBlocks.length > 0) {
            // Try the last code block first (most likely to be the answer)
            for (let i = codeBlocks.length - 1; i >= 0; i--) {
              const codeText = await codeBlocks[i].innerText();
              try {
                extracted_json = JSON.parse(codeText);
                parse_ok = true;
                break;
              } catch (e) {
                // Not valid JSON, try next
              }
            }
          }
        } catch (e) {}
      }

      // Try 3: Look for "JSON\n{" pattern (ChatGPT's fallback format)
      if (!parse_ok) {
        const simpleMatch = rawText.match(/^JSON\s*\n\s*(\{[\s\S]*\}|\[[\s\S]*\])\s*$/im);
        if (simpleMatch) {
          try {
            extracted_json = JSON.parse(simpleMatch[1]);
            parse_ok = true;
          } catch (e) {}
        }
      }

      // Write response
      const response = {
        ok: true,
        raw_text: rawText,
        parse_ok: parse_ok,
        extracted_json: extracted_json,
        error: parse_ok ? null : "NO_JSON_STRUCTURE_FOUND"
      };

      fs.writeFileSync(RESPONSE_FILE, JSON.stringify(response, null, 2) + "\n");
      console.error(`✓ Response written (${rawText.length} chars)`);

    } catch (err) {
      const errorResponse = {
        ok: false,
        raw_text: "",
        parse_ok: false,
        extracted_json: null,
        error: err.message
      };
      fs.writeFileSync(RESPONSE_FILE, JSON.stringify(errorResponse, null, 2) + "\n");
      console.error(`✗ Error: ${err.message}`);
    }
  }

  // Sleep before next check
  await page.waitForTimeout(500);
}
