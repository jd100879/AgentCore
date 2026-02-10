# Flywheel Tools Installation Guide

This guide walks through installing Flywheel Tools into your project.

## Prerequisites

Before installing Flywheel Tools, ensure you have:

### Required Components

1. **beads_rust** (`br` command)
   ```bash
   # Install via curl
   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" | bash

   # Verify installation
   br --version
   ```

2. **MCP Agent Mail** server
   ```bash
   # Install in your preferred location
   cd ~/tools
   curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/mcp_agent_mail/main/scripts/install.sh?$(date +%s)" | bash -s -- --yes

   # Server will start on port 8765
   # Verify with: curl -s http://localhost:8765/health
   ```

3. **tmux** (version 3.0+)
   ```bash
   # macOS
   brew install tmux

   # Ubuntu/Debian
   sudo apt-get install tmux

   # Verify
   tmux -V
   ```

4. **jq** (JSON processor)
   ```bash
   # macOS
   brew install jq

   # Ubuntu/Debian
   sudo apt-get install jq
   ```

5. **bash** (version 4.0+)
   ```bash
   # Check version
   bash --version
   ```

### Optional Components

- **Python 3.8+**: For some utility scripts
- **yq**: For YAML processing in type inference
- **Beads Viewer** (`bv`): Task visualization TUI

## Installation Methods

### Method 1: Using install.sh (Recommended)

The `install.sh` script creates symlinks from your project to the Flywheel Tools scripts:

```bash
# 1. Navigate to flywheel_tools
cd /path/to/AgentCore/flywheel_tools

# 2. Run installer with your project path
./install.sh /path/to/your/project

# 3. Follow prompts to:
#    - Create scripts/ directory (if needed)
#    - Symlink core scripts
#    - Set up configuration
#    - Initialize hooks
```

**What the installer does:**
- Creates `scripts/` directory in your project
- Symlinks Flywheel Tools scripts by category
- Sets up `.agent-profiles/types.yaml` for work briefs
- Configures git hooks for workflow automation
- Creates `config/` for project-specific settings

### Method 2: Manual Installation

For more control over the installation:

```bash
# 1. Create project structure
cd /path/to/your/project
mkdir -p scripts/{core,hooks,beads,terminal,fleet,monitoring,dev,adapters,lib}
mkdir -p .agent-profiles
mkdir -p config

# 2. Symlink scripts by category
ln -s /path/to/AgentCore/flywheel_tools/scripts/core/* scripts/core/
ln -s /path/to/AgentCore/flywheel_tools/scripts/hooks/* scripts/hooks/
ln -s /path/to/AgentCore/flywheel_tools/scripts/beads/* scripts/beads/
# ... repeat for other categories

# 3. Set up configuration
cp /path/to/AgentCore/flywheel_tools/config/types.yaml.example .agent-profiles/types.yaml

# 4. Initialize git hooks
cd .git/hooks
ln -s ../../scripts/hooks/pre-edit-check-hook.sh pre-edit
ln -s ../../scripts/hooks/post-bash-bead-track-hook.sh post-bash
# ... see hooks documentation for full list
```

## Post-Installation Configuration

### 1. Set Environment Variables

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, or project `.envrc`):

```bash
# Required
export PROJECT_ROOT="/absolute/path/to/your/project"
export MAIL_PROJECT_KEY="$PROJECT_ROOT"

# Optional tuning
export AGENT_RUNNER_IDLE_SLEEP=60        # Seconds to sleep when no beads
export AGENT_RUNNER_MAX_IDLE=10          # Max idle checks before exit
export AGENT_RUNNER_MAX_RESTARTS=5       # Max crash restarts
export PIDS_DIR="/tmp"                   # PID and state files location
```

### 2. Initialize Beads

```bash
cd /path/to/your/project
br init
```

This creates `.beads/` directory for task tracking.

### 3. Register Agent Identity

Each agent needs a unique identity:

```bash
# First time setup
export MAIL_PROJECT_KEY="/path/to/your/project"
./scripts/agent-mail-helper.sh register "Your agent role description"

# Verify registration
./scripts/agent-mail-helper.sh whoami
```

### 4. Configure Work Brief Types (Optional)

Edit `.agent-profiles/types.yaml` to customize work brief templates:

```yaml
agent_types:
  - name: backend
    description: Backend API development
    constraints_template: |
      CONSTRAINTS:
      - Do NOT modify frontend code
      - MUST write unit tests
      - MUST update API documentation

  - name: frontend
    description: Frontend UI development
    constraints_template: |
      CONSTRAINTS:
      - Do NOT modify backend APIs
      - MUST test in multiple browsers
      - MUST follow design system
```

### 5. Verify Installation

Run the doctor script to check your setup:

```bash
./scripts/doctor.sh
```

This checks:
- All required dependencies
- Environment variables
- MCP Agent Mail server connectivity
- Beads initialization
- Hook installation
- File permissions

Expected output:
```
✓ bash version 5.1.16
✓ tmux version 3.3a
✓ jq version 1.6
✓ br (beads_rust) installed
✓ MCP Agent Mail server responding
✓ PROJECT_ROOT set
✓ Beads initialized
✓ Hooks installed (8/8)
✓ Agent identity registered: TurquoiseGrove

All checks passed!
```

## Integration with Existing Projects

### Adding to Git Repository

Add Flywheel Tools references to your `.gitignore`:

```gitignore
# Flywheel Tools state
.beads/
.agent-profiles/identities/
.session-state/
/tmp/agent-*.txt
*.mail-queue
runner-cycles.jsonl
```

Commit the configuration:

```bash
git add scripts/ .agent-profiles/types.yaml config/
git commit -m "Add Flywheel Tools infrastructure"
```

### tmux Integration

Add to your `.tmux.conf`:

```bash
# Enable hooks for Flywheel Tools
set-hook -g session-created 'run-shell "scripts/hooks/session-start-hook.sh"'
set-hook -g session-closed 'run-shell "scripts/hooks/session-stop-hook.sh"'

# Optional: Status bar integration
set -g status-right '#(scripts/fleet-tmux-status.sh) %H:%M'
```

### Claude Code Integration

Add to your project's `CLAUDE.md`:

```markdown
## Beads Workflow (MANDATORY)

All work MUST be tracked with a bead. Hooks block edits without one.

- Start work: `./scripts/br-start-work.sh "Title"` or `./scripts/bv-claim.sh`
- Create sub-beads: `./scripts/br-create.sh "Title" --parent bd-xxx`
- Commits: `git commit -m "[bd-xxx] message"`
- Close: `br close bd-xxx`
```

## Upgrading

To upgrade Flywheel Tools:

```bash
# 1. Pull latest AgentCore changes
cd /path/to/AgentCore
git pull

# 2. Reinstall (updates symlinks)
cd flywheel_tools
./install.sh /path/to/your/project --upgrade

# 3. Review migration notes
cat docs/migration-status.md
```

## Uninstalling

To remove Flywheel Tools:

```bash
# 1. Remove symlinks
cd /path/to/your/project
rm -rf scripts/{core,hooks,beads,terminal,fleet,monitoring,dev,adapters,lib}

# 2. Remove hooks
cd .git/hooks
rm pre-edit post-bash pre-commit  # etc.

# 3. (Optional) Remove state
rm -rf .beads .agent-profiles .session-state

# 4. (Optional) Unregister agent
./scripts/agent-mail-helper.sh unregister
```

## Troubleshooting

### "br: command not found"

beads_rust is not installed or not in PATH:

```bash
# Reinstall
curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/beads_rust/main/install.sh?$(date +%s)" | bash

# Add to PATH (installer should do this)
export PATH="$HOME/.cargo/bin:$PATH"
```

### "MCP Agent Mail server not responding"

Server is not running:

```bash
# Check if server is running
curl -s http://localhost:8765/health

# Start server
cd /path/to/mcp_agent_mail
./scripts/run_server_with_token.sh

# Or use alias (if installer created it)
am
```

### Hooks not triggering

Hooks may not be executable or not linked:

```bash
# Make hooks executable
chmod +x .git/hooks/*

# Verify links
ls -la .git/hooks/

# Reinstall hooks
./install.sh /path/to/your/project --hooks-only
```

### Agent identity not persisting

Agent mail may be using different project key:

```bash
# Check current identity
./scripts/agent-mail-helper.sh whoami

# Verify MAIL_PROJECT_KEY
echo $MAIL_PROJECT_KEY

# Re-register with correct key
export MAIL_PROJECT_KEY="/correct/path"
./scripts/agent-mail-helper.sh register "Agent role"
```

## Next Steps

After installation:

1. Read the [Quick Start Guide](quick-start.md)
2. Create your first bead: `./scripts/br-create.sh "Setup project"`
3. Launch an autonomous agent: `./scripts/agent-runner.sh`
4. Explore [Script Reference](scripts-reference.md) for available tools

## Support

- **Issues**: https://github.com/Dicklesworthstone/AgentCore/issues
- **Docs**: https://agent-flywheel.com
- **Community**: Agent Flywheel Discord
