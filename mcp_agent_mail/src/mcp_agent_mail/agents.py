"""Agent-related functions extracted from app.py."""
# ruff: noqa: I001

from __future__ import annotations

from contextlib import suppress
from typing import Any, Optional, Sequence, cast

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError, NoResultFound, SQLAlchemyError

from .config import Settings
from .db import ensure_schema, get_session
from .errors import ToolExecutionError
from .models import Agent, Project
from .projects import _similarity_score
from .storage import archive_write_lock, ensure_archive, write_agent_profile
from .time_utils import _iso, _naive_utc
from .utils import generate_agent_name, sanitize_agent_name, validate_agent_name_format

# Using archive_write_lock from storage.py to avoid circular dependency

SYSTEM_SENDER_PRIMARY = "SystemNotify"
SYSTEM_SENDER_NAMES: frozenset[str] = frozenset({SYSTEM_SENDER_PRIMARY, "System"})



# Known program names that agents might mistakenly use as agent names
_KNOWN_PROGRAM_NAMES: frozenset[str] = frozenset({
    "claude-code", "claude", "codex-cli", "codex", "cursor", "windsurf",
    "cline", "aider", "copilot", "github-copilot", "gemini-cli", "gemini",
    "opencode", "vscode", "neovim", "vim", "emacs", "zed", "continue",
})

# Known model name patterns that agents might mistakenly use as agent names
_MODEL_NAME_PATTERNS: tuple[str, ...] = (
    "gpt-", "gpt4", "gpt3", "claude-", "opus", "sonnet", "haiku",
    "gemini-", "llama", "mistral", "codestral", "o1-", "o3-",
)


def _agent_to_dict(agent: Agent) -> dict[str, object]:
    return {
        "id": agent.id,
        "name": agent.name,
        "program": agent.program,
        "model": agent.model,
        "task_description": agent.task_description,
        "inception_ts": _iso(agent.inception_ts),
        "last_active_ts": _iso(agent.last_active_ts),
        "project_id": agent.project_id,
        "attachments_policy": getattr(agent, "attachments_policy", "auto"),
    }


async def _find_similar_agents(project: Project, name: str, limit: int = 5, min_score: float = 0.4) -> list[tuple[str, float]]:
    """Find agents with similar names in the project. Returns list of (name, score)."""
    suggestions: list[tuple[str, float]] = []
    async with get_session() as session:
        result = await session.execute(
            select(Agent).where(cast(Any, Agent.project_id == project.id))
        )
        agents = result.scalars().all()
        for a in agents:
            score = _similarity_score(name, a.name)
            if score >= min_score:
                suggestions.append((a.name, score))
    suggestions.sort(key=lambda x: x[1], reverse=True)
    return suggestions[:limit]


async def _list_project_agents(project: Project, limit: int = 10) -> list[str]:
    """List agent names in a project."""
    async with get_session() as session:
        result = await session.execute(
            select(Agent.name).where(cast(Any, Agent.project_id == project.id)).limit(limit)
        )
        return [row[0] for row in result.all()]


def _looks_like_program_name(value: str) -> bool:
    """Check if value looks like a program name (not a valid agent name)."""
    v = value.lower().strip()
    return v in _KNOWN_PROGRAM_NAMES


def _looks_like_model_name(value: str) -> bool:
    """Check if value looks like a model name (not a valid agent name)."""
    v = value.lower().strip()
    return any(p in v for p in _MODEL_NAME_PATTERNS)


def _looks_like_email(value: str) -> bool:
    """Check if value looks like an email address."""
    return "@" in value and "." in value.split("@")[-1]


def _looks_like_broadcast(value: str) -> bool:
    """Check if value looks like a broadcast attempt."""
    v = value.lower().strip()
    return v in {"all", "*", "everyone", "broadcast", "@all", "@everyone"}


def _looks_like_descriptive_name(value: str) -> bool:
    """Check if value looks like a descriptive role name instead of adjective+noun."""
    v = value.lower()
    # Common suffixes for descriptive agent names
    descriptive_patterns = (
        "agent", "bot", "assistant", "helper", "manager", "coordinator",
        "developer", "engineer", "migrator", "refactorer", "fixer",
        "harmonizer", "integrator", "optimizer", "analyzer", "worker",
    )
    return any(v.endswith(p) for p in descriptive_patterns)


def _looks_like_unix_username(value: str) -> bool:
    """
    Check if value looks like a Unix username rather than an adjective+noun agent name.

    This helps detect when hooks or scripts pass $USER instead of the actual agent name.
    Unix usernames typically:
    - Are all lowercase
    - Don't contain capital letters (unlike CamelCase agent names)
    - Are short (3-12 chars typically)
    - Often match common first name patterns
    """
    v = value.strip()
    if not v:
        return False

    # Agent names are PascalCase (e.g., "GreenLake"), usernames are usually all lowercase
    # If there are no uppercase letters and it's a single "word", it's likely a username
    if v.islower() and v.isalnum() and 2 <= len(v) <= 16:
        # Additional check: if it doesn't match any adjective or noun, more likely a username
        from mcp_agent_mail.utils import ADJECTIVES, NOUNS
        if v.lower() not in {a.lower() for a in ADJECTIVES} and v.lower() not in {n.lower() for n in NOUNS}:
            return True

    return False


def _detect_agent_name_mistake(value: str) -> tuple[str, str] | None:
    """
    Detect common mistakes when agents provide invalid agent names.
    Returns (mistake_type, helpful_message) or None if no obvious mistake detected.
    """
    if _looks_like_program_name(value):
        return (
            "PROGRAM_NAME_AS_AGENT",
            f"'{value}' looks like a program name, not an agent name. "
            f"Agent names must be adjective+noun combinations like 'BlueLake' or 'GreenCastle'. "
            f"Use the 'program' parameter for program names, and omit 'name' to auto-generate a valid agent name."
        )
    if _looks_like_model_name(value):
        return (
            "MODEL_NAME_AS_AGENT",
            f"'{value}' looks like a model name, not an agent name. "
            f"Agent names must be adjective+noun combinations like 'RedStone' or 'PurpleBear'. "
            f"Use the 'model' parameter for model names, and omit 'name' to auto-generate a valid agent name."
        )
    if _looks_like_email(value):
        return (
            "EMAIL_AS_AGENT",
            f"'{value}' looks like an email address. Agent names are simple identifiers like 'BlueDog', "
            f"not email addresses. Check the 'to' parameter format."
        )
    if _looks_like_broadcast(value):
        return (
            "BROADCAST_ATTEMPT",
            f"'{value}' looks like a broadcast attempt. Agent Mail doesn't support broadcasting to all agents. "
            f"List specific recipient agent names in the 'to' parameter."
        )
    if _looks_like_descriptive_name(value):
        return (
            "DESCRIPTIVE_NAME",
            f"'{value}' looks like a descriptive role name. Agent names must be randomly generated "
            f"adjective+noun combinations like 'WhiteMountain' or 'BrownCreek', NOT descriptive of the agent's task. "
            f"Omit the 'name' parameter to auto-generate a valid name."
        )
    if _looks_like_unix_username(value):
        return (
            "UNIX_USERNAME_AS_AGENT",
            f"'{value}' looks like a Unix username (possibly from $USER environment variable). "
            f"Agent names must be adjective+noun combinations like 'BlueLake' or 'GreenCastle'. "
            f"When you called register_agent, the system likely auto-generated a valid name for you. "
            f"To find your actual agent name, check the response from register_agent or use "
            f"resource://agents/{{project_key}} to list all registered agents in this project."
        )
    return None


async def _agent_name_exists(project: Project, name: str) -> bool:
    if project.id is None:
        raise ValueError("Project must have an id before querying agents.")
    async with get_session() as session:
        result = await session.execute(
            select(Agent.id).where(Agent.project_id == project.id, func.lower(Agent.name) == name.lower())
        )
        return result.first() is not None


async def _generate_unique_agent_name(
    project: Project,
    settings: Settings,
    name_hint: Optional[str] = None,
) -> str:
    archive = await ensure_archive(settings, project.slug)

    async def available(candidate: str) -> bool:
        return not await _agent_name_exists(project, candidate) and not (archive.root / "agents" / candidate).exists()

    mode = getattr(settings, "agent_name_enforcement_mode", "coerce").lower()
    if name_hint:
        sanitized = sanitize_agent_name(name_hint)
        if mode == "always_auto":
            sanitized = None
        if sanitized:
            # When coercing, if the provided hint is not in the valid adjective+noun set,
            # silently fall back to auto-generation instead of erroring.
            if validate_agent_name_format(sanitized):
                if not await available(sanitized):
                    # In strict mode, indicate conflict; in coerce, fall back to generation
                    if mode == "strict":
                        raise ValueError(f"Agent name '{sanitized}' is already in use.")
                else:
                    return sanitized
            else:
                if mode == "strict":
                    raise ValueError(
                        f"Invalid agent name format: '{sanitized}'. "
                        f"Agent names MUST be randomly generated adjective+noun combinations "
                        f"(e.g., 'GreenLake', 'BlueDog'), NOT descriptive names. "
                        f"Omit the 'name_hint' parameter to auto-generate a valid name."
                    )
        else:
            # No alphanumerics remain; only strict mode should error
            if mode == "strict":
                raise ValueError("Name hint must contain alphanumeric characters.")

    for _ in range(1024):
        candidate = sanitize_agent_name(generate_agent_name())
        if candidate and await available(candidate):
            return candidate
    raise RuntimeError("Unable to generate a unique agent name.")


async def _create_agent_record(
    project: Project,
    name: str,
    program: str,
    model: str,
    task_description: str,
) -> Agent:
    if project.id is None:
        raise ValueError("Project must have an id before creating agents.")
    await ensure_schema()
    async with get_session() as session:
        agent = Agent(
            project_id=project.id,
            name=name,
            program=program,
            model=model,
            task_description=task_description,
        )
        session.add(agent)
        await session.commit()
        await session.refresh(agent)
        return agent


async def _get_or_create_system_agent(project: Project) -> Agent:
    """
    Get or create the reserved System sender for a project.
    Keeps messages audit-friendly by using a real DB-backed agent instead of a synthetic record.
    """
    try:
        return await _get_agent(project, SYSTEM_SENDER_PRIMARY)
    except ToolExecutionError:
        return await _create_agent_record(
            project=project,
            name=SYSTEM_SENDER_PRIMARY,
            program="system",
            model="system",
            task_description="Automated system notifications",
        )


async def _get_or_create_agent(
    project: Project,
    name: Optional[str],
    program: str,
    model: str,
    task_description: str,
    settings: Settings,
) -> Agent:
    if project.id is None:
        raise ValueError("Project must have an id before creating agents.")
    mode = getattr(settings, "agent_name_enforcement_mode", "coerce").lower()
    explicit_name_used = False
    if mode == "always_auto" or name is None:
        desired_name = await _generate_unique_agent_name(project, settings, None)
    else:
        sanitized = sanitize_agent_name(name)
        if not sanitized:
            if mode == "strict":
                raise ValueError("Agent name must contain alphanumeric characters.")
            desired_name = await _generate_unique_agent_name(project, settings, None)
        else:
            if validate_agent_name_format(sanitized):
                desired_name = sanitized
                explicit_name_used = True
            else:
                if mode == "strict":
                    # Check for common mistakes and provide specific guidance
                    mistake = _detect_agent_name_mistake(sanitized)
                    if mistake:
                        raise ToolExecutionError(
                            mistake[0],
                            mistake[1],
                            recoverable=True,
                            data={"provided_name": sanitized, "valid_examples": ["BlueLake", "GreenCastle", "RedStone"]},
                        )
                    raise ToolExecutionError(
                        "INVALID_AGENT_NAME",
                        f"Invalid agent name format: '{sanitized}'. "
                        f"Agent names MUST be randomly generated adjective+noun combinations "
                        f"(e.g., 'GreenLake', 'BlueDog'), NOT descriptive names. "
                        f"Omit the 'name' parameter to auto-generate a valid name.",
                        recoverable=True,
                        data={"provided_name": sanitized, "valid_examples": ["BlueLake", "GreenCastle", "RedStone"]},
                    )
                # coerce -> ignore invalid provided name and auto-generate
                desired_name = await _generate_unique_agent_name(project, settings, None)
    await ensure_schema()
    async with get_session() as session:
        for _attempt in range(5):
            # Use case-insensitive matching to be consistent with _agent_name_exists() and _get_agent()
            result = await session.execute(
                select(Agent).where(
                    cast(Any, Agent.project_id == project.id),
                    cast(Any, func.lower(Agent.name) == desired_name.lower()),
                )
            )
            agent = result.scalars().first()
            if agent:
                agent.program = program
                agent.model = model
                agent.task_description = task_description
                agent.last_active_ts = _naive_utc()
                session.add(agent)
                await session.commit()
                await session.refresh(agent)
                break

            candidate = Agent(
                project_id=project.id,
                name=desired_name,
                program=program,
                model=model,
                task_description=task_description,
            )
            session.add(candidate)
            try:
                await session.commit()
                await session.refresh(candidate)
                agent = candidate
                break
            except IntegrityError:
                await session.rollback()
                with suppress(SQLAlchemyError):
                    session.expunge(candidate)

                if explicit_name_used:
                    # Another concurrent call created this identity; treat as idempotent update.
                    result = await session.execute(
                        select(Agent).where(
                            cast(Any, Agent.project_id == project.id),
                            cast(Any, func.lower(Agent.name) == desired_name.lower()),
                        )
                    )
                    agent = result.scalars().first()
                    if agent is None:
                        raise
                    agent.program = program
                    agent.model = model
                    agent.task_description = task_description
                    agent.last_active_ts = _naive_utc()
                    session.add(agent)
                    await session.commit()
                    await session.refresh(agent)
                    break

                # Auto-generated name collision under concurrency: pick a new name and retry.
                desired_name = await _generate_unique_agent_name(project, settings, None)
                continue
        else:
            raise RuntimeError("Failed to create a unique agent after multiple retries.")
    archive = await ensure_archive(settings, project.slug)
    async with archive_write_lock(archive):
        await write_agent_profile(archive, _agent_to_dict(agent))
    return agent


async def _get_agent(project: Project, name: str) -> Agent:
    """Get agent by name with helpful error messages and suggestions."""
    await ensure_schema()

    # Validate input
    if not name or not name.strip():
        raise ToolExecutionError(
            "INVALID_ARGUMENT",
            f"Agent name cannot be empty. Provide a valid agent name for project '{project.human_key}'.",
            recoverable=True,
            data={"parameter": "agent_name", "provided": repr(name), "project": project.slug},
        )

    # Detect placeholder values (indicates unconfigured hooks/settings)
    _agent_placeholder_patterns = [
        "YOUR_AGENT",
        "YOUR_AGENT_NAME",
        "AGENT_NAME",
        "PLACEHOLDER",
        "<AGENT>",
        "{AGENT}",
        "$AGENT",
    ]
    name_upper = name.upper().strip()
    for pattern in _agent_placeholder_patterns:
        if pattern in name_upper or name_upper == pattern:
            raise ToolExecutionError(
                "CONFIGURATION_ERROR",
                f"Detected placeholder value '{name}' instead of a real agent name. "
                f"This typically means a hook or integration script hasn't been configured yet. "
                f"Replace placeholder values with your actual agent name (e.g., 'BlueMountain').",
                recoverable=True,
                data={
                    "parameter": "agent_name",
                    "provided": name,
                    "detected_placeholder": pattern,
                    "fix_hint": "Update AGENT_MAIL_AGENT or agent_name in your configuration",
                },
            )

    async with get_session() as session:
        result = await session.execute(
            select(Agent).where(Agent.project_id == project.id, func.lower(Agent.name) == name.lower())
        )
        agent = result.scalars().first()
        if agent:
            return agent

    # Agent not found - provide helpful suggestions
    suggestions = await _find_similar_agents(project, name)
    available_agents = await _list_project_agents(project)

    # Check for common mistakes (Unix username, program name, etc.)
    mistake = _detect_agent_name_mistake(name)
    mistake_hint = ""
    if mistake:
        mistake_hint = f"\n\nHINT: {mistake[1]}"

    if suggestions:
        # Found similar names - probably a typo
        suggestion_text = ", ".join([f"'{s[0]}'" for s in suggestions[:3]])
        raise ToolExecutionError(
            mistake[0] if mistake else "NOT_FOUND",
            f"Agent '{name}' not found in project '{project.human_key}'. Did you mean: {suggestion_text}? "
            f"Agent names are case-insensitive but must match exactly.{mistake_hint}",
            recoverable=True,
            data={
                "agent_name": name,
                "project": project.slug,
                "suggestions": [{"name": s[0], "score": round(s[1], 2)} for s in suggestions],
                "available_agents": available_agents,
                "mistake_type": mistake[0] if mistake else None,
            },
        )
    elif available_agents:
        # No similar names but project has agents
        agents_list = ", ".join([f"'{a}'" for a in available_agents[:5]])
        more_text = f" and {len(available_agents) - 5} more" if len(available_agents) > 5 else ""
        raise ToolExecutionError(
            mistake[0] if mistake else "NOT_FOUND",
            f"Agent '{name}' not found in project '{project.human_key}'. "
            f"Available agents: {agents_list}{more_text}. "
            f"Use register_agent to create a new agent identity.{mistake_hint}",
            recoverable=True,
            data={
                "agent_name": name,
                "project": project.slug,
                "available_agents": available_agents,
                "mistake_type": mistake[0] if mistake else None,
            },
        )
    else:
        # Project has no agents
        raise ToolExecutionError(
            mistake[0] if mistake else "NOT_FOUND",
            f"Agent '{name}' not found. Project '{project.human_key}' has no registered agents yet. "
            f"Use register_agent to create an agent identity first (omit 'name' to auto-generate a valid one). "
            f"Example: register_agent(project_key='{project.slug}', program='claude-code', model='opus-4'){mistake_hint}",
            recoverable=True,
            data={"agent_name": name, "project": project.slug, "available_agents": [], "mistake_type": mistake[0] if mistake else None},
        )


async def _get_agents_batch(project: Project, names: Sequence[str]) -> dict[str, Agent]:
    """Batch lookup agents by name with `_get_agent`-equivalent error reporting."""
    await ensure_schema()
    if not names:
        return {}
    if project.id is None:
        raise ValueError("Project must have an id before querying agents.")

    lowered_names: list[str] = []
    seen: set[str] = set()
    for name in names:
        lowered = name.lower()
        if lowered in seen:
            continue
        seen.add(lowered)
        lowered_names.append(lowered)

    async with get_session() as session:
        result = await session.execute(
            select(Agent).where(Agent.project_id == project.id, func.lower(Agent.name).in_(lowered_names))
        )
        agents = result.scalars().all()

    by_lower = {agent.name.lower(): agent for agent in agents}
    resolved: dict[str, Agent] = {}
    missing: list[str] = []
    for name in names:
        agent = by_lower.get(name.lower())
        if agent is None:
            missing.append(name)
        else:
            resolved[name] = agent

    if missing:
        # Reuse the exact error logic from _get_agent for the first missing entry.
        await _get_agent(project, missing[0])

    return resolved


async def _get_agents_batch_lenient(project: Project, names: Sequence[str]) -> dict[str, Agent]:
    """Batch lookup agents by name, silently skipping missing agents.

    Unlike _get_agents_batch, this does NOT raise errors for missing agents.
    Use this for contact policy enforcement where missing recipients should
    be skipped rather than treated as errors.

    Parameters
    ----------
    project : Project
        The project to look up agents in.
    names : Sequence[str]
        Agent names to look up.

    Returns
    -------
    dict[str, Agent]
        Mapping from original name to Agent. Missing agents are omitted.
    """
    await ensure_schema()
    if not names:
        return {}
    if project.id is None:
        return {}

    # Deduplicate and lowercase for efficient IN query
    lowered_names: list[str] = []
    seen: set[str] = set()
    for name in names:
        lowered = name.lower()
        if lowered in seen:
            continue
        seen.add(lowered)
        lowered_names.append(lowered)

    async with get_session() as session:
        result = await session.execute(
            select(Agent).where(Agent.project_id == project.id, func.lower(Agent.name).in_(lowered_names))
        )
        agents = result.scalars().all()

    # Build lookup by lowercase name
    by_lower = {agent.name.lower(): agent for agent in agents}

    # Resolve original names to agents (preserving original case in keys)
    resolved: dict[str, Agent] = {}
    for name in names:
        agent = by_lower.get(name.lower())
        if agent is not None:
            resolved[name] = agent

    return resolved


async def _get_agent_by_id(project: Project, agent_id: int) -> Agent:
    if project.id is None:
        raise ValueError("Project must have an id before querying agents.")
    await ensure_schema()
    async with get_session() as session:
        result = await session.execute(
            select(Agent).where(Agent.project_id == project.id, Agent.id == agent_id)
        )
        agent = result.scalars().first()
        if not agent:
            raise NoResultFound(f"Agent id '{agent_id}' not found for project '{project.human_key}'.")
        return agent


