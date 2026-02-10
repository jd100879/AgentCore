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
