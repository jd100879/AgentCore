# Session State - Agent Flywheel Work

**Date:** 2026-02-12
**Branch:** feature/agent-flywheel-protocol
**Agent:** OrangeLantern

## What We Learned

### 1. Formal Protocol Was Over-Engineered ❌
- Built 12 JSON schemas, validation tools (packet-build.mjs, packet-validate.mjs)
- User already has working system: PearlOwl (coordinator) → EmeraldBear (worker)
- Natural language coordination works fine for their scale
- **Decision:** Keep schemas on branch as future reference, but not needed now

### 2. What's Actually Useful ✅
**Batch Planning:**
- Multiple beads → one ChatGPT request → multiple plans back
- Reduces round trips, more efficient at scale

**Dedicated Bridge Agent:**
- Auto-restarts like existing agent runners
- Never claims worker beads (dedicated coordinator role)
- Uses external helper process to avoid MCP context burn

### 3. ChatGPT Extraction Pattern (CRITICAL - Saved to Memory)
- Last message DOM is complete even if off-screen (no scroll needed)
- Extract from last assistant message container innerText
- Regex for ```json fence
- Don't use page.content() or global pre code locator
- Two-signal gate: "Stop generating" gone + text stable

## Files Created

### Useful (Keep):
- `scripts/chatgpt/batch-plan.mjs` - Formats batch request for ChatGPT
- `scripts/chatgpt/bridge-agent-loop.sh` - Bridge agent main loop
- `scripts/start-bridge-agent.sh` - Auto-restart wrapper
- `scripts/chatgpt/post-and-extract.mjs` - External helper (NEEDS UPDATE)
- `.flywheel/chatgpt.json` - Config with conversation URL

### Reference (Keep on branch):
- `schemas/flywheel/chatgpt/v1/*.schema.json` (12 files)
- `schemas/flywheel/chatgpt/v1/README.md`

## Next Steps

1. **Update post-and-extract.mjs** with ChatGPT's recommended pattern:
   - Target last message container
   - Extract innerText
   - Regex for ```json fence
   - Two-signal wait (stop generating + stable text)

2. **Test the bridge system:**
   - Start bridge agent: `./scripts/start-bridge-agent.sh`
   - Send batch request via agent-mail
   - Verify response extraction

3. **Optional: Daemon version**
   - Keep browser warm instead of spawning fresh
   - Faster, avoids re-auth

## Important Context

**User's System:**
- Pool-based agents (no named/specialized agents)
- Beads system (br CLI - Rust)
- Agent-mail for communication
- tmux panes with auto-restart runners
- 7d-solutions platform with PearlOwl + EmeraldBear working

**Context Burn Issue:**
- Happens in THIS conversation (Claude ↔ User)
- MCP snapshots are 386KB each
- Solution: External helper process returns only JSON
- Not about browser staying open (that's for speed/auth)

**ChatGPT Conversation:**
- URL: https://chatgpt.com/c/698de3b1-63c8-8329-b1b9-5e916d806e4b
- Storage state: `.browser-profiles/chatgpt-state.json`
- MCP server: playwright-chatgpt

## Key Decisions

1. ✅ Build batch planning + bridge agent (actually useful)
2. ✅ Use external helper to avoid context burn
3. ✅ Follow ChatGPT's extraction pattern (no scroll, innerText, regex)
4. ❌ Don't implement formal protocol (over-engineered)
5. ✅ Keep browser session open for this chat (still has context)

## Git Status

```
M package-lock.json
M package.json
?? .flywheel/
?? schemas/
?? scripts/chatgpt/
?? tmp/
```

Ready to commit bridge scripts when tested.
