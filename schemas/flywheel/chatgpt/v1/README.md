# Flywheel ChatGPT Protocol (v1)

## Overview

The Flywheel ChatGPT Protocol enables structured, JSON-based communication between AgentCore's multi-agent system and ChatGPT. It provides a formal request/response pattern for:

- **Planning** - Request implementation plans with risks and acceptance criteria
- **Arbitration** - Get decisions on technical tradeoffs and design choices
- **Evidence Review** - Submit work artifacts for review and feedback
- **Spec Locking** - Finalize API contracts, schemas, and interfaces
- **Acceptance Gates** - Validate completion against acceptance criteria

## Architecture

```
Agent → packet-build.mjs → ChatGPT (via Bridge) → ChatGPT Response → packet-validate.mjs → Agent
```

**Key Components:**
- **Packet Builder** (`scripts/chatgpt/packet-build.mjs`) - Generates protocol-compliant request packets
- **Packet Validator** (`scripts/chatgpt/packet-validate.mjs`) - Validates packets against JSON schemas
- **Bridge Agent** (future) - Sends packets to ChatGPT via Playwright MCP and extracts responses
- **Schemas** - 12 JSON Schema files defining message contracts

## Pool-Based Agent Model

This protocol uses **pool-based assignment** instead of named agents:

```json
{
  "task": "Install JWT library",
  "assign_to": "any",
  "notes": "Step-by-step instructions:\n1. Run: npm install jsonwebtoken\n2. Verify: npm list jsonwebtoken\n3. Import in auth.js: import jwt from 'jsonwebtoken'"
}
```

**Key Principle:** Write detailed instructions in `notes` so any general-purpose agent can execute the task. Use `assign_to: "any"` unless a special capability is required.

## Message Types

### Requests (Agent → ChatGPT)

1. **RFP_PLAN** - Request for Plan
   - Ask ChatGPT to design an implementation approach
   - Returns: plan steps, risks, acceptance tests, next actions

2. **RFP_ARBITRATE** - Request for Arbitration
   - Present multiple options for a technical decision
   - Returns: decision, rationale, tradeoffs, next actions

3. **EVIDENCE_BUNDLE** - Evidence Submission
   - Submit logs, diffs, test results for review
   - Returns: findings, missing evidence, next actions

4. **SPEC_LOCK** - Specification Lock
   - Finalize API contracts, schemas, event names
   - Returns: locked spec document, next actions

5. **ACCEPTANCE_GATE** - Acceptance Validation
   - Verify work meets acceptance criteria
   - Returns: pass/fail verdict, evidence, failed reasons, next actions

### Responses (ChatGPT → Agent)

All responses include:
- `verdict` - "ok", "revise", "reject", or "error"
- `next_actions[]` - Pool-friendly tasks with detailed instructions
- Message-specific fields (plan, decision, findings, spec, acceptance)

## Usage Examples

### Build a Request Packet

```bash
# Create context file
cat > tmp/context.json <<EOF
{
  "repo": "AgentCore",
  "branch": "feature/auth",
  "goal": "Add JWT authentication to API",
  "constraints": ["stateless", "rotate secrets monthly"]
}
EOF

# Build RFP_PLAN packet
node scripts/chatgpt/packet-build.mjs \
  --type RFP_PLAN \
  --bead bd-auth-jwt \
  --sender QuietDune \
  --context tmp/context.json \
  --question "Design JWT auth flow with refresh tokens" \
  --question "List security risks and mitigations" \
  --out tmp/packet.json
```

### Validate a Packet

```bash
# Validate request
node scripts/chatgpt/packet-validate.mjs --file tmp/packet.json

# Validate response (after Bridge extracts it)
cat chatgpt-response.json | node scripts/chatgpt/packet-validate.mjs --stdin
```

### Send to ChatGPT (via Bridge - future)

```bash
# Bridge agent will:
# 1. Load .flywheel/chatgpt.json for conversation URL
# 2. Post packet as formatted message
# 3. Wait for ChatGPT response
# 4. Extract JSON block
# 5. Validate response schema
# 6. Return to requesting agent
./scripts/flywheel-send.sh tmp/packet.json
```

## Schema Structure

```
schemas/flywheel/chatgpt/v1/
├── common.schema.json           # Shared types (next_action, artifact, etc.)
├── envelope.schema.json         # Base request envelope
├── msg-rfp-plan.schema.json     # RFP_PLAN request
├── msg-rfp-arbitrate.schema.json
├── msg-evidence-bundle.schema.json
├── msg-spec-lock.schema.json
├── msg-acceptance-gate.schema.json
├── resp-rfp-plan.schema.json    # RFP_PLAN response
├── resp-rfp-arbitrate.schema.json
├── resp-evidence-bundle.schema.json
├── resp-spec-lock.schema.json
└── resp-acceptance-gate.schema.json
```

## Configuration

`.flywheel/chatgpt.json`:
```json
{
  "crt_url": "https://chatgpt.com/c/698de3b1-...",
  "mcp_server": "playwright-chatgpt",
  "writer_agent": "QuietDune"
}
```

- `crt_url` - Dedicated ChatGPT conversation for this project
- `mcp_server` - Playwright MCP server name (must be configured with storage state)
- `writer_agent` - Agent authorized to post to ChatGPT (prevents concurrent writes)

## Next Actions (Implementation Roadmap)

### Phase 1: Schema Foundation ✅ COMPLETE
- [x] Create 12 JSON schema files
- [x] Implement packet-build.mjs
- [x] Implement packet-validate.mjs
- [x] Install ajv + ajv-formats
- [x] Test with sample packet

### Phase 2: Bridge Component (TODO)
- [ ] Create scripts/chatgpt/bridge-post.mjs
  - Load .flywheel/chatgpt.json
  - Use Playwright MCP to navigate to conversation
  - Format packet as markdown code block
  - Post to ChatGPT
  - Wait for response (polling or streaming)
- [ ] Create scripts/chatgpt/bridge-extract.mjs
  - Extract JSON code block from ChatGPT response
  - Validate against response schema
  - Return validated JSON

### Phase 3: Bead Integration (TODO)
- [ ] Add flywheel lifecycle hooks to bead state machine
- [ ] Trigger RFP_PLAN when bead enters "needs-plan" state
- [ ] Trigger EVIDENCE_BUNDLE before completion
- [ ] Trigger ACCEPTANCE_GATE at completion
- [ ] Store packet/response pairs in .beads/flywheel/

### Phase 4: Safety & Governance (TODO)
- [ ] Single-writer lock (prevent concurrent ChatGPT posts)
- [ ] Idempotency keys (prevent duplicate requests)
- [ ] Session expiry detection (auth check before posting)
- [ ] Rate limiting (respect ChatGPT usage limits)
- [ ] Audit trail (log all packets sent/received)

## Contributing

When extending this protocol:

1. **Add new message types** - Create msg-*.schema.json and resp-*.schema.json
2. **Update common types** - Modify common.schema.json, test all schemas still validate
3. **Preserve pool model** - Keep `notes` detailed enough for any agent to execute
4. **Validate everything** - Run packet-validate.mjs on all packets before sending

## References

- ChatGPT Planning Conversation: https://chatgpt.com/c/698de3b1-63c8-8329-b1b9-5e916d806e4b
- JSON Schema 2020-12: https://json-schema.org/draft/2020-12/schema
- AJV Validator: https://ajv.js.org/
