#!/usr/bin/env node
/**
 * Validates Grok Playwright MCP setup
 * - Verifies storage state exists and is valid
 * - Tests browser launch with authentication
 * - Confirms navigation to Grok works
 */

import fs from 'node:fs';
import path from 'node:path';
import { chromium } from 'playwright';

const PROJECT_ROOT = path.dirname(path.dirname(new URL(import.meta.url).pathname));
const STORAGE_STATE = path.join(PROJECT_ROOT, '.browser-profiles/grok-state.json');
const GROK_URL = 'https://x.com/i/grok';
const BRAVE_PATH = '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser';

async function validateGrokSetup() {
  console.log('🔍 Validating Grok Playwright MCP setup...\n');

  // 1. Check storage state exists
  if (!fs.existsSync(STORAGE_STATE)) {
    console.error('❌ Storage state not found:', STORAGE_STATE);
    console.log('\nTo create it, run:');
    console.log('  node scripts/init-grok-storage-state.mjs');
    process.exit(1);
  }
  console.log('✓ Storage state exists:', STORAGE_STATE);

  // 2. Validate storage state is valid JSON
  try {
    const state = JSON.parse(fs.readFileSync(STORAGE_STATE, 'utf8'));
    if (!state.cookies || !Array.isArray(state.cookies)) {
      throw new Error('Invalid storage state format');
    }
    console.log('✓ Storage state is valid JSON with', state.cookies.length, 'cookies');
  } catch (err) {
    console.error('❌ Storage state is invalid:', err.message);
    process.exit(1);
  }

  // 3. Test browser launch with storage state
  console.log('\n🌐 Launching browser with storage state...');
  const browser = await chromium.launch({
    headless: false,
    executablePath: BRAVE_PATH,
    args: [
      '--disable-blink-features=AutomationControlled',
      '--window-position=2000,0', // Position off-screen
    ],
  });

  try {
    const context = await browser.newContext({
      storageState: STORAGE_STATE,
      viewport: { width: 1280, height: 800 },
    });
    console.log('✓ Browser context created with storage state');

    const page = await context.newPage();
    console.log('✓ New page created');

    // 4. Navigate to Grok
    console.log('\n🚀 Navigating to Grok...');
    await page.goto(GROK_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
    console.log('✓ Navigation successful');

    // 5. Wait a moment for page to settle
    await page.waitForTimeout(3000);

    // 6. Check if we're logged in by looking for auth indicators
    const url = page.url();
    console.log('Current URL:', url);

    if (url.includes('login') || url.includes('oauth')) {
      console.warn('⚠️  Still on login/auth page - storage state may be expired');
      console.log('   Run: node scripts/init-grok-storage-state.mjs');
    } else {
      console.log('✓ Not on login page - likely authenticated');
    }

    // 7. Take screenshot for manual verification
    const screenshotPath = path.join(PROJECT_ROOT, 'tmp/grok-validation.png');
    fs.mkdirSync(path.dirname(screenshotPath), { recursive: true });
    await page.screenshot({ path: screenshotPath, fullPage: false });
    console.log('\n📸 Screenshot saved:', screenshotPath);

    console.log('\n✅ Validation complete!');
    console.log('\nMCP Instance Config: .agent-profiles/instances/playwright-grok.json');
    console.log('Storage State: .browser-profiles/grok-state.json');
    console.log('\nTo use in MCP: tools will be prefixed with mcp__playwright-grok__browser_*');

  } finally {
    await browser.close();
  }
}

validateGrokSetup().catch((err) => {
  console.error('\n❌ Validation failed:', err.message);
  process.exit(1);
});
