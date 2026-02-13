#!/usr/bin/env node
import fs from "node:fs";
import { chromium } from "playwright";

/**
 * Start a persistent Playwright browser server
 *
 * This launches a browser in server mode and outputs the WebSocket endpoint
 * that clients can connect to. This allows multiple post-and-extract.mjs
 * calls to reuse the same browser session (no window spam, no focus stealing).
 *
 * Usage:
 *   node scripts/chatgpt/start-browser-server.mjs \
 *     --pid-file .flywheel/browser-server.pid \
 *     --endpoint-file .flywheel/browser-endpoint.txt
 */

function usage(exitCode = 1) {
  console.error(`
start-browser-server.mjs

Start a persistent Playwright browser server for ChatGPT integration.

Usage:
  node scripts/chatgpt/start-browser-server.mjs \\
    [--pid-file .flywheel/browser-server.pid] \\
    [--endpoint-file .flywheel/browser-endpoint.txt] \\
    [--storage-state .browser-profiles/chatgpt-state.json]

The browser will stay open and the process will keep running.
Kill the process or send SIGTERM to stop the browser.
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

async function startBrowserServer(storageStatePath, pidFile, endpointFile) {
  console.error("=== Starting Browser Server ===");
  console.error(`Storage state: ${storageStatePath}`);
  console.error(`PID file: ${pidFile}`);
  console.error(`Endpoint file: ${endpointFile}`);
  console.error("");

  // Launch browser in server mode
  const browserServer = await chromium.launchServer({
    headless: false,  // Use headed mode to avoid detection
    args: [
      '--disable-blink-features=AutomationControlled',
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-web-security'
    ]
  });

  const wsEndpoint = browserServer.wsEndpoint();
  console.error(`✓ Browser server started`);
  console.error(`WebSocket endpoint: ${wsEndpoint}`);
  console.error("");

  // Write PID file
  const pid = process.pid;
  fs.writeFileSync(pidFile, `${pid}\n`, "utf8");
  console.error(`✓ PID ${pid} written to: ${pidFile}`);

  // Write endpoint file
  fs.writeFileSync(endpointFile, `${wsEndpoint}\n`, "utf8");
  console.error(`✓ Endpoint written to: ${endpointFile}`);
  console.error("");

  // Health check: connect and verify
  console.error("Running health check...");
  const browser = await chromium.connect(wsEndpoint);
  const version = await browser.version();
  console.error(`✓ Health check passed (browser version: ${version})`);
  await browser.close();  // Close connection, not the server
  console.error("");

  console.error("Browser server is running. Press Ctrl+C to stop.");
  console.error("");

  // Cleanup handler
  const cleanup = async () => {
    console.error("");
    console.error("Shutting down browser server...");

    // Remove files
    if (fs.existsSync(pidFile)) {
      fs.unlinkSync(pidFile);
      console.error(`✓ Removed PID file: ${pidFile}`);
    }
    if (fs.existsSync(endpointFile)) {
      fs.unlinkSync(endpointFile);
      console.error(`✓ Removed endpoint file: ${endpointFile}`);
    }

    // Close browser
    await browserServer.close();
    console.error("✓ Browser server stopped");
    process.exit(0);
  };

  process.on('SIGTERM', cleanup);
  process.on('SIGINT', cleanup);

  // Keep process alive
  setInterval(() => {}, 1000);
}

(async function main() {
  const args = parseArgs(process.argv);

  if (args.help || args.h) usage(0);

  const pidFile = args["pid-file"] || ".flywheel/browser-server.pid";
  const endpointFile = args["endpoint-file"] || ".flywheel/browser-endpoint.txt";
  const storageStatePath = args["storage-state"] || ".browser-profiles/chatgpt-state.json";

  // Check for storage state
  if (!fs.existsSync(storageStatePath)) {
    console.error(`Storage state not found: ${storageStatePath}`);
    console.error("Run: node scripts/init-chatgpt-storage-state.mjs");
    process.exit(1);
  }

  // Ensure directories exist
  const pidDir = pidFile.substring(0, pidFile.lastIndexOf("/"));
  if (pidDir && !fs.existsSync(pidDir)) {
    fs.mkdirSync(pidDir, { recursive: true });
  }
  const endpointDir = endpointFile.substring(0, endpointFile.lastIndexOf("/"));
  if (endpointDir && !fs.existsSync(endpointDir)) {
    fs.mkdirSync(endpointDir, { recursive: true });
  }

  await startBrowserServer(storageStatePath, pidFile, endpointFile);
})().catch((err) => {
  console.error(`ERROR: ${err.message}`);
  process.exit(1);
});
