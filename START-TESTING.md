# Start Here: Testing AgentCore Tools

## Current Status
- ✅ Tools installed to ~/.local/bin
- ✅ Basic installation tests passed
- ✅ 2 critical bugs found and fixed
- ⏸ Manual testing NOT started yet

## DO NOT MERGE until manual testing complete

## Quick Start Testing

### Step 1: Verify MCP Agent Mail is installed
```bash
cd ~/Projects/AgentCore/mcp_agent_mail
test -f venv/bin/activate && echo "✓ MCP installed" || echo "❌ Need to install MCP first"
```

If not installed:
```bash
cd ~/Projects/AgentCore/mcp_agent_mail
./install.sh
```

### Step 2: Start MCP server
```bash
cd ~/Projects/AgentCore/mcp_agent_mail
source venv/bin/activate
python -m mcp_agent_mail serve-http
```

Leave this running in a separate terminal.

### Step 3: Test agent-mail-helper
```bash
# In a new terminal
agent-mail-helper register "Test Agent"
agent-mail-helper whoami
agent-mail-helper list
```

### Step 4: Follow full test plan
See: `test-results/manual-test-plan.md`

## Test Documentation

- **Automated Tests:** `test-results/test-results.md` (COMPLETED ✅)
- **Manual Tests:** `test-results/manual-test-plan.md` (NOT STARTED ⏸)

## Feature Branch Info

**Branch:** feature/workflow-integration  
**Commits:** 7 total  
**Files changed:** 28  
**Lines added:** 7,440

## What's Been Tested So Far

✅ Installation works  
✅ Commands in PATH  
✅ Lib dependencies resolved  
✅ No syntax errors  
✅ Basic help/usage works

## What Needs Testing

❌ MCP integration in real workflow  
❌ Multi-agent communication  
❌ Task management tools (br-start-work, bv-claim, etc.)  
❌ Monitoring tools (mail-monitor-ctl, terminal-inject)  
❌ Session management (visual-session-manager, agent-runner)  
❌ Model adapters (grok, deepseek)  
❌ Edge cases and error handling  
❌ Full multi-agent workflow

## When Testing is Complete

Once all manual tests pass and you're satisfied:

```bash
cd ~/Projects/AgentCore
git checkout main
git merge feature/workflow-integration
git push origin main
```

## If Issues Are Found

Report issues in test-results/manual-test-plan.md and we'll fix them before merging.
