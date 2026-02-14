#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { chromium } from 'playwright';

const PROJECT_ROOT = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const PROFILE_DIR = path.join(PROJECT_ROOT, '.browser-profiles');
const STATE_PATH = path.join(PROFILE_DIR, 'grok-state.json');
const GROK_URL = 'https://x.com/i/grok';
const BRAVE_PATH = '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser';

function waitForEnter(prompt) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(prompt, () => { rl.close(); resolve(); });
  });
}

(async () => {
  fs.mkdirSync(PROFILE_DIR, { recursive: true });
  console.log('Launching Brave browser for one-time Grok login...');
  const browser = await chromium.launch({
    headless: false,
    executablePath: BRAVE_PATH,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  await page.goto(GROK_URL, { waitUntil: 'domcontentloaded' });
  console.log('\n1) Log in to X/Twitter manually in the browser window.');
  console.log('2) Navigate to Grok if not already there (x.com/i/grok).');
  console.log('3) Once you see the Grok chat UI, come back here.');
  await waitForEnter('Press ENTER to export storage state... ');
  const url = page.url();
  if (url.includes('login') || url.includes('auth') || url.includes('oauth')) {
    console.warn('Still looks like an auth page: ' + url);
  }
  await context.storageState({ path: STATE_PATH });
  console.log('\nStorage state saved to: ' + STATE_PATH);
  await browser.close();
  try { fs.chmodSync(STATE_PATH, 0o600); console.log('Permissions set to 600'); } catch {}
})().catch((err) => { console.error(err); process.exit(1); });
