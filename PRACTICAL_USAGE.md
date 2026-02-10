# AgentCore Tools - Practical Usage Guide

## Tools You Have RIGHT NOW

### 1. 📊 beads_viewer (bv) - Task Intelligence

**What it does:** AI-powered task recommendations based on your beads

**Try it now:**
```bash
cd ~/Projects/agent-flywheel-integration

# Get single best task to work on
bv --robot-next

# Get detailed triage (top 10 tasks with scores)
bv --robot-triage | jq '.triage.recommendations[:5]'

# See project health
bv --robot-triage | jq '.triage.project_health'

# Launch interactive TUI
bv
```

**What you'll see:** JSON with task ID, title, score, and reasons to work on it

---

### 2. 🐛 UBS (Ultimate Bug Scanner) - Code Quality

**What it does:** Scans code for 1000+ bug patterns (SQL injection, XSS, race conditions, etc.)

**Try it now:**
```bash
cd ~/Projects/agent-flywheel-integration

# Scan entire project
ubs

# Export to JSON
ubs --json > /tmp/bugs.json

# See summary
ubs --json | jq '{total: .findings | length, critical: [.findings[] | select(.severity=="critical")] | length}'
```

**What you'll see:** SARIF output with security vulnerabilities and code issues

---

### 3. 🔍 CASS (Coding Agent Session Search) - History Search

**What it does:** Full-text search across all your coding sessions (<60ms)

**Setup (one-time):**
```bash
# Index your coding history
cass index --full
# This takes 5-10 minutes first time
```

**Try it now:**
```bash
# Search for specific topics
cass search "authentication"
cass search "database migration"

# Check what's indexed
cass stats

# View health
cass status
```

**What you'll see:** Search results from your entire coding history

---

### 4. 📹 command_monitor (cm) - Session Recording

**What it does:** Records command history with context for AI agents

**Try it now:**
```bash
# Get context for current task
cm context "fixing login bug" --json

# Quick start guide
cm quickstart --json

# Record a session
cm record "working on auth feature"
```

**What you'll see:** Procedural memory that agents can reference

---

### 5. 🛡️ slb (Safety Lock Box) - Two-Person Rule

**What it does:** Requires approval before dangerous commands (rm -rf, git push -f)

**Try it now:**
```bash
# This will prompt for approval:
slb rm -rf /tmp/test-delete

# Check what's classified as dangerous
slb --help
```

**What you'll see:** Authorization prompts before risky operations

---

### 6. 🔄 repo_updater (ru) - Sync Repos

**What it does:** Keeps all your Git repositories in sync

**Try it now:**
```bash
# See status of all repos
ru status

# Sync all repos (clone missing, pull updates)
ru sync
```

**What you'll see:** Status of all GitHub repos

---

### 7. 🖥️ wezterm_automata (wa) - Terminal Hypervisor

**What it does:** Captures terminal output for AI agent coordination

**Try it now:**
```bash
# List all terminal panes
wa list

# Search captured output
wa search "error"

# Show version
wa version
```

**What you'll see:** Terminal pane information and search results

---

## 🚀 RECOMMENDED FIRST STEPS

### Step 1: Get Your Top Task (5 seconds)
```bash
cd ~/Projects/agent-flywheel-integration
bv --robot-next | jq -r '.title'
```

### Step 2: Scan for Bugs (30 seconds)
```bash
ubs --json | jq '[.findings[] | select(.severity=="high" or .severity=="critical")] | length'
```

### Step 3: Initialize CASS (5-10 minutes, one-time)
```bash
cass index --full
```

### Step 4: Search Your History (instant after indexing)
```bash
cass search "hooks"
```

---

## 💡 REAL WORKFLOW EXAMPLE

**Scenario:** You want to work on the highest-priority task

```bash
cd ~/Projects/agent-flywheel-integration

# 1. Get AI recommendation
TASK=$(bv --robot-next | jq -r '.id')
echo "Working on: $TASK"

# 2. See task details
br show $TASK

# 3. Scan for related bugs
ubs --json | jq ".findings[] | select(.file | contains(\"scripts\"))"

# 4. Search past work on similar issues
cass search "$(br show $TASK | grep -o 'title:.*' | cut -d: -f2)"

# 5. Start working (with command monitoring)
cm context "$TASK" --json

# 6. When done
br close $TASK
```

---

## 🎓 LEARN MORE

Each tool has detailed help:
```bash
br --help
bv --help
ubs --help
cass --help
cm --help
slb --help
ru --help
wa --help
```

## 🔥 TRY THIS RIGHT NOW

Run this one-liner to see EVERYTHING in action:

```bash
cd ~/Projects/agent-flywheel-integration && \
echo "=== TOP TASK ===" && bv --robot-next | jq -r '.title' && \
echo -e "\n=== CASS STATUS ===" && cass status && \
echo -e "\n=== PROJECT BEADS ===" && br list --json | jq 'length' | xargs echo "Total beads:"
```
