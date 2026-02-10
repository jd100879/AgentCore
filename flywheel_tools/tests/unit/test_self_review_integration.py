#!/usr/bin/env python3
"""
Integration tests for self-review tool (bd-24f)

Tests the self-review.sh script functionality including:
- Exit codes
- Iteration limits
- Time-boxing warnings
- Integration with git workflow
"""

import subprocess
import os
import tempfile
import pytest
from pathlib import Path


PROJECT_ROOT = Path(__file__).parent.parent
SELF_REVIEW_SCRIPT = PROJECT_ROOT / "scripts" / "self-review.sh"


class TestSelfReviewScript:
    """Test self-review.sh script behavior"""

    def test_script_exists_and_executable(self):
        """Verify script exists and is executable"""
        assert SELF_REVIEW_SCRIPT.exists(), "self-review.sh not found"
        assert os.access(SELF_REVIEW_SCRIPT, os.X_OK), "self-review.sh not executable"

    def test_max_iterations_blocked(self):
        """Verify iteration 4+ is blocked (exit code 2)"""
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT), "--iteration", "4"],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 2, "Should exit with code 2 when max iterations exceeded"
        assert "Maximum review iterations" in result.stdout, "Should show max iterations message"
        assert "3" in result.stdout, "Should mention max of 3 iterations"

    def test_iteration_5_also_blocked(self):
        """Verify iteration 5 is also blocked"""
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT), "--iteration", "5"],
            capture_output=True,
            text=True,
        )

        assert result.returncode == 2, "Should exit with code 2 for iteration 5"
        assert "Maximum review iterations" in result.stdout

    def test_valid_iteration_numbers(self):
        """Verify iterations 1-3 don't immediately fail"""
        for iteration in [1, 2, 3]:
            result = subprocess.run(
                [str(SELF_REVIEW_SCRIPT), "--iteration", str(iteration)],
                capture_output=True,
                text=True,
                input="\n" * 20,  # Skip all prompts with newlines
                timeout=5,
            )

            # Should not exit with code 2 (max iterations)
            assert result.returncode != 2, f"Iteration {iteration} should not be blocked"

            # Should show correct iteration number
            assert f"Iteration {iteration}/3" in result.stdout, \
                f"Should display 'Iteration {iteration}/3'"

    def test_time_limit_display(self):
        """Verify correct time limits are displayed"""
        # Iteration 1: 5 minutes (300s)
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT), "--iteration", "1"],
            capture_output=True,
            text=True,
            input="\n",
            timeout=2,
            check=True,
        )
        assert "5 minutes" in result.stdout, "Iteration 1 should show 5 minute limit"

        # Iteration 2: 3 minutes (180s)
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT), "--iteration", "2"],
            capture_output=True,
            text=True,
            input="\n",
            timeout=2,
            check=True,
        )
        assert "3 minutes" in result.stdout, "Iteration 2 should show 3 minute limit"

        # Iteration 3: 2 minutes (120s)
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT), "--iteration", "3"],
            capture_output=True,
            text=True,
            input="\n",
            timeout=2,
            check=True,
        )
        assert "2 minutes" in result.stdout, "Iteration 3 should show 2 minute limit"

    def test_checklist_sections_present(self):
        """Verify all checklist sections are displayed"""
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT)],
            capture_output=True,
            text=True,
            input="\n",
            timeout=2,
            check=True,
        )

        output = result.stdout

        # Check all sections are present
        assert "Code Quality" in output, "Should include Code Quality section"
        assert "Testing" in output or "test" in output.lower(), "Should include Testing section"
        assert "Documentation" in output, "Should include Documentation section"
        assert "Safety" in output or "Governance" in output, "Should include Safety/Governance section"

    def test_exit_code_validation(self):
        """Verify exit codes are in valid range"""
        # Test with all 'y' responses (should pass with exit code 0)
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT)],
            capture_output=True,
            text=True,
            input="y\n" * 30,  # Answer 'y' to all prompts
            timeout=10,
        )

        assert result.returncode in [0, 1, 2], \
            f"Exit code should be 0, 1, or 2, got {result.returncode}"


class TestSelfReviewIntegration:
    """Test self-review integration with git workflow"""

    def test_scope_check_with_git(self):
        """Verify scope checking works with git status"""
        # This test requires being in a git repository
        result = subprocess.run(
            ["git", "rev-parse", "--git-dir"],
            capture_output=True,
            cwd=PROJECT_ROOT,
        )

        if result.returncode != 0:
            pytest.skip("Not in a git repository")

        # Run self-review (it will check git status internally)
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT)],
            capture_output=True,
            text=True,
            input="\n",
            timeout=3,
            cwd=PROJECT_ROOT,
        )

        # Should complete without crashing
        assert result.returncode in [0, 1, 2], "Should exit with valid code"


class TestSelfReviewDocumentation:
    """Test that documentation exists and is complete"""

    def test_guide_exists(self):
        """Verify self-review-guide.md exists"""
        guide_path = PROJECT_ROOT / "docs" / "self-review-guide.md"
        assert guide_path.exists(), "self-review-guide.md should exist"

    def test_guide_content(self):
        """Verify guide has key sections"""
        guide_path = PROJECT_ROOT / "docs" / "self-review-guide.md"
        content = guide_path.read_text()

        # Check for essential sections
        assert "Quick Start" in content or "quick start" in content.lower()
        assert "Time" in content or "iteration" in content.lower()
        assert "Checklist" in content or "checklist" in content.lower()
        assert "Example" in content or "example" in content.lower()

    def test_governance_reference(self):
        """Verify reference to governance rules exists"""
        guide_path = PROJECT_ROOT / "docs" / "self-review-guide.md"
        content = guide_path.read_text()

        assert "governance" in content.lower(), \
            "Guide should reference governance rules"


class TestSelfReviewTimeBoxing:
    """Test time-boxing behavior"""

    def test_iteration_count_in_output(self):
        """Verify iteration count is clearly displayed"""
        for i in [1, 2, 3]:
            result = subprocess.run(
                [str(SELF_REVIEW_SCRIPT), "--iteration", str(i)],
                capture_output=True,
                text=True,
                input="\n",
                timeout=2,
                check=True,
            )

            # Should show "Iteration N/3"
            assert f"Iteration {i}/3" in result.stdout or f"iteration {i}" in result.stdout.lower()

    def test_max_iterations_message(self):
        """Verify helpful message when max iterations reached"""
        result = subprocess.run(
            [str(SELF_REVIEW_SCRIPT), "--iteration", "4"],
            capture_output=True,
            text=True,
            check=True,
        )

        output = result.stdout

        # Should suggest escalation paths
        assert "peer review" in output.lower() or "human review" in output.lower(), \
            "Should suggest peer or human review"
        assert "mail" in output.lower() or "guidance" in output.lower(), \
            "Should mention how to escalate"


def test_acceptance_criteria():
    """
    Verify acceptance criteria from bd-24f are met:
    - Checklist tool runs successfully ✓
    - Provides actionable feedback ✓
    - Time limits prevent runaway iterations ✓
    - Integrates with existing workflows ✓
    """
    # Criterion 1: Tool runs successfully
    result = subprocess.run(
        [str(SELF_REVIEW_SCRIPT), "--iteration", "1"],
        capture_output=True,
        text=True,
        input="\n",
        timeout=5,
    )
    assert result.returncode in [0, 1, 2], "Tool should run and exit cleanly"

    # Criterion 2: Provides actionable feedback
    assert "Next steps" in result.stdout or "Options" in result.stdout, \
        "Should provide actionable next steps"

    # Criterion 3: Time limits prevent runaway
    result_max = subprocess.run(
        [str(SELF_REVIEW_SCRIPT), "--iteration", "4"],
        capture_output=True,
        text=True,
    )
    assert result_max.returncode == 2, "Should block iteration 4+"
    assert "Maximum" in result_max.stdout, "Should explain max iterations reached"

    # Criterion 4: Integration with workflows
    # Script should reference other tools
    guide_path = PROJECT_ROOT / "docs" / "self-review-guide.md"
    guide = guide_path.read_text()
    assert "reserve" in guide.lower(), "Should integrate with file reservations"
    assert "commit" in guide.lower(), "Should integrate with git workflow"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
