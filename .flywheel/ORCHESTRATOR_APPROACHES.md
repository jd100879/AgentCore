# Orchestrator Approaches: Comparison

We have two orchestrator implementations. Here's how they differ:

## Simplified Approach (Recommended for Most Cases)

**Script:** `scripts/start-orchestrator-simple.sh`
**Instructions:** `.flywheel/orchestrator-instructions-simple.md`

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

### Cons
- Orchestrator must be running (can't queue requests while offline)
- No request routing (but not needed for single orchestrator per project)

### When to Use
- Default choice for most projects
- When you want simplicity
- Single orchestrator per project

---

## Bridge Agent Approach (Complex)

**Script:** `scripts/start-orchestrator-agent.sh`
**Instructions:** `.flywheel/orchestrator-instructions.md` (embedded in script)

### How It Works

```
User → Orchestrator Agent → agent-mail BATCH_PLAN → Bridge Agent → batch-plan.mjs → ChatGPT
                         ↓                                              ↑
                    Worker Agents                                  agent-mail
```

**Orchestrator sends message via agent-mail:**
```bash
# Create request
cat > tmp/batch-request-msg.json << EOF
{
  "beads": ["bd-123", "bd-456"],
  "conversation_url": "https://chatgpt.com/c/..."
}
EOF

# Send to bridge
./scripts/agent-mail-helper.sh send "AzureSnow" \
  "BATCH_PLAN" \
  "$(cat tmp/batch-request-msg.json)"
```

**Bridge listens and processes:**
```bash
# Separate process (bridge-agent-loop.sh)
while true; do
  # Check for BATCH_PLAN messages
  # Call batch-plan.mjs
  # Reply with results
  sleep 3
done
```

### Pros
- **Decoupled:** Bridge runs independently
- **Queue-based:** Can queue requests while bridge restarts
- **Idempotent:** Tracks processed requests (Guard #6)

### Cons
- **Complex:** Two processes (orchestrator + bridge)
- **Message protocol:** Need to format/parse agent-mail messages
- **Harder debugging:** Multiple moving parts
- **More failure modes:** Bridge can crash, orchestrator loses connection

### When to Use
- When you need request queuing
- When multiple orchestrators share one bridge (though simplified approach works fine for this too)
- When you want message-based decoupling

---

## Token Burn Comparison

**Both approaches avoid MCP context burn equally:**

1. **MCP Playwright** (what we're avoiding):
   ```
   Agent → MCP Playwright → Browser → ChatGPT
         ← Full HTML/DOM (100KB+) in agent context
   ```
   ❌ Burns agent tokens with massive browser state

2. **Simplified Approach**:
   ```
   Orchestrator → batch-plan.mjs (subprocess) → Playwright → ChatGPT
               ← Structured JSON (~2KB) in agent context
   ```
   ✅ Only JSON in agent context

3. **Bridge Approach**:
   ```
   Orchestrator → agent-mail → Bridge → batch-plan.mjs (subprocess) → Playwright → ChatGPT
               ← Structured JSON (~2KB) in agent context
   ```
   ✅ Only JSON in agent context (but more hops)

**Result:** Both are equally efficient for token burn. The difference is architectural complexity, not performance.

---

## Multi-Project Support

### Simplified Approach
Each project has its own orchestrator:

```bash
# Project A
cd ~/ProjectA
./scripts/start-orchestrator-simple.sh
# → Uses ProjectA/.flywheel/chatgpt.json

# Project B
cd ~/ProjectB
./scripts/start-orchestrator-simple.sh
# → Uses ProjectB/.flywheel/chatgpt.json
```

**No conflicts:** Each orchestrator is independent.

### Bridge Approach
You could have:
- **Option 1:** One bridge per project (same as simplified, but more complex)
- **Option 2:** One shared bridge for all projects (requires routing logic)

**Option 2 not implemented yet** - would need bridge to route requests by project key.

---

## Recommendation

**Use the simplified approach** (`start-orchestrator-simple.sh`) unless you have a specific need for message queuing or request decoupling.

The original bridge approach was designed before we realized how simple direct calls could be. It adds complexity without significant benefit for most use cases.

---

## Migration Path

If you're using the bridge approach and want to simplify:

1. Stop the bridge: `Ctrl+C` on bridge terminal
2. Use `start-orchestrator-simple.sh` instead of `start-orchestrator-agent.sh`
3. Orchestrator instructions are updated to call batch-plan.mjs directly
4. No other changes needed (batch-plan.mjs and post-and-extract.mjs stay the same)
