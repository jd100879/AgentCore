#!/bin/bash
# Health check script for agent-flywheel
# Verifies all dependencies and services are working correctly

set -uo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

echo -e "${BLUE}${BOLD}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║   Agent-Flywheel Health Check                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

check_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASSED++)) || true
}

check_fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAILED++)) || true
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARNINGS++)) || true
}

# 1. System Dependencies
echo -e "${BOLD}1. System Dependencies${NC}"

command -v tmux &>/dev/null && check_pass "tmux installed" || check_fail "tmux not found"
command -v jq &>/dev/null && check_pass "jq installed" || check_fail "jq not found"
command -v docker &>/dev/null && check_pass "docker installed" || check_fail "docker not found"
command -v python3 &>/dev/null && check_pass "python3 installed" || check_fail "python3 not found"
command -v git &>/dev/null && check_pass "git installed" || check_fail "git not found"
command -v curl &>/dev/null && check_pass "curl installed" || check_fail "curl not found"

# 2. Docker Status
echo -e "\n${BOLD}2. Docker Status${NC}"

if docker ps &>/dev/null; then
    check_pass "Docker is running"
else
    check_warn "Docker not running - agent mail won't work"
fi

# 3. MCP Agent Mail
echo -e "\n${BOLD}3. MCP Agent Mail${NC}"

MCP_DIR="${MCP_AGENT_MAIL_DIR:-$HOME/mcp_agent_mail}"
if [ -d "$MCP_DIR" ]; then
    check_pass "MCP Agent Mail directory found: $MCP_DIR"

    if [ -f "$MCP_DIR/.env" ]; then
        check_pass "MCP .env file exists"
    else
        check_warn ".env file not found - server may not be configured"
    fi
else
    check_fail "MCP Agent Mail not found at $MCP_DIR"
fi

# Check if MCP server is running
if docker ps 2>/dev/null | grep -q "8765.*8765"; then
    check_pass "MCP Agent Mail server running (port 8765)"
elif curl -s http://127.0.0.1:8765/health &>/dev/null; then
    check_pass "MCP Agent Mail server running (port 8765)"
else
    check_warn "MCP server not running on port 8765"
    echo -e "   ${BLUE}Start it: cd $MCP_DIR && docker-compose up -d${NC}"
fi

# 4. Python Environment
echo -e "\n${BOLD}4. Python Environment${NC}"

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
check_pass "Python version: $PYTHON_VERSION"

# Check if Python bin is in PATH
if [[ "$OSTYPE" == "darwin"* ]]; then
    PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PYTHON_BIN="$HOME/Library/Python/$PY_VER/bin"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    PYTHON_BIN="$HOME/.local/bin"
fi

if [[ ":$PATH:" == *":$PYTHON_BIN:"* ]]; then
    check_pass "Python bin directory in PATH"
else
    check_warn "Python bin ($PYTHON_BIN) not in PATH"
    echo -e "   ${BLUE}Add: export PATH=\"$PYTHON_BIN:\$PATH\"${NC}"
fi

# 5. Tmux Configuration
echo -e "\n${BOLD}5. Tmux Configuration${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLYWHEEL_ROOT="$(dirname "$SCRIPT_DIR")"
TMUX_CONF="$FLYWHEEL_ROOT/.tmux.conf.agent-flywheel"

if [ -f "$TMUX_CONF" ]; then
    check_pass "Tmux config found"
else
    check_warn "Tmux config not found - will be created on first run"
fi

# Check if tmux is accessible
if tmux -V &>/dev/null; then
    TMUX_VERSION=$(tmux -V | awk '{print $2}')
    check_pass "Tmux version: $TMUX_VERSION"
fi

# 6. Active Sessions
echo -e "\n${BOLD}6. Active Tmux Sessions${NC}"

SESSION_COUNT=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
if [ "$SESSION_COUNT" -gt 0 ]; then
    check_pass "$SESSION_COUNT active tmux session(s)"
    tmux list-sessions 2>/dev/null | while read line; do
        echo -e "   ${BLUE}→${NC} $line"
    done
else
    echo -e "   ${BLUE}No active sessions${NC}"
fi

# 7. File Permissions
echo -e "\n${BOLD}7. File Permissions${NC}"

if [ -x "$SCRIPT_DIR/start-multi-agent-session.sh" ]; then
    check_pass "Main launcher is executable"
else
    check_fail "Main launcher not executable"
    echo -e "   ${BLUE}Fix: chmod +x $SCRIPT_DIR/start-multi-agent-session.sh${NC}"
fi

if [ -x "$FLYWHEEL_ROOT/install.sh" ]; then
    check_pass "Installer is executable"
else
    check_warn "Installer not executable (not critical)"
fi

# 8. Network Ports
echo -e "\n${BOLD}8. Network Ports${NC}"

# Check if port 8765 is available or in use
if lsof -Pi :8765 -sTCP:LISTEN -t &>/dev/null 2>&1 || netstat -an 2>/dev/null | grep -q ":8765.*LISTEN"; then
    check_pass "Port 8765 is in use (MCP server)"
else
    check_warn "Port 8765 not in use"
fi

# 9. Git Repository
echo -e "\n${BOLD}9. Git Repository${NC}"

if [ -d "$FLYWHEEL_ROOT/.git" ]; then
    check_pass "Git repository found"

    BRANCH=$(git -C "$FLYWHEEL_ROOT" branch --show-current 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        check_pass "Current branch: $BRANCH"
    fi

    if git -C "$FLYWHEEL_ROOT" status --porcelain 2>/dev/null | grep -q .; then
        check_warn "Working tree has uncommitted changes"
    else
        check_pass "Working tree is clean"
    fi
else
    check_warn "Not a git repository"
fi

# 10. Environment Variables
echo -e "\n${BOLD}10. Environment Variables${NC}"

if [ -n "${MCP_AGENT_MAIL_DIR:-}" ]; then
    check_pass "MCP_AGENT_MAIL_DIR is set: $MCP_AGENT_MAIL_DIR"
else
    check_warn "MCP_AGENT_MAIL_DIR not set (will use default)"
fi

# Check for AI authentication (either API key or Codex OAuth)
if [ -f "$HOME/.codex/auth.json" ]; then
    check_pass "Codex OAuth configured (uses ChatGPT subscription)"
elif [ -n "${OPENAI_API_KEY:-}" ]; then
    check_pass "OPENAI_API_KEY is set"
else
    check_warn "No AI authentication configured"
    echo "         Run: ./scripts/setup-codex-oauth.sh"
    echo "         Or:  ./scripts/setup-openai-key.sh"
fi

# Summary
echo -e "\n${BOLD}═════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}Summary:${NC}"
echo -e "  ${GREEN}✓ Passed: $PASSED${NC}"
if [ $WARNINGS -gt 0 ]; then
    echo -e "  ${YELLOW}⚠ Warnings: $WARNINGS${NC}"
fi
if [ $FAILED -gt 0 ]; then
    echo -e "  ${RED}✗ Failed: $FAILED${NC}"
fi

echo -e "\n"

if [ $FAILED -gt 0 ]; then
    echo -e "${RED}❌ Some critical checks failed${NC}"
    echo -e "Fix the issues above before running agent-flywheel\n"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  System is functional but has warnings${NC}"
    echo -e "Review warnings above for optimal performance\n"
    exit 0
else
    echo -e "${GREEN}✅ All systems operational!${NC}"
    echo -e "Ready to run: ${BLUE}./start${NC}\n"
    exit 0
fi
