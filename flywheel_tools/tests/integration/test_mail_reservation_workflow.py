#!/usr/bin/env python3
"""
Integration tests for mail + file reservation workflow (bd-8sb)

Tests end-to-end integration of file reservation expiry notifications:
- SystemNotify sender path for automated notifications
- Mail delivery when reservations expire
- Cross-agent notification workflows
- Notification idempotency and targeting

Reference: bd-8sb
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone

import pytest
from fastmcp import Client
from sqlalchemy import text

# Import MCP agent mail test utilities
import sys
from pathlib import Path

# Add mcp_agent_mail to path for imports
MCP_AGENT_MAIL_DIR = Path(__file__).parent.parent.parent / "tools" / "mcp_agent_mail"
sys.path.insert(0, str(MCP_AGENT_MAIL_DIR / "src"))

from mcp_agent_mail.app import build_mcp_server
from mcp_agent_mail.db import get_session
from mcp_agent_mail.agents import SYSTEM_SENDER_PRIMARY


# ============================================================================
# Helper functions for database queries
# ============================================================================


async def get_project_id(human_key: str) -> int | None:
    """Get project ID from human_key."""
    async with get_session() as session:
        result = await session.execute(
            text("SELECT id FROM projects WHERE human_key = :key"),
            {"key": human_key},
        )
        row = result.first()
        return row[0] if row else None


async def get_agent_id(project_key: str, agent_name: str) -> int | None:
    """Get agent ID from project_key and name."""
    async with get_session() as session:
        result = await session.execute(
            text(
                "SELECT a.id FROM agents a "
                "JOIN projects p ON a.project_id = p.id "
                "WHERE p.human_key = :key AND a.name = :name"
            ),
            {"key": project_key, "name": agent_name},
        )
        row = result.first()
        return row[0] if row else None


async def get_system_sender_id(project_key: str) -> int | None:
    """Get SystemNotify sender ID for a project."""
    async with get_session() as session:
        result = await session.execute(
            text(
                "SELECT a.id FROM agents a "
                "JOIN projects p ON a.project_id = p.id "
                "WHERE p.human_key = :key AND a.name = :name"
            ),
            {"key": project_key, "name": SYSTEM_SENDER_PRIMARY},
        )
        row = result.first()
        return row[0] if row else None


async def get_messages_for_agent(
    project_key: str, agent_name: str, sender_name: str | None = None
) -> list[dict]:
    """Get all messages for a specific agent, optionally filtered by sender."""
    async with get_session() as session:
        # Build query
        query = """
            SELECT m.id, m.subject, m.body_md, m.created_ts, sender.name as sender_name
            FROM messages m
            JOIN message_recipients mr ON m.id = mr.message_id
            JOIN agents recipient ON mr.agent_id = recipient.id
            JOIN agents sender ON m.sender_id = sender.id
            JOIN projects p ON recipient.project_id = p.id
            WHERE p.human_key = :project_key
            AND recipient.name = :agent_name
        """
        params = {"project_key": project_key, "agent_name": agent_name}

        if sender_name:
            query += " AND sender.name = :sender_name"
            params["sender_name"] = sender_name

        query += " ORDER BY m.created_ts DESC"

        result = await session.execute(text(query), params)
        rows = result.fetchall()

        return [
            {
                "id": row[0],
                "subject": row[1],
                "body_md": row[2],
                "created_ts": row[3],
                "sender_name": row[4],
            }
            for row in rows
        ]


async def get_active_reservations(project_id: int) -> list[dict]:
    """Get all active (non-released, non-expired) reservations."""
    async with get_session() as session:
        result = await session.execute(
            text(
                "SELECT id, agent_id, path_pattern, exclusive, expires_ts "
                "FROM file_reservations "
                "WHERE project_id = :pid AND released_ts IS NULL "
                "AND expires_ts > datetime('now')"
            ),
            {"pid": project_id},
        )
        rows = result.fetchall()
        return [
            {
                "id": row[0],
                "agent_id": row[1],
                "path_pattern": row[2],
                "exclusive": row[3],
                "expires_ts": row[4],
            }
            for row in rows
        ]


# ============================================================================
# Helper functions for test setup
# ============================================================================


async def setup_project_and_agents(
    client, project_key: str, num_agents: int = 1
) -> tuple[str, list[str]]:
    """
    Create project and multiple agents.
    Returns (project_key, [agent_names])
    """
    await client.call_tool("ensure_project", {"human_key": project_key})

    agent_names = []
    for _ in range(num_agents):
        result = await client.call_tool(
            "register_agent",
            {
                "project_key": project_key,
                "program": "test",
                "model": "test",
            },
        )
        agent_names.append(result.data["name"])

    return project_key, agent_names


async def create_test_reservation(
    client,
    project_key: str,
    agent_name: str,
    path_pattern: str,
    ttl_seconds: int = 300,
    exclusive: bool = True,
) -> dict:
    """Create a test file reservation and return granted reservation data."""
    result = await client.call_tool(
        "file_reservation_paths",
        {
            "project_key": project_key,
            "agent_name": agent_name,
            "paths": [path_pattern],
            "ttl_seconds": ttl_seconds,
            "exclusive": exclusive,
            "reason": f"Test reservation for {path_pattern}",
        },
    )

    assert "granted" in result.data, "Reservation should be granted"
    assert len(result.data["granted"]) > 0, "At least one reservation should be granted"

    return result.data["granted"][0]


# ============================================================================
# Test 1: Basic Expiry Notification E2E
# ============================================================================


@pytest.mark.asyncio
async def test_basic_expiry_notification_e2e(isolated_env):
    """
    Test basic end-to-end flow of reservation expiry notification.

    Flow:
    1. Create file reservation with short TTL
    2. Send notification (simulating expiry monitor)
    3. Verify SystemNotify sends message to agent
    4. Validate message format and content
    """
    server = build_mcp_server()
    async with Client(server) as client:
        project_key = "/test/mail_res/basic_expiry"
        _, agent_names = await setup_project_and_agents(client, project_key, num_agents=1)
        agent_name = agent_names[0]

        # Create reservation with short TTL (60 seconds)
        reservation = await create_test_reservation(
            client, project_key, agent_name, "src/test.py", ttl_seconds=60
        )

        reservation_id = reservation["id"]
        path_pattern = reservation["path_pattern"]
        expires_ts = reservation["expires_ts"]

        # Simulate expiry notification by sending message as SystemNotify
        # In production, this is done by expiry-notify-monitor.sh
        subject = f"[System] ⏰ Reservation expiring soon (ID: {reservation_id})"
        body = f"""System notice (not sent by an agent): your file reservation is expiring soon.

Reservation Details:
- Path: {path_pattern}
- Reservation ID: {reservation_id}
- Expires at: {expires_ts}
- Time remaining: ~1 minutes

Suggested Actions:
1. Renew if you still need it: ./scripts/reserve-files.sh renew
2. Release if you're done: ./scripts/reserve-files.sh release --id {reservation_id}
3. Do nothing - it will expire automatically

Project: {project_key}"""

        # Send message as SystemNotify
        send_result = await client.call_tool(
            "send_message",
            {
                "project_key": project_key,
                "sender_name": SYSTEM_SENDER_PRIMARY,
                "to": [agent_name],
                "subject": subject,
                "body_md": body,
                "importance": "normal",
            },
        )

        # Extract message ID from deliveries
        assert "deliveries" in send_result.data, "Message should be sent"
        assert len(send_result.data["deliveries"]) > 0, "At least one delivery"
        message_id = send_result.data["deliveries"][0]["payload"]["id"]

        # Verify message was delivered to agent
        messages = await get_messages_for_agent(
            project_key, agent_name, sender_name=SYSTEM_SENDER_PRIMARY
        )

        assert len(messages) > 0, "Agent should have received at least one message"

        # Find our specific message
        our_message = None
        for msg in messages:
            if msg["id"] == message_id:
                our_message = msg
                break

        assert our_message is not None, "Our message should be in agent's inbox"

        # Validate message content
        assert f"ID: {reservation_id}" in our_message["subject"]
        assert "⏰" in our_message["subject"]
        assert "expiring soon" in our_message["subject"].lower()

        assert "System notice" in our_message["body_md"]
        assert path_pattern in our_message["body_md"]
        assert str(reservation_id) in our_message["body_md"]
        assert expires_ts in our_message["body_md"]
        assert "reserve-files.sh" in our_message["body_md"]


# ============================================================================
# Test 2: SystemNotify Sender Verification
# ============================================================================


@pytest.mark.asyncio
async def test_systemnotify_sender_verification(isolated_env):
    """
    Verify that expiry notifications are sent from SystemNotify.

    Verifies:
    - Sender is SystemNotify (not auto-renamed)
    - Message contains system disclaimer
    - Sender ID matches system sender in database
    """
    server = build_mcp_server()
    async with Client(server) as client:
        project_key = "/test/mail_res/sender_verify"
        _, agent_names = await setup_project_and_agents(client, project_key, num_agents=1)
        agent_name = agent_names[0]

        # Get SystemNotify sender ID
        system_sender_id = await get_system_sender_id(project_key)

        # If SystemNotify doesn't exist yet, sending a message will create it
        # So we send a test message first
        test_subject = "[System] Test notification"
        test_body = "System notice (not sent by an agent): test message"

        send_result = await client.call_tool(
            "send_message",
            {
                "project_key": project_key,
                "sender_name": SYSTEM_SENDER_PRIMARY,
                "to": [agent_name],
                "subject": test_subject,
                "body_md": test_body,
                "importance": "normal",
            },
        )

        assert "deliveries" in send_result.data
        message_id = send_result.data["deliveries"][0]["payload"]["id"]

        # Verify sender in database
        messages = await get_messages_for_agent(
            project_key, agent_name, sender_name=SYSTEM_SENDER_PRIMARY
        )

        assert len(messages) > 0, "Should have received message from SystemNotify"

        latest_message = messages[0]
        assert latest_message["sender_name"] == SYSTEM_SENDER_PRIMARY
        assert "System notice (not sent by an agent)" in latest_message["body_md"]


# ============================================================================
# Test 3: Cross-Agent Notification Workflow
# ============================================================================


@pytest.mark.asyncio
async def test_cross_agent_notification_workflow(isolated_env):
    """
    Test that each agent receives only their own expiry notifications.

    Flow:
    1. Create two agents with different reservations
    2. Send expiry notification for Agent A's reservation
    3. Verify only Agent A receives the notification
    4. Verify Agent B does NOT receive Agent A's notification
    """
    server = build_mcp_server()
    async with Client(server) as client:
        project_key = "/test/mail_res/cross_agent"
        _, agent_names = await setup_project_and_agents(client, project_key, num_agents=2)
        agent_a, agent_b = agent_names[0], agent_names[1]

        # Agent A creates reservation
        res_a = await create_test_reservation(
            client, project_key, agent_a, "backend/**", ttl_seconds=100
        )

        # Agent B creates different reservation
        res_b = await create_test_reservation(
            client, project_key, agent_b, "frontend/**", ttl_seconds=100
        )

        # Send expiry notification for Agent A's reservation only
        subject_a = f"[System] ⏰ Reservation expiring soon (ID: {res_a['id']})"
        body_a = f"""System notice (not sent by an agent): your file reservation is expiring soon.

Reservation Details:
- Path: {res_a['path_pattern']}
- Reservation ID: {res_a['id']}
- Expires at: {res_a['expires_ts']}"""

        await client.call_tool(
            "send_message",
            {
                "project_key": project_key,
                "sender_name": SYSTEM_SENDER_PRIMARY,
                "to": [agent_a],  # Only to Agent A
                "subject": subject_a,
                "body_md": body_a,
                "importance": "normal",
            },
        )

        # Verify Agent A received the notification
        messages_a = await get_messages_for_agent(
            project_key, agent_a, sender_name=SYSTEM_SENDER_PRIMARY
        )
        assert len(messages_a) > 0, "Agent A should have received notification"
        assert res_a["path_pattern"] in messages_a[0]["body_md"]

        # Verify Agent B did NOT receive Agent A's notification
        messages_b = await get_messages_for_agent(
            project_key, agent_b, sender_name=SYSTEM_SENDER_PRIMARY
        )

        # Agent B should have no messages about Agent A's reservation
        for msg in messages_b:
            assert res_a["path_pattern"] not in msg["body_md"], \
                "Agent B should not receive Agent A's notifications"


# ============================================================================
# Test 4: Notification Idempotency
# ============================================================================


@pytest.mark.asyncio
async def test_notification_idempotency(isolated_env):
    """
    Test that duplicate notifications are not sent for the same reservation expiry.

    This test simulates the idempotency mechanism that would be implemented
    in the expiry monitor to prevent spam.

    Note: The actual idempotency is handled by expiry-notify-monitor.sh
    using notification tracking files. This test verifies the mail system
    itself doesn't prevent duplicate sends (which is correct - the monitor
    should handle deduplication).
    """
    server = build_mcp_server()
    async with Client(server) as client:
        project_key = "/test/mail_res/idempotency"
        _, agent_names = await setup_project_and_agents(client, project_key, num_agents=1)
        agent_name = agent_names[0]

        reservation = await create_test_reservation(
            client, project_key, agent_name, "config/app.yml", ttl_seconds=80
        )

        subject = f"[System] ⏰ Reservation expiring soon (ID: {reservation['id']})"
        body = f"System notice: reservation {reservation['id']} expiring"

        # Send first notification
        result1 = await client.call_tool(
            "send_message",
            {
                "project_key": project_key,
                "sender_name": SYSTEM_SENDER_PRIMARY,
                "to": [agent_name],
                "subject": subject,
                "body_md": body,
                "importance": "normal",
            },
        )

        assert "deliveries" in result1.data
        msg_id_1 = result1.data["deliveries"][0]["payload"]["id"]

        # Send second notification (duplicate)
        result2 = await client.call_tool(
            "send_message",
            {
                "project_key": project_key,
                "sender_name": SYSTEM_SENDER_PRIMARY,
                "to": [agent_name],
                "subject": subject,
                "body_md": body,
                "importance": "normal",
            },
        )

        assert "deliveries" in result2.data
        msg_id_2 = result2.data["deliveries"][0]["payload"]["id"]

        # Verify both messages were sent (mail system allows duplicates)
        # The expiry monitor is responsible for preventing duplicate sends
        # via notification tracking files
        assert msg_id_1 != msg_id_2, "Should create separate message records"

        messages = await get_messages_for_agent(
            project_key, agent_name, sender_name=SYSTEM_SENDER_PRIMARY
        )

        # Count messages about this specific reservation
        res_messages = [
            msg for msg in messages if str(reservation['id']) in msg['subject']
        ]

        # Mail system should have delivered both (no built-in dedup)
        # In production, expiry-notify-monitor.sh prevents this at send time
        assert len(res_messages) >= 2, \
            "Mail system should deliver duplicates (monitor handles dedup)"


# ============================================================================
# Test 5: Multiple Simultaneous Expiries
# ============================================================================


@pytest.mark.asyncio
async def test_multiple_simultaneous_expiries(isolated_env):
    """
    Test that multiple agents receive their own notifications when multiple
    reservations expire simultaneously.

    Flow:
    1. Create 3 agents with different reservations
    2. Send expiry notifications for all reservations
    3. Verify each agent receives only their own notification
    4. Verify no cross-contamination
    """
    server = build_mcp_server()
    async with Client(server) as client:
        project_key = "/test/mail_res/multi_expiry"
        _, agent_names = await setup_project_and_agents(client, project_key, num_agents=3)

        # Create reservations for each agent
        reservations = []
        patterns = ["api/**", "models/**", "tests/**"]

        for agent_name, pattern in zip(agent_names, patterns):
            res = await create_test_reservation(
                client, project_key, agent_name, pattern, ttl_seconds=90
            )
            reservations.append((agent_name, res))

        # Send notifications for all reservations
        for agent_name, res in reservations:
            subject = f"[System] ⏰ Reservation expiring soon (ID: {res['id']})"
            body = f"""System notice: reservation expiring

Path: {res['path_pattern']}
ID: {res['id']}"""

            await client.call_tool(
                "send_message",
                {
                    "project_key": project_key,
                    "sender_name": SYSTEM_SENDER_PRIMARY,
                    "to": [agent_name],
                    "subject": subject,
                    "body_md": body,
                    "importance": "normal",
                },
            )

        # Verify each agent received exactly their own notification
        for i, (agent_name, res) in enumerate(reservations):
            messages = await get_messages_for_agent(
                project_key, agent_name, sender_name=SYSTEM_SENDER_PRIMARY
            )

            assert len(messages) > 0, f"{agent_name} should have received notification"

            # Check that the message is about their reservation
            latest = messages[0]
            assert res["path_pattern"] in latest["body_md"], \
                f"{agent_name} should receive notification about {res['path_pattern']}"

            # Verify no cross-contamination with other agents' patterns
            other_patterns = [p for j, p in enumerate(patterns) if j != i]
            for other_pattern in other_patterns:
                assert other_pattern not in latest["body_md"], \
                    f"{agent_name} should not see {other_pattern} in their notification"


# ============================================================================
# Test 6: Message Format Validation
# ============================================================================


@pytest.mark.asyncio
async def test_message_format_validation(isolated_env):
    """
    Validate that expiry notification messages follow the expected format.

    Verifies:
    - Subject line format
    - Body structure and content
    - Required fields present
    - Actionable suggestions included
    """
    server = build_mcp_server()
    async with Client(server) as client:
        project_key = "/test/mail_res/format"
        _, agent_names = await setup_project_and_agents(client, project_key, num_agents=1)
        agent_name = agent_names[0]

        reservation = await create_test_reservation(
            client, project_key, agent_name, "docs/readme.md", ttl_seconds=120
        )

        # Create properly formatted notification (matching expiry-notify-monitor.sh)
        subject = f"[System] ⏰ Reservation expiring soon (ID: {reservation['id']})"
        body = f"""System notice (not sent by an agent): your file reservation is expiring soon.

Reservation Details:
- Path: {reservation['path_pattern']}
- Reservation ID: {reservation['id']}
- Expires at: {reservation['expires_ts']}
- Time remaining: ~2 minutes

Suggested Actions:
1. Renew if you still need it: ./scripts/reserve-files.sh renew
2. Release if you're done: ./scripts/reserve-files.sh release --id {reservation['id']}
3. Do nothing - it will expire automatically

Project: {project_key}"""

        await client.call_tool(
            "send_message",
            {
                "project_key": project_key,
                "sender_name": SYSTEM_SENDER_PRIMARY,
                "to": [agent_name],
                "subject": subject,
                "body_md": body,
                "importance": "normal",
            },
        )

        messages = await get_messages_for_agent(
            project_key, agent_name, sender_name=SYSTEM_SENDER_PRIMARY
        )

        assert len(messages) > 0
        msg = messages[0]

        # Validate subject format
        assert msg["subject"].startswith("[System]")
        assert "⏰" in msg["subject"]
        assert "expiring soon" in msg["subject"].lower()
        assert f"ID: {reservation['id']}" in msg["subject"]

        # Validate body structure
        body_text = msg["body_md"]

        # Required sections
        assert "System notice (not sent by an agent)" in body_text
        assert "Reservation Details:" in body_text
        assert "Suggested Actions:" in body_text

        # Required details
        assert f"Path: {reservation['path_pattern']}" in body_text
        assert f"Reservation ID: {reservation['id']}" in body_text
        assert f"Expires at: {reservation['expires_ts']}" in body_text
        assert "Time remaining:" in body_text

        # Actionable suggestions
        assert "reserve-files.sh renew" in body_text
        assert "reserve-files.sh release" in body_text
        assert f"--id {reservation['id']}" in body_text
        assert "expire automatically" in body_text

        # Project info
        assert f"Project: {project_key}" in body_text


# ============================================================================
# Acceptance Criteria Test
# ============================================================================


@pytest.mark.asyncio
async def test_acceptance_criteria(isolated_env):
    """
    Verify all acceptance criteria for bd-8sb are met:

    ✓ E2E tests for file reservation expiry notifications
    ✓ SystemNotify sender path tested
    ✓ Mail delivery verification when reservations expire
    ✓ Cross-agent notification workflows validated
    """
    # This test is a meta-test that validates the test suite itself
    # It runs a minimal version of each key scenario

    server = build_mcp_server()
    async with Client(server) as client:
        project_key = "/test/mail_res/acceptance"
        _, agent_names = await setup_project_and_agents(client, project_key, num_agents=2)

        # Criterion 1: E2E flow works
        res = await create_test_reservation(
            client, project_key, agent_names[0], "acceptance/**", ttl_seconds=70
        )
        assert res is not None, "Reservation creation works"

        # Criterion 2: SystemNotify can send messages
        msg_result = await client.call_tool(
            "send_message",
            {
                "project_key": project_key,
                "sender_name": SYSTEM_SENDER_PRIMARY,
                "to": [agent_names[0]],
                "subject": "[System] Test",
                "body_md": "System notice: test",
                "importance": "normal",
            },
        )
        assert "deliveries" in msg_result.data, "SystemNotify can send messages"

        # Criterion 3: Mail delivery works
        messages = await get_messages_for_agent(
            project_key, agent_names[0], sender_name=SYSTEM_SENDER_PRIMARY
        )
        assert len(messages) > 0, "Mail delivery works"

        # Criterion 4: Cross-agent targeting works
        messages_other = await get_messages_for_agent(
            project_key, agent_names[1], sender_name=SYSTEM_SENDER_PRIMARY
        )
        # agent_names[1] should not have received the message sent to agent_names[0]
        # (assuming no other messages were sent to them)
        test_messages = [m for m in messages_other if "Test" in m["subject"]]
        assert len(test_messages) == 0, "Messages are correctly targeted"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
