Run this exact Bash command and nothing else:

touch "$PROJECT_ROOT/.agent-exit-restart" && echo "Exit flag set. Agent-runner will restart Claude..." && exit 0
