# Orchestrator Architecture

We use a **direct approach** where the orchestrator calls ChatGPT utilities directly.

## How It Works

**Script:** `scripts/start-orchestrator.sh`
**Instructions:** `.flywheel/orchestrator-instructions.md`

### How It Works

```
User → Orchestrator Agent → batch-plan.mjs → post-and-extract.mjs → ChatGPT
                         ↓
                    Worker Agents
```

**Orchestrator calls batch-plan.mjs directly:**
```bash
node scripts/chatgpt/batch-plan.mjs \
  --beads "bd-123,bd-456" \
  --conversation-url "$(jq -r .crt_url .flywheel/chatgpt.json)" \
  --out "tmp/batch-response.json"
```

### Pros
- **Simpler:** Fewer processes, no message queue protocol
- **Direct:** Orchestrator calls ChatGPT utilities directly
- **Multi-project:** Each project's orchestrator runs independently
- **Transparent:** Easy to debug (single call chain)
- **Token efficient:** Still avoids MCP context burn (subprocess runs Playwright)

### Benefits
- **Simple:** Single process, direct calls
- **Transparent:** Easy to debug (single call chain)
- **Token efficient:** Avoids MCP context burn (subprocess runs Playwright)
- **Multi-project:** Each project's orchestrator runs independently

---

## Token Burn Efficiency

**Why this approach avoids context burn:**

**MCP Playwright** (what we're avoiding):
```
Agent → MCP Playwright → Browser → ChatGPT
      ← Full HTML/DOM (100KB+) in agent context
```
❌ Burns agent tokens with massive browser state

**Our approach:**
```
Orchestrator → batch-plan.mjs (subprocess) → Playwright → ChatGPT
            ← Structured JSON (~2KB) in agent context
```
✅ Only JSON in agent context

The subprocess handles all browser interaction and returns only the parsed JSON response.

---

## Multi-Project Support

Each project has its own orchestrator:

```bash
# Project A
cd ~/ProjectA
./scripts/start-orchestrator.sh
# → Uses ProjectA/.flywheel/chatgpt.json

# Project B
cd ~/ProjectB
./scripts/start-orchestrator.sh
# → Uses ProjectB/.flywheel/chatgpt.json
```

**No conflicts:** Each orchestrator is independent.
