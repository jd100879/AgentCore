#!/usr/bin/env bash
# Self-Review Tool - Validate work before submission
# Usage: ./scripts/self-review.sh [--iteration N]
# Exit codes: 0=passed, 1=failed, 2=max iterations reached

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
MAX_ITERATIONS=3
ITERATION=${1:-1}
TIME_LIMITS=(0 300 180 120)  # Index 0 unused, then 5min, 3min, 2min

# Extract iteration number if --iteration flag is used
if [[ "${1:-}" == "--iteration" ]]; then
    ITERATION="${2:-1}"
fi

# Validate iteration
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ "$ITERATION" -lt 1 ]]; then
    ITERATION=1
fi

# Check if max iterations exceeded
if [[ "$ITERATION" -gt "$MAX_ITERATIONS" ]]; then
    echo -e "${RED}✗ Maximum review iterations ($MAX_ITERATIONS) reached${NC}"
    echo ""
    echo "You've reviewed this work 3 times. Further iterations suggest:"
    echo "  1. The issue isn't getting better with more review"
    echo "  2. The scope is too large for unattended completion"
    echo "  3. Human or peer review is needed"
    echo ""
    echo "Next steps:"
    echo "  - Request peer review via agent mail"
    echo "  - Ask for human guidance"
    echo "  - Break work into smaller tasks"
    exit 2
fi

TIME_LIMIT=${TIME_LIMITS[$ITERATION]}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Self-Review Checklist (Iteration $ITERATION/$MAX_ITERATIONS)            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Time limit: ${YELLOW}$((TIME_LIMIT / 60)) minutes${NC}"
echo ""

START_TIME=$(date +%s)

# Track failures
FAILED_CHECKS=0

usage() {
    cat <<EOF
Self-Review Tool - Validate work before submission

USAGE:
    $0 [--iteration N]

EXAMPLES:
    $0                    # First review
    $0 --iteration 2      # Second review iteration

DESCRIPTION:
    Runs through the self-review checklist from governance rules.
    Time-boxed to prevent infinite review loops:
      - Iteration 1: 5 minutes
      - Iteration 2: 3 minutes
      - Iteration 3: 2 minutes
      - Iteration 4+: Blocked (require peer/human review)

EXIT CODES:
    0 - Review passed
    1 - Review found issues
    2 - Max iterations reached

CHECKLIST SECTIONS:
    1. Code Quality
    2. Testing
    3. Documentation
    4. Safety & Governance

EOF
}

check_time_limit() {
    local current=$(date +%s)
    local elapsed=$((current - START_TIME))

    if [[ $elapsed -gt $TIME_LIMIT ]]; then
        echo ""
        echo -e "${YELLOW}⏱  Time limit exceeded ($((TIME_LIMIT / 60)) minutes)${NC}"
        echo "Moving on - don't over-optimize."
        return 1
    fi
    return 0
}

prompt_check() {
    local question="$1"
    local tip="${2:-}"

    echo -e "${BLUE}▶${NC} $question"
    if [[ -n "$tip" ]]; then
        echo -e "  ${YELLOW}Tip:${NC} $tip"
    fi

    read -p "  [y/n/skip]: " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "  ${GREEN}✓${NC}"
        return 0
    elif [[ $REPLY =~ ^[Ss]$ ]]; then
        echo -e "  ${YELLOW}⊘ Skipped${NC}"
        return 0
    else
        echo -e "  ${RED}✗${NC}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

automated_check() {
    local name="$1"
    local command="$2"
    local tip="${3:-}"

    echo -e "${BLUE}▶${NC} $name"
    if [[ -n "$tip" ]]; then
        echo -e "  ${YELLOW}Tip:${NC} $tip"
    fi

    if eval "$command" > /tmp/self-review-check.log 2>&1; then
        echo -e "  ${GREEN}✓ Passed${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Failed${NC}"
        echo -e "  ${YELLOW}Output:${NC}"
        head -10 /tmp/self-review-check.log | sed 's/^/    /'
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        return 1
    fi
}

# ============================================================================
# SECTION 1: Code Quality
# ============================================================================
echo -e "${BLUE}┌─ Code Quality ─────────────────────────────────────────────┐${NC}"
echo ""

prompt_check \
    "Does code follow existing patterns in the codebase?" \
    "Check similar files for consistency"

prompt_check \
    "Are there any obvious bugs or edge cases missed?" \
    "Think about null/empty/boundary cases"

prompt_check \
    "Is error handling appropriate?" \
    "Check for uncaught exceptions or silent failures"

prompt_check \
    "Are variable/function names clear?" \
    "Could another agent understand this in 6 months?"

echo ""
check_time_limit || exit 0

# ============================================================================
# SECTION 2: Testing
# ============================================================================
echo -e "${BLUE}┌─ Testing ──────────────────────────────────────────────────┐${NC}"
echo ""

# Check if tests exist and should be run
if [[ -d "$PROJECT_ROOT/tests" ]] || [[ -d "$PROJECT_ROOT/test" ]]; then
    echo "Checking for test files..."

    # Look for Python tests
    if command -v pytest &> /dev/null && find "$PROJECT_ROOT" -name "test_*.py" -o -name "*_test.py" | grep -q .; then
        automated_check \
            "Running Python tests (pytest)" \
            "cd '$PROJECT_ROOT' && pytest -xvs 2>&1 | head -50" \
            "Tests must pass before submission"
    else
        prompt_check \
            "Do existing tests still pass?" \
            "Run test suite if applicable"
    fi

    prompt_check \
        "Are new tests added for new functionality?" \
        "Skip if no new functionality added"

    prompt_check \
        "Has manual testing been performed?" \
        "Skip if automated tests cover everything"
else
    echo -e "${YELLOW}  ⊘ No test directory found - skipping automated tests${NC}"
    echo ""
fi

echo ""
check_time_limit || exit 0

# ============================================================================
# SECTION 3: Documentation
# ============================================================================
echo -e "${BLUE}┌─ Documentation ────────────────────────────────────────────┐${NC}"
echo ""

prompt_check \
    "Are changes self-explanatory or commented?" \
    "Complex logic should have comments explaining why"

prompt_check \
    "Is documentation updated if API/behavior changed?" \
    "Check README, docstrings, and docs/"

prompt_check \
    "Do deliverables match task requirements?" \
    "Review original task description"

echo ""
check_time_limit || exit 0

# ============================================================================
# SECTION 4: Safety & Governance
# ============================================================================
echo -e "${BLUE}┌─ Safety & Governance ──────────────────────────────────────┐${NC}"
echo ""

prompt_check \
    "No destructive operations without approval?" \
    "Check for rm -rf, git reset --hard, force push, etc."

# Check scope limits
echo -e "${BLUE}▶${NC} Checking scope limits..."
FILES_CHANGED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
LINES_CHANGED=$(git diff --cached --stat 2>/dev/null | tail -1 | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s}' || true)
LINES_CHANGED=${LINES_CHANGED:-0}

echo "  Files changed: $FILES_CHANGED (limit: 10)"
echo "  Lines changed: $LINES_CHANGED (limit: 500)"

if [[ $FILES_CHANGED -gt 10 ]]; then
    echo -e "  ${RED}✗ Exceeds file limit (10)${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
elif [[ $LINES_CHANGED -gt 500 ]]; then
    echo -e "  ${RED}✗ Exceeds line limit (500)${NC}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
else
    echo -e "  ${GREEN}✓ Within scope limits${NC}"
fi

echo ""

prompt_check \
    "No security vulnerabilities introduced?" \
    "Check for SQL injection, XSS, command injection, etc."

# Check file reservations
echo -e "${BLUE}▶${NC} Checking file reservations..."
if [[ -f "$SCRIPT_DIR/reservation-status.sh" ]]; then
    if "$SCRIPT_DIR/reservation-status.sh" | grep -q "HazyFinch"; then
        echo -e "  ${GREEN}✓ You have active reservations${NC}"
        echo ""
        read -p "  Will you release reservations after this work? [y/n]: " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "  ${GREEN}✓${NC}"
        else
            echo -e "  ${YELLOW}⚠ Remember to release reservations when done${NC}"
        fi
    else
        echo -e "  ${YELLOW}⊘ No active reservations found${NC}"
    fi
else
    echo -e "  ${YELLOW}⊘ Reservation status script not found${NC}"
fi

echo ""
check_time_limit || exit 0

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                      Review Summary                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

ELAPSED=$(($(date +%s) - START_TIME))
echo "Time taken: $((ELAPSED / 60))m $((ELAPSED % 60))s"
echo "Failed checks: $FAILED_CHECKS"
echo ""

if [[ $FAILED_CHECKS -eq 0 ]]; then
    echo -e "${GREEN}✓ Self-review PASSED${NC}"
    echo ""
    echo "Code is ready when:"
    echo "  ✓ All checklist items are checked"
    echo "  ✓ You can explain the changes clearly"
    echo "  ✓ No obvious improvements come to mind"
    echo "  ✓ Changes are minimal and focused"
    echo ""
    echo "Next steps:"
    echo "  - Commit your changes"
    echo "  - Release file reservations"
    echo "  - Update task status"
    echo "  - Notify team via agent mail"
    exit 0
else
    echo -e "${YELLOW}⚠ Self-review found $FAILED_CHECKS issue(s)${NC}"
    echo ""
    echo "Options:"
    echo "  1. Fix the issues and run review again:"
    echo "     ./scripts/self-review.sh --iteration $((ITERATION + 1))"
    echo ""
    echo "  2. Document bypass reason and proceed with caution"
    echo ""
    echo "  3. Request peer review via agent mail"
    echo ""

    if [[ $ITERATION -lt $MAX_ITERATIONS ]]; then
        echo "You have $((MAX_ITERATIONS - ITERATION)) review iteration(s) remaining."
    else
        echo -e "${RED}This was your final self-review iteration.${NC}"
        echo "Further work requires peer or human review."
    fi

    exit 1
fi
