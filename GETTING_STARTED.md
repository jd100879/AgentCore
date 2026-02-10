# Getting Started with AgentCore

This guide will help you install and configure all components of AgentCore.

## Prerequisites

- **Rust** (for beads_rust): `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`
- **Python 3.8+** (for MCP Agent Mail, CASS, UBS)
- **Go 1.18+** (for Beads Viewer)
- **Git** (for task management)

## Installation Steps

### 1. MCP Agent Mail

The communication backbone for multi-agent coordination.

```bash
cd mcp_agent_mail
./install.sh
cd ..
```

This will:
- Create a Python virtual environment
- Install dependencies (FastAPI, uvicorn, httpx, etc.)
- Set up the MCP server

**Verify:**
```bash
cd mcp_agent_mail
source venv/bin/activate
python -m mcp_agent_mail.server --help
deactivate
cd ..
```

### 2. beads_rust (br)

Git-based task management system.

```bash
cd beads_rust
cargo build --release
# Install the binary
cargo install --path .
cd ..
```

**Verify:**
```bash
br --version
```

### 3. Beads Viewer (bv)

Terminal UI for visualizing task dependencies.

```bash
cd beads_viewer
./install.sh
cd ..
```

**Verify:**
```bash
bv --help
```

### 4. CASS (Coding Agent Session Search)

Semantic search for coding sessions with <60ms performance.

```bash
cd coding_agent_session_search
./install.sh
cd ..
```

**Verify:**
```bash
cd coding_agent_session_search
source venv/bin/activate
python -m cass --help
deactivate
cd ..
```

### 5. Ultimate Bug Scanner (UBS)

Multi-language static analysis for automated bug detection.

```bash
cd ultimate_bug_scanner
./install.sh
cd ..
```

**Verify:**
```bash
ubs --version
```

## Configuration

### MCP Agent Mail Setup

1. Configure the server port and settings:
```bash
cd mcp_agent_mail
cp config.example.json config.json
# Edit config.json as needed
```

2. Start the server:
```bash
source venv/bin/activate
python -m mcp_agent_mail.server
```

### Initialize a Beads Repository

```bash
# In your project directory
br init
br new "Initial setup task"
```

### View Tasks with Beads Viewer

```bash
bv
```

## Integration Testing

Once all components are installed, test the integration:

```bash
# Start MCP Agent Mail server
cd mcp_agent_mail && source venv/bin/activate && python -m mcp_agent_mail.server &
MCP_PID=$!

# Create a test bead
br init
br new "Test task for agent coordination"

# View in Beads Viewer
bv

# Stop MCP server
kill $MCP_PID
```

## Troubleshooting

### Rust Build Issues
```bash
# Update Rust
rustup update

# Clean and rebuild
cd beads_rust
cargo clean
cargo build --release
```

### Python Virtual Environment Issues
```bash
# Recreate venv
rm -rf venv
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Go Build Issues
```bash
# Ensure Go is up to date
go version  # Should be 1.18+
go mod tidy
go build
```

## Next Steps

1. **Explore Components**: Read individual READMEs in each subdirectory
2. **Configure Integration**: Set up file reservations and agent communication
3. **Build Workflows**: Create agent workflows using the Ralph Loop pattern
4. **Scan Code**: Use UBS to analyze your codebase and create improvement beads

## Architecture Overview

```
AgentCore
├── mcp_agent_mail/      # Agent communication server
├── beads_rust/          # Task management (br)
├── beads_viewer/        # Task visualization (bv)
├── coding_agent_session_search/  # Semantic search (CASS)
└── ultimate_bug_scanner/         # Static analysis (UBS)
```

## Resources

- [Agent Flywheel Vision](https://github.com/Dicklesworthstone) - Jeffrey Emanuel's repositories
- [MCP Documentation](mcp_agent_mail/README.md)
- [Beads Workflow](beads_rust/README.md)

## Support

For issues with individual components, refer to their respective README files and GitHub repositories.
