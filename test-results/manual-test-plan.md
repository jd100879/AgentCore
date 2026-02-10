# AgentCore Tools - Manual Testing Plan

## DO NOT MERGE until all tests pass and user is satisfied

## Test Environment Setup

### Prerequisites Check
- [ ] MCP Agent Mail server installed
- [ ] beads_rust (br) installed
- [ ] beads_viewer (bv) installed
- [ ] tmux installed
- [ ] fzf installed
- [ ] jq installed

## Test Phase 1: MCP Agent Mail Integration

### 1.1 Start MCP Server
```bash
cd ~/Projects/AgentCore/mcp_agent_mail
source venv/bin/activate
python -m mcp_agent_mail serve-http
```
- [ ] Server starts without errors
- [ ] Server listening on port 8765
- [ ] Health check passes: `curl http://localhost:8765/health`

### 1.2 Test agent-mail-helper
```bash
# Register as agent
agent-mail-helper register "Test Agent"

# Check identity
agent-mail-helper whoami

# List all agents
agent-mail-helper list

# Send test message
agent-mail-helper test-message
```
- [ ] Registration works
- [ ] Identity retrieved correctly
- [ ] List shows agents
- [ ] Test message sent successfully

### 1.3 Test multi-agent communication
```bash
# In terminal 1: Register agent 1
agent-mail-helper register "Agent Alpha"
AGENT1=$(agent-mail-helper whoami)

# In terminal 2: Register agent 2  
agent-mail-helper register "Agent Beta"
AGENT2=$(agent-mail-helper whoami)

# Agent 1 sends to Agent 2
agent-mail-helper send "$AGENT2" "Test subject" "Test message body"

# Agent 2 checks inbox
agent-mail-helper inbox
```
- [ ] Both agents register successfully
- [ ] Message sends without errors
- [ ] Message appears in recipient inbox
- [ ] Message content is correct

## Test Phase 2: Task Management Integration

### 2.1 Test in project with beads
```bash
cd ~/Projects/agent-flywheel-integration

# Test br-start-work
br-start-work "Test task integration"

# Test bv-claim
bv-claim

# Test next-bead
next-bead
```
- [ ] br-start-work creates bead
- [ ] bv-claim shows next task
- [ ] next-bead returns bead ID
- [ ] No errors about missing br/bv commands

### 2.2 Test hook-bypass
```bash
cd ~/Projects/agent-flywheel-integration

# Check status
hook-bypass status

# Enable bypass
hook-bypass on
hook-bypass status

# Disable bypass
hook-bypass off
hook-bypass status
```
- [ ] Status shows correctly
- [ ] Enable works (creates bypass file)
- [ ] Disable works (removes bypass file)
- [ ] No permission errors

## Test Phase 3: Monitoring Tools

### 3.1 Test mail monitor
```bash
# In terminal 1: Start monitor
mail-monitor-ctl start

# Check status
mail-monitor-ctl status

# In terminal 2: Send a message
agent-mail-helper broadcast "Test broadcast"

# Back to terminal 1: Verify message appears
# Check ~/.claude/logs/mail-monitor-*.log

# Stop monitor
mail-monitor-ctl stop
```
- [ ] Monitor starts successfully
- [ ] Status shows running
- [ ] Messages appear in terminal
- [ ] Monitor stops cleanly

### 3.2 Test terminal-inject
```bash
# Inject a command
terminal-inject "echo 'Test command injection'"

# Check queue file exists
ls -la ~/.claude/terminal-inject-queue.jsonl

# Verify queue format
tail -1 ~/.claude/terminal-inject-queue.jsonl | jq .
```
- [ ] Command added to queue
- [ ] Queue file created correctly
- [ ] JSON format is valid
- [ ] Timestamp has millisecond precision

## Test Phase 4: Session Management

### 4.1 Test visual-session-manager
```bash
# Launch session manager (interactive)
visual-session-manager
```
- [ ] fzf interface appears
- [ ] Shows existing sessions
- [ ] Can create new session
- [ ] Can attach to session
- [ ] Preview pane works
- [ ] No errors on exit

### 4.2 Test agent-runner
```bash
# Create a test bead first
cd ~/Projects/agent-flywheel-integration
br new "Test agent runner" > /tmp/bead-id.txt
BEAD_ID=$(cat /tmp/bead-id.txt | grep -o 'bd-[a-z0-9]*')

# Run agent-runner with bead
agent-runner "$BEAD_ID"
```
- [ ] Agent runner starts
- [ ] Registers with MCP Agent Mail
- [ ] Shows assigned bead
- [ ] Claude Code launches
- [ ] No immediate crashes

### 4.3 Test broadcast-to-swarm
```bash
# Need multiple agents registered first
broadcast-to-swarm "Hello all agents"
```
- [ ] Broadcast sends to all agents
- [ ] No errors
- [ ] All agents receive message (check with agent-mail-helper inbox)

## Test Phase 5: Model Adapters (Optional - requires API keys)

### 5.1 Test Grok adapter (if you have API key)
```bash
cd ~/Projects/AgentCore/tools/model-adapters/grok
./setup-grok.sh

# Test wrapper
grok-claude-wrapper
```
- [ ] Setup completes successfully
- [ ] API key configured
- [ ] Wrapper launches
- [ ] Connects to xAI API
- [ ] Basic interaction works

### 5.2 Test DeepSeek adapter (if you have API key)
```bash
cd ~/Projects/AgentCore/tools/model-adapters/deepseek
./setup-deepseek.sh

# Test wrapper
deepseek-claude-wrapper
```
- [ ] Setup completes successfully
- [ ] API key configured
- [ ] Wrapper launches
- [ ] Connects to DeepSeek API
- [ ] Basic interaction works

## Test Phase 6: Real Workflow Test

### 6.1 Multi-agent workflow
```bash
# 1. Start MCP server
cd ~/Projects/AgentCore/mcp_agent_mail
source venv/bin/activate
python -m mcp_agent_mail serve-http &

# 2. Create tmux session with 2 agents
tmux new-session -s test-swarm -d
tmux split-window -h -t test-swarm

# 3. Start agents in each pane
cd ~/Projects/agent-flywheel-integration
br new "Agent 1 task" > /tmp/bead1.txt
br new "Agent 2 task" > /tmp/bead2.txt

BEAD1=$(cat /tmp/bead1.txt | grep -o 'bd-[a-z0-9]*')
BEAD2=$(cat /tmp/bead2.txt | grep -o 'bd-[a-z0-9]*')

tmux send-keys -t test-swarm:0.0 "cd ~/Projects/agent-flywheel-integration && agent-runner $BEAD1" C-m
tmux send-keys -t test-swarm:0.1 "cd ~/Projects/agent-flywheel-integration && agent-runner $BEAD2" C-m

# 4. Attach and observe
tmux attach -t test-swarm
```
- [ ] Both agents start successfully
- [ ] Both register with MCP
- [ ] Agents can see each other in list
- [ ] Agents can communicate
- [ ] Work proceeds independently
- [ ] No crashes or hangs

### 6.2 Cleanup test
```bash
# Kill session
tmux kill-session -t test-swarm

# Stop MCP server
pkill -f "mcp_agent_mail"

# Clean up test beads
br close $BEAD1
br close $BEAD2
```
- [ ] Session closes cleanly
- [ ] Server stops cleanly
- [ ] No orphaned processes
- [ ] No error messages

## Test Phase 7: Edge Cases & Error Handling

### 7.1 Missing prerequisites
```bash
# Try agent-mail-helper without MCP running
pkill -f mcp_agent_mail
agent-mail-helper whoami
```
- [ ] Shows appropriate error message
- [ ] Doesn't crash or hang
- [ ] Error is user-friendly

### 7.2 Invalid input
```bash
# Try agent-runner with invalid bead
agent-runner bd-notexist
```
- [ ] Shows appropriate error
- [ ] Doesn't crash
- [ ] Error message is helpful

### 7.3 Reinstallation
```bash
# Reinstall tools
cd ~/Projects/AgentCore/tools/agent_workflow
./install.sh

cd ~/Projects/AgentCore/tools/model-adapters
./install.sh
```
- [ ] Reinstall works without errors
- [ ] No file conflicts
- [ ] Tools still work after reinstall

## Test Phase 8: Uninstallation

### 8.1 Remove all tools
```bash
# Remove commands
rm ~/.local/bin/{agent-runner,agent-mail-helper,visual-session-manager}
rm ~/.local/bin/{monitor-agent-mail,mail-monitor-ctl,terminal-inject}
rm ~/.local/bin/{br-start-work,bv-claim,next-bead,broadcast-to-swarm,hook-bypass}
rm ~/.local/bin/{grok-claude-wrapper,deepseek-claude-wrapper}
rm ~/.local/bin/{deepseek-compact-proxy.py,start-deepseek-proxy}

# Remove lib
rm -rf ~/.local/lib/agent_workflow

# Verify removal
which agent-runner
which agent-mail-helper
```
- [ ] All commands removed
- [ ] Library files removed
- [ ] Commands no longer in PATH
- [ ] No errors during removal

### 8.2 Reinstall verification
```bash
# Reinstall everything
cd ~/Projects/AgentCore/tools/agent_workflow && ./install.sh
cd ~/Projects/AgentCore/tools/model-adapters && ./install.sh

# Verify commands work
agent-mail-helper
hook-bypass status
```
- [ ] Reinstall completes successfully
- [ ] All commands work after reinstall
- [ ] No residual issues

## Final Checklist

Before merging to main, verify:
- [ ] All automated tests pass
- [ ] All manual tests pass
- [ ] MCP integration fully working
- [ ] Multi-agent workflows tested successfully
- [ ] Model adapters tested (if applicable)
- [ ] Edge cases handled gracefully
- [ ] Error messages are helpful
- [ ] Documentation is accurate
- [ ] Install/uninstall works cleanly
- [ ] No regressions in existing functionality

## Test Results

Record results here:

```
Phase 1 (MCP Integration): 
Phase 2 (Task Management): 
Phase 3 (Monitoring): 
Phase 4 (Session Management): 
Phase 5 (Model Adapters): 
Phase 6 (Real Workflow): 
Phase 7 (Edge Cases): 
Phase 8 (Uninstall): 

Overall Status: 
Ready for merge: YES / NO
Notes:
```
