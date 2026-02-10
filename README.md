# AgentCore

A clean implementation of Jeffrey Emanuel's (Dicklesworthstone) multi-agent coordination system.

## Core Components

### ✅ Successfully Integrated

1. **MCP Agent Mail** (`mcp_agent_mail/`)
   - Multi-agent communication via Model Context Protocol
   - FastAPI server for agent coordination
   - [README](mcp_agent_mail/README.md)

2. **beads_rust** (`beads_rust/`)
   - Git-based task management system (br command)
   - Persistent task tracking with git backend
   - [README](beads_rust/README.md)

3. **Beads Viewer** (`beads_viewer/`)
   - Terminal UI for task visualization (bv command)
   - Graph analysis and task dependency tracking
   - [README](beads_viewer/README.md)

4. **CASS** (`coding_agent_session_search/`)
   - Coding Agent Session Search with <60ms semantic search
   - RAG-based session retrieval
   - [README](coding_agent_session_search/README.md)

5. **Ultimate Bug Scanner** (`ultimate_bug_scanner/`)
   - Multi-language static analysis tool
   - Automated code quality scanning
   - [README](ultimate_bug_scanner/README.md)

6. **Flywheel Tools** (`flywheel_tools/`)
   - Shell script infrastructure for autonomous agent workflows
   - Agent lifecycle management and coordination
   - Workflow hooks and automation
   - [README](flywheel_tools/README.md)

### ❌ Not Available
- **Named Tmux Manager (NTM)** - Repository not found (may be private or renamed)

## Extended Tools

**NEW:** AgentCore now includes extended tools for multi-agent workflows!

### [tools/](tools/) - Extended Tools & Utilities

7. **Model Adapters** (`tools/model-adapters/`)
   - Grok (xAI) and DeepSeek drop-in replacements for Claude
   - Enable multi-model agent swarms
   - [README](tools/model-adapters/README.md)

8. **Agent Workflow** (`tools/agent_workflow/`)
   - Autonomous agent execution and coordination
   - Multi-agent communication tools
   - Task management integration
   - [README](tools/agent_workflow/README.md)

Install extended tools:
```bash
cd tools/model-adapters && ./install.sh
cd tools/agent_workflow && ./install.sh
```

## Architecture

AgentCore implements the Agent Flywheel pattern:
- **File Reservations** - Advisory locking for conflict prevention
- **Agent Mail** - Asynchronous inter-agent communication
- **Task Beads** - Git-backed task persistence
- **Multi-Agent Orchestration** - tmux-based agent coordination

## Quick Start

```bash
# 1. Install MCP Agent Mail
cd mcp_agent_mail && ./install.sh && cd ..

# 2. Build beads_rust
cd beads_rust && cargo build --release && cd ..

# 3. Install Beads Viewer
cd beads_viewer && ./install.sh && cd ..

# 4. Install CASS
cd coding_agent_session_search && ./install.sh && cd ..

# 5. Install UBS
cd ultimate_bug_scanner && ./install.sh && cd ..

# 6. Install Flywheel Tools
cd flywheel_tools && ./install.sh /path/to/your/project && cd ..

# 7. Install extended tools (optional)
cd tools/agent_workflow && ./install.sh && cd ../..
cd tools/model-adapters && ./install.sh && cd ../..
```

See [GETTING_STARTED.md](GETTING_STARTED.md) for detailed installation and setup instructions.

## Project Origin

Originally "Agent Flywheel Integration", renamed to **AgentCore** to better reflect its role as foundational infrastructure for multi-agent systems.

## Status

✅ **Core Components** - 6 components installed and ready
✅ **Extended Tools** - Model adapters and workflow automation added

## Documentation

### Core Components
- [MCP Agent Mail](mcp_agent_mail/README.md)
- [beads_rust](beads_rust/README.md)
- [Beads Viewer](beads_viewer/README.md)
- [CASS](coding_agent_session_search/README.md)
- [Ultimate Bug Scanner](ultimate_bug_scanner/README.md)
- [Flywheel Tools](flywheel_tools/README.md)

### Extended Tools
- [Tools Overview](tools/README.md)
- [Model Adapters](tools/model-adapters/README.md)
- [Agent Workflow](tools/agent_workflow/README.md)

### Architecture
- [ARCHITECTURE.md](ARCHITECTURE.md) - System architecture and component integration
