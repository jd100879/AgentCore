# AgentCore Tools

Extended tools and utilities for multi-agent workflows.

## Available Tool Sets

### [model-adapters/](model-adapters/) - AI Model Adapters
Drop-in replacements for Claude Code that enable using alternative AI models.

**Models:** Grok (xAI), DeepSeek

**Install:** `cd model-adapters && ./install.sh`

### [agent_workflow/](agent_workflow/) - Agent Workflow Tools  
Core automation and coordination tools for multi-agent development.

**Install:** `cd agent_workflow && ./install.sh`

## Installation

```bash
cd ~/Projects/AgentCore/tools
cd model-adapters && ./install.sh && cd ..
cd agent_workflow && ./install.sh && cd ..
```

All tools install to `~/.local/bin/`.

## Documentation

- [Model Adapters](model-adapters/README.md) - Grok & DeepSeek wrappers
- [Agent Workflow](agent_workflow/README.md) - Multi-agent coordination tools

See main [AgentCore README](../README.md).
