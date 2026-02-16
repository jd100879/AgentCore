#!/usr/bin/env node
/**
 * Initialize Grok storage state for Playwright MCP
 * Run this once to create .browser-profiles/grok-state.json
 */

import fs from 'node:fs';
import path from 'node:path';
import readline from 'node:readline';
import { chromium } from 'playwright';

const HOME = process.env.HOME;
const PROFILE_DIR = path.join(HOME, '.flywheel', 'browser-profiles');
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

  console.log('🚀 Launching Brave browser for one-time Grok login...\n');

  const browser = await chromium.launch({
    headless: false,
    executablePath: BRAVE_PATH,
    args: ['--disable-blink-features=AutomationControlled'],
  });

  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 }
  });

  const page = await context.newPage();
  await page.goto(GROK_URL, { waitUntil: 'domcontentloaded' });

  console.log('📝 Instructions:');
  console.log('1) Log in to X/Twitter if needed');
  console.log('2) Wait for Grok chat interface to load');
  console.log('3) Come back here and press ENTER\n');

  await waitForEnter('Press ENTER to save storage state... ');

  const url = page.url();
  if (url.includes('login') || url.includes('oauth')) {
    console.warn('⚠️  Still on auth page:', url);
    console.warn('    Storage state may not include authentication');
  }

  await context.storageState({ path: STATE_PATH });
  console.log('\n✅ Storage state saved to:', STATE_PATH);

  await browser.close();

  try {
    fs.chmodSync(STATE_PATH, 0o600);
    console.log('✅ Permissions set to 600');
  } catch (err) {
    console.warn('⚠️  Could not set permissions:', err.message);
  }

  console.log('\n🎉 Setup complete! You can now use the Grok Playwright MCP instance.');
  console.log('\nValidate with: node scripts/validate-grok-browser.mjs');

})().catch((err) => {
  console.error('\n❌ Error:', err.message);
  process.exit(1);
});
