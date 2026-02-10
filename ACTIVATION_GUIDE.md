# AgentCore Activation Guide

## Where Does AgentCore Run?

AgentCore runs **locally on your machine** in your terminal environment:

- **Terminal/Shell:** Most tools are CLI utilities you run on demand
- **tmux:** NTM orchestrates multi-agent sessions in tmux windows/panes  
- **Background Services:** Some components (MCP Agent Mail, CASS) can run as background services
- **On-Demand Tools:** UBS, br, bv, slb, etc. run when you invoke them

## Quick Start: Single Agent Mode

**For using AgentCore tools in your current project:**

### 1. Initialize Beads (Task Management)
```bash
cd /path/to/your/project
br init                              # Create .beads/ directory
br create --title "Fix login bug"   # Create first task
```

### 2. View Tasks
```bash
bv                          # Launch TUI (interactive)
bv --robot-triage           # Get AI recommendations (JSON)
bv --robot-next             # Get single top task
```

### 3. Run Bug Scanner
```bash
ubs                         # Scan current directory
ubs --json > findings.json  # Export to JSON
```

### 4. Check Dependencies
```bash
ntm deps -v                 # See what's installed
```

## Using AgentCore in agent-flywheel-integration

**You already have this running!** Your agent-flywheel-integration project uses AgentCore components:

### Check Your Current Setup

```bash
cd ~/Projects/agent-flywheel-integration

# See your current agent identity
./scripts/agent-mail-helper.sh whoami

# Check inbox for tasks
./scripts/agent-mail-helper.sh inbox

# View beads
bv --robot-next
```

### Start an Agent Session

```bash
# Launch an agent runner (automated agent loop)
./scripts/agent-runner.sh

# This will:
# 1. Register with MCP Agent Mail
# 2. Check for assigned tasks
# 3. Work on beads autonomously
# 4. Report progress via agent mail
```

## Component Activation Reference

### On-Demand Tools (Run as needed)

| Tool | Command | Purpose |
|------|---------|---------|
| **beads_rust** | `br <command>` | Task management |
| **beads_viewer** | `bv` or `bv --robot-*` | Task visualization |
| **UBS** | `ubs` | Code scanning |
| **slb** | Wraps commands | Safety checks |
| **cm** | `cm <command>` | Command monitoring |
| **ru** | `ru sync` | Repo updates |
| **wa** | `wa watch` | Terminal automation |

### Background Services

**MCP Agent Mail Server:**
```bash
cd ~/Projects/AgentCore/mcp_agent_mail
source venv/bin/activate
python -m mcp_agent_mail serve-stdio
```

**CASS Indexing (one-time setup):**
```bash
cass index --full
cass status
```

## Common Workflows

### Workflow 1: Solo Development with Beads

```bash
cd ~/my-project
br init
br create --title "Implement user auth"
bv --robot-next              # Get top task
# ... do work ...
br close bd-xyz              # Close when done
```

### Workflow 2: Code Quality Audit

```bash
cd ~/my-project
ubs --json > scan-results.json       # Scan for bugs

# Create beads for each finding
jq -r '.findings[] | "br create --title \"Fix: \(.title)\""' scan-results.json | bash

# View prioritized issues
bv --robot-triage
```

## Environment Setup

Add to your ~/.bashrc or ~/.zshrc:

```bash
# AgentCore paths
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Beads configuration
export BEADS_ACTOR="$(whoami)"

# Useful aliases
alias bv-next="bv --robot-next | jq -r '.id'"
alias ubs-scan="ubs --format sarif"
```

## Checking Service Status

```bash
# Check CASS status
cass status

# Check what's in PATH
ntm deps -v

# Check tmux sessions
tmux ls

# Check beads in current project
br list --json | jq '.[] | {id, title, status}'
```

## Troubleshooting

### "Command not found: br"
```bash
which br
# If not found, reinstall:
cd ~/Projects/AgentCore/beads_rust
cargo install --path .
source ~/.cargo/env
```

### "CASS not indexed"
```bash
cass index --full
# Wait for completion
cass status
```

### Check all tools are available
```bash
ntm deps -v
```

## Next Steps

1. **Try the workflows:** Start with single-agent mode
2. **Read component docs:** Each tool has detailed docs in ~/Projects/AgentCore/*/README.md
3. **Explore agent-flywheel-integration:** Your project already uses many patterns
4. **Review test results:** See TEST_RESULTS.md for verified functionality

## Resources

- **AgentCore Repo:** https://github.com/jd100879/AgentCore
- **Test Results:** TEST_RESULTS.md
- **Installation Guide:** AGENTS.md
