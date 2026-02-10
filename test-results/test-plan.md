# AgentCore Tools Test Plan

## Test Environment
- Branch: feature/workflow-integration
- Date: 2026-02-09
- Tester: Automated

## Phase 1: Installation Tests

### 1.1 Model Adapters Installation
- [ ] Install script runs without errors
- [ ] Grok wrapper installed to ~/.local/bin
- [ ] DeepSeek wrapper installed to ~/.local/bin
- [ ] DeepSeek proxy installed
- [ ] All scripts are executable
- [ ] Commands available in PATH

### 1.2 Agent Workflow Installation
- [ ] Install script runs without errors
- [ ] All 11 commands installed to ~/.local/bin
- [ ] Library files installed to ~/.local/lib/agent_workflow
- [ ] Lib path updates applied correctly
- [ ] All scripts are executable
- [ ] Commands available in PATH

## Phase 2: Dependency Tests

### 2.1 Model Adapters Dependencies
- [ ] Grok wrapper sources lib files correctly
- [ ] DeepSeek wrapper sources lib files correctly
- [ ] No broken script references

### 2.2 Agent Workflow Dependencies
- [ ] agent-runner sources lib files
- [ ] visual-session-manager sources lib files
- [ ] All lib path references updated
- [ ] No hardcoded paths to agent-flywheel-integration

## Phase 3: Functionality Tests

### 3.1 Basic Command Tests
- [ ] Each installed command shows help/usage
- [ ] No immediate syntax errors
- [ ] Scripts can locate their dependencies

### 3.2 Integration Tests
- [ ] agent-mail-helper can connect to MCP (if running)
- [ ] visual-session-manager can launch
- [ ] hook-bypass can toggle state

## Phase 4: Uninstallation Tests
- [ ] Commands can be cleanly removed
- [ ] No orphaned files left behind

## Test Results

Results will be recorded below...
