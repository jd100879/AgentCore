"""Pytest configuration for integration tests."""

import asyncio
import sys
from pathlib import Path

import pytest

# Add mcp_agent_mail to path for imports
MCP_AGENT_MAIL_DIR = Path(__file__).parent.parent.parent / "tools" / "mcp_agent_mail"
sys.path.insert(0, str(MCP_AGENT_MAIL_DIR / "src"))

from mcp_agent_mail.config import clear_settings_cache
from mcp_agent_mail.db import reset_database_state
from mcp_agent_mail.storage import clear_repo_cache


@pytest.fixture(scope="function")
def event_loop():
    """Create a new event loop for each test function."""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    yield loop

    # Proper cleanup sequence
    try:
        # Cancel all pending tasks
        pending = asyncio.all_tasks(loop)
        for task in pending:
            task.cancel()

        # Allow cancelled tasks to complete
        if pending:
            loop.run_until_complete(asyncio.gather(*pending, return_exceptions=True))

        # Shutdown async generators
        loop.run_until_complete(loop.shutdown_asyncgens())

        # Shutdown default executor
        if hasattr(loop, "shutdown_default_executor"):
            loop.run_until_complete(loop.shutdown_default_executor())
    except Exception:
        pass  # Ignore cleanup errors
    finally:
        asyncio.set_event_loop(None)
        loop.close()


@pytest.fixture
def isolated_env(tmp_path, monkeypatch):
    """Provide isolated database settings for tests and reset caches."""
    db_path: Path = tmp_path / "test.sqlite3"
    monkeypatch.setenv("DATABASE_URL", f"sqlite+aiosqlite:///{db_path}")
    monkeypatch.setenv("HTTP_HOST", "127.0.0.1")
    monkeypatch.setenv("HTTP_PORT", "8765")
    monkeypatch.setenv("HTTP_PATH", "/mcp/")
    monkeypatch.setenv("APP_ENVIRONMENT", "test")
    monkeypatch.setenv("ARCHIVE_ROOT", str(tmp_path / "archives"))
    monkeypatch.setenv("PROJECT_ROOT_OVERRIDE", str(tmp_path / "projects"))

    # Reset global state before test
    reset_database_state()
    clear_settings_cache()
    clear_repo_cache()

    yield

    # Reset global state after test
    reset_database_state()
    clear_settings_cache()
    clear_repo_cache()
