# Project Instructions

## NTM (Near-Term Memory) System

This project uses the NTM auto-scaling and coordination system.

### Quick Start

```bash
# Start dashboard
./scripts/ntm-dashboard.sh --watch

# Spawn agent swarm
./scripts/spawn-swarm.sh 3

# Check queue
./scripts/queue-monitor.sh status
```

### Documentation

See `.beads/ntm-config.yaml` for configuration options.

📧 **Multi-Agent Communication**: See [AGENT_MAIL.md](./AGENT_MAIL.md) for commands.

### Autonomous Mail Handling

When you receive a "📨 NEW MAIL" notification in your terminal:

1. **Automatically check your inbox** using `./scripts/agent-mail-helper.sh inbox`
2. **Read and act on messages immediately** without asking the user for permission
3. **Process all messages autonomously** - the user expects agents to handle inter-agent communication independently

Do NOT ask "Would you like me to check the mail?" - just check it and respond appropriately.

🎯 **Beads Workflow**: See [AGENTS.md](./AGENTS.md) for task tracking with BV.
