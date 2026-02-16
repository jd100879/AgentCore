#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { chromium } from 'playwright';

const HOME = process.env.HOME;
const PROFILE_DIR = path.join(HOME, '.flywheel', 'browser-profiles');
const STATE_PATH = path.join(PROFILE_DIR, 'chatgpt-state.json');
const CHATGPT_URL = 'https://chatgpt.com/';
const BRAVE_PATH = '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser';

function waitForEnter(prompt) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(prompt, () => { rl.close(); resolve(); });
  });
}

(async () => {
  fs.mkdirSync(PROFILE_DIR, { recursive: true });
  console.log('Launching Brave browser for one-time ChatGPT login...');
  const browser = await chromium.launch({
    headless: false,
    executablePath: BRAVE_PATH,
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await context.newPage();
  await page.goto(CHATGPT_URL, { waitUntil: 'domcontentloaded' });
  console.log('\n1) Log in manually in the browser window.');
  console.log('2) Once you see the chat UI, come back here.');
  await waitForEnter('Press ENTER to export storage state... ');
  const url = page.url();
  if (url.includes('login') || url.includes('auth')) {
    console.warn('Still looks like an auth page: ' + url);
  }
  await context.storageState({ path: STATE_PATH });
  console.log('\nStorage state saved to: ' + STATE_PATH);
  await browser.close();
  try { fs.chmodSync(STATE_PATH, 0o600); console.log('Permissions set to 600'); } catch {}
})().catch((err) => { console.error(err); process.exit(1); });
