# Playwright MCP Instances

This directory contains configurations for Playwright MCP instances. Each instance provides a dedicated browser context with its own storage state (cookies, local storage, etc.).

## Available Instances

### playwright-grok
- **URL**: https://x.com/i/grok
- **Storage State**: `.browser-profiles/grok-state.json`
- **Use Case**: Grok AI assistant on X/Twitter
- **MCP Tools**: `mcp__playwright-grok__browser_*`

Setup:
```bash
# First time: Initialize storage state
node scripts/init-grok-storage-state.mjs

# Validate setup
node scripts/validate-grok-browser.mjs
```

## Instance Configuration Format

Each instance config file should follow this format:

```json
{
  "name": "instance-name",
  "plugin": "playwright",
  "config": {
    "storageState": "/absolute/path/to/storage-state.json",
    "startUrl": "https://example.com"
  }
}
```

## Adding a New Instance

1. Create storage state:
   ```bash
   # Create based on init-grok-storage-state.mjs template
   node scripts/init-<name>-storage-state.mjs
   ```

2. Create instance config in this directory:
   ```json
   {
     "name": "playwright-<name>",
     "plugin": "playwright",
     "config": {
       "storageState": "/path/to/.browser-profiles/<name>-state.json",
       "startUrl": "https://target-url.com"
     }
   }
   ```

3. Create validation script:
   ```bash
   # Create based on validate-grok-browser.mjs template
   node scripts/validate-<name>-browser.mjs
   ```

4. Restart Claude Code session to load the new instance

## Notes

- Storage state files are stored in `.browser-profiles/` (gitignored, contains auth)
- Instance configs are committed to git (no secrets)
- Each instance provides isolated browser contexts
- Useful for maintaining separate authenticated sessions
