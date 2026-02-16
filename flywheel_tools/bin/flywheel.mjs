#!/usr/bin/env node
/**
 * flywheel CLI dispatcher
 *
 * Clean-break contract:
 *   - Consumers call `flywheel <command> [args...]`
 *   - No consumer calls file paths like `node scripts/...`
 *   - This CLI resolves scripts relative to *this package*, not CWD
 */

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Package root = flywheel_tools/
const PKG_ROOT = path.resolve(__dirname, "..");

// Existing scripts directory
const SCRIPTS_DIR = path.resolve(PKG_ROOT, "scripts", "chatgpt");
const GROK_SCRIPTS_DIR = path.resolve(PKG_ROOT, "scripts", "adapters", "grok");

function printHelp() {
  const help = `
flywheel - Flywheel Tools CLI

Usage:
  flywheel <command> [args...]

Commands:
  browser-worker     Run browser-worker.mjs
  send-to-worker     Run send-to-worker.mjs
  batch-plan         Run batch-plan.mjs

  check-worker       Run check-worker.sh
  start-worker       Run start-worker.sh
  stop-worker        Run stop-worker.sh
  set-conversation   Run set-conversation.sh

  ask-grok           Run ask-grok.mjs

  init-chatgpt       Initialize ChatGPT authentication (one-time setup)
  init-grok          Initialize Grok authentication (one-time setup)

Examples:
  flywheel start-worker
  flywheel browser-worker --profile default
  flywheel send-to-worker --message "hello"
  flywheel set-conversation --url "https://chatgpt.com/c/..."

Notes:
  - Node scripts run with the current working directory preserved (your project),
    but the script FILE path is resolved from the flywheel_tools package.
  - Shell scripts run via bash. If you need zsh or POSIX sh, adjust below.
`.trim();
  console.log(help);
}

function fail(msg, code = 1) {
  console.error(`flywheel: ${msg}`);
  process.exit(code);
}

/**
 * Spawns a process inheriting stdio. Returns exit code via process exit.
 */
function run(cmd, args, opts = {}) {
  const child = spawn(cmd, args, {
    stdio: "inherit",
    env: process.env,
    cwd: process.cwd(), // preserve caller's cwd semantics
    ...opts,
  });

  child.on("error", (err) => fail(err.message, 1));
  child.on("close", (code) => process.exit(code ?? 1));
}

/**
 * Resolve a script path within scripts/chatgpt and verify it exists.
 */
function resolveScript(relName) {
  const full = path.resolve(SCRIPTS_DIR, relName);
  if (!existsSync(full)) {
    fail(`script not found: ${full}`);
  }
  return full;
}

/**
 * Resolve a script path within scripts/adapters/grok and verify it exists.
 */
function resolveGrokScript(relName) {
  const full = path.resolve(GROK_SCRIPTS_DIR, relName);
  if (!existsSync(full)) {
    fail(`script not found: ${full}`);
  }
  return full;
}

/**
 * Command table: maps CLI command -> runner
 * - node scripts: run `node <file> ...args`
 * - bash scripts: run `bash <file> ...args`
 */
const COMMANDS = {
  "browser-worker": (args) => run(process.execPath, [resolveScript("browser-worker.mjs"), ...args]),
  "send-to-worker": (args) => run(process.execPath, [resolveScript("send-to-worker.mjs"), ...args]),
  "batch-plan": (args) => run(process.execPath, [resolveScript("batch-plan.mjs"), ...args]),

  "check-worker": (args) => run("bash", [resolveScript("check-worker.sh"), ...args]),
  "start-worker": (args) => run("bash", [resolveScript("start-worker.sh"), ...args]),
  "stop-worker": (args) => run("bash", [resolveScript("stop-worker.sh"), ...args]),
  "set-conversation": (args) => run("bash", [resolveScript("set-conversation.sh"), ...args]),

  "ask-grok": (args) => run(process.execPath, [resolveGrokScript("ask-grok.mjs"), ...args]),

  "init-chatgpt": (args) => run(process.execPath, [resolveScript("init-chatgpt-storage-state.mjs"), ...args]),
  "init-grok": (args) => run(process.execPath, [resolveGrokScript("init-grok-storage-state.mjs"), ...args]),

  // Convenience aliases (optional)
  "bw": (args) => run(process.execPath, [resolveScript("browser-worker.mjs"), ...args]),
  "stw": (args) => run(process.execPath, [resolveScript("send-to-worker.mjs"), ...args]),
};

const argv = process.argv.slice(2);
const cmd = argv[0];

if (!cmd || cmd === "-h" || cmd === "--help" || cmd === "help") {
  printHelp();
  process.exit(0);
}

const handler = COMMANDS[cmd];
if (!handler) {
  printHelp();
  fail(`unknown command: ${cmd}`);
}

handler(argv.slice(1));
