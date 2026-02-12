#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execSync } from "node:child_process";

function usage(exitCode = 1) {
  console.error(`
batch-plan.mjs

Send multiple bead contexts to ChatGPT at once and get back multiple plans.

Usage:
  node scripts/chatgpt/batch-plan.mjs \\
    --beads bd-auth,bd-api,bd-ui \\
    [--out plans/batch-001.json]

The tool will:
1. Read each bead's context using 'br show <bead-id>'
2. Format a batch request to ChatGPT
3. Extract multiple plan responses
4. Output as JSON array

Output format:
[
  {
    "bead_id": "bd-auth",
    "plan": [...],
    "risks": [...],
    "acceptance_tests": [...],
    "next_actions": [...]
  },
  ...
]
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

function getBeadInfo(beadId) {
  try {
    const output = execSync(`br show ${beadId} --format json`, { encoding: "utf8" });
    return JSON.parse(output);
  } catch (e) {
    console.error(`Failed to get info for bead ${beadId}: ${e.message}`);
    return null;
  }
}

function formatBatchRequest(beads) {
  const beadContexts = beads.map((b, idx) => {
    return `
## Bead ${idx + 1}: ${b.id}
**Title:** ${b.title || b.subject || "No title"}
**Status:** ${b.status || "unknown"}
**Description:**
${b.description || b.body || "No description"}

**Dependencies:** ${b.dependencies?.length ? b.dependencies.join(", ") : "none"}
`;
  }).join("\n---\n");

  return `I need implementation plans for ${beads.length} beads. For EACH bead, provide:

1. **plan** - Array of step objects: { step: number, action: string, owner: string, evidence: string }
2. **risks** - Array of risk objects: { risk: string, mitigation: string }
3. **acceptance_tests** - Array of test descriptions (strings)
4. **next_actions** - Array of next_action objects with pool-based assignment:
   {
     "task": "string",
     "assign_to": "any",  // Use "any" for pool-based assignment
     "priority": "P0|P1|P2|P3",
     "blocking": boolean,
     "notes": "Step-by-step copy/paste-ready instructions",
     "requirements": ["prereq1", "prereq2"],
     "acceptance": ["test command + expected output"]
   }

Return as valid JSON array where each element corresponds to a bead in order:

[
  {
    "bead_id": "${beads[0]?.id}",
    "plan": [...],
    "risks": [...],
    "acceptance_tests": [...],
    "next_actions": [...]
  },
  // ... one object per bead
]

${beadContexts}

Return ONLY the JSON array, no commentary.`;
}

(async function main() {
  const args = parseArgs(process.argv);

  if (args.help || args.h) usage(0);

  const beadsArg = args.beads;
  const outPath = args.out;

  if (!beadsArg) {
    console.error("Missing required --beads argument");
    usage(1);
  }

  const beadIds = beadsArg.split(",").map(s => s.trim());

  // Guard #5: Cap batch size at 5 beads for MVP
  const MAX_BATCH_SIZE = 5;
  if (beadIds.length > MAX_BATCH_SIZE) {
    console.error(`ERROR: Batch size ${beadIds.length} exceeds maximum of ${MAX_BATCH_SIZE}`);
    console.error(`Please split into smaller batches to avoid truncation/continue behavior.`);
    process.exit(1);
  }

  console.error(`Fetching info for ${beadIds.length} beads...`);
  const beads = beadIds.map(id => {
    const info = getBeadInfo(id);
    return info ? { id, ...info } : { id, title: "Failed to load", description: "Error loading bead info" };
  });

  console.error(`Formatting batch request for ChatGPT...`);
  const request = formatBatchRequest(beads);

  // Save request to temp file
  fs.mkdirSync("tmp", { recursive: true });
  const requestFile = "tmp/batch-request.txt";
  fs.writeFileSync(requestFile, request, "utf8");
  console.error(`Request saved to ${requestFile} (${request.length} chars)`);

  // Call post-and-extract.mjs to handle the actual ChatGPT interaction
  console.error("");
  console.error("Posting to ChatGPT and extracting response...");

  const responseFile = outPath || "tmp/batch-response.json";
  try {
    execSync(
      `node scripts/chatgpt/post-and-extract.mjs --message-file "${requestFile}" --out "${responseFile}" --timeout 120000`,
      { encoding: "utf8", stdio: "inherit" }
    );
  } catch (e) {
    console.error(`Failed to post and extract: ${e.message}`);
    process.exit(1);
  }

  // Read the response
  if (!fs.existsSync(responseFile)) {
    console.error(`Response file not created: ${responseFile}`);
    process.exit(1);
  }

  const extractionResult = JSON.parse(fs.readFileSync(responseFile, "utf8"));

  console.error("");

  let output;

  if (extractionResult.parse_ok) {
    // Happy path: JSON parsed successfully
    output = JSON.stringify(extractionResult.extracted_json, null, 2);
    console.error(`✓ JSON parsed successfully (${output.length} chars)`);
    console.error(`✓ Raw text size: ${extractionResult.raw_text.length} chars`);
    console.error(`✓ Context burn check: Returning structured JSON`);
  } else {
    // Error path: Return raw text + error for agent to handle
    const errorResponse = {
      error: extractionResult.error || "PARSE_FAILED",
      raw_text: extractionResult.raw_text,
      message: "ChatGPT response could not be parsed as JSON. Agent should review raw_text and decide how to proceed."
    };
    output = JSON.stringify(errorResponse, null, 2);
    console.error(`✗ JSON parsing failed: ${extractionResult.error}`);
    console.error(`✗ Raw text size: ${extractionResult.raw_text.length} chars`);
    console.error(`✗ Returning error response with raw text for agent review`);
  }

  if (outPath) {
    const abs = path.isAbsolute(outPath) ? outPath : path.join(process.cwd(), outPath);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, output + "\n", "utf8");
    console.error(`✓ Response written to: ${abs}`);
  } else {
    process.stdout.write(output + "\n");
  }

  console.error("");
  console.error("=== Batch Planning Complete ===");

  process.exit(0);
})().catch((err) => {
  console.error(`batch-plan error: ${err.message}`);
  process.exit(1);
});
