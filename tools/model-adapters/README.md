# AI Model Adapters

Drop-in replacements for Claude Code that enable using alternative AI models in multi-agent workflows.

## Available Adapters

### Grok (xAI)
- **Wrapper**: `grok-claude-wrapper`
- **Setup**: `grok/setup-grok.sh`
- **API**: https://console.x.ai/
- **Model**: grok-2-latest

### DeepSeek
- **Wrapper**: `deepseek-claude-wrapper`
- **Proxy**: `deepseek-compact-proxy.py`
- **Setup**: `deepseek/setup-deepseek.sh`
- **API**: https://platform.deepseek.com/
- **Model**: deepseek-chat

## Installation

```bash
cd ~/Projects/AgentCore/tools/model-adapters
./install.sh
```

Installs to `~/.local/bin/`:
- `grok-claude-wrapper`
- `deepseek-claude-wrapper`
- `deepseek-compact-proxy.py`
- `start-deepseek-proxy`

## Setup

### Grok
```bash
cd ~/Projects/AgentCore/tools/model-adapters/grok
./setup-grok.sh
```

### DeepSeek
```bash
cd ~/Projects/AgentCore/tools/model-adapters/deepseek
./setup-deepseek.sh
```

## Usage

Use the wrappers exactly like `claude`:

```bash
# Instead of:
claude

# Use:
grok-claude-wrapper
# or
deepseek-claude-wrapper
```

## Features

- **Agent Mail Integration**: Wrappers automatically register with MCP Agent Mail
- **Session Persistence**: Maintains session state per tmux pane
- **API Compatibility**: Translates between Claude API format and provider APIs
- **Multi-Model Swarms**: Run Claude + Grok + DeepSeek agents simultaneously

## Architecture

Each wrapper:
1. Converts Claude API calls to provider format
2. Registers with agent mail system (if available)
3. Maintains session continuity
4. Handles API key management

## Dependencies

- MCP Agent Mail (optional, for multi-agent coordination)
- Provider API keys
- `~/.local/bin` in PATH

## Multi-Agent Example

```bash
# Start MCP Agent Mail server
cd ~/Projects/AgentCore/mcp_agent_mail
python -m mcp_agent_mail serve-http &

# Launch multi-model swarm
tmux new-session -s swarm \; \
  split-window -h \; \
  split-window -v \; \
  select-pane -t 0 \; send-keys "claude" C-m \; \
  select-pane -t 1 \; send-keys "grok-claude-wrapper" C-m \; \
  select-pane -t 2 \; send-keys "deepseek-claude-wrapper" C-m
```

Now you have 3 AI agents (Claude, Grok, DeepSeek) working together via agent mail!

## Notes

- Wrappers require valid API keys for their respective services
- Performance and capabilities vary by model
- Cost varies by provider (check pricing pages)
- All wrappers support the same command-line interface as Claude Code
