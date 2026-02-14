"""Project-related functions extracted from app.py."""
# ruff: noqa: I001

from __future__ import annotations

import hashlib
import json
import logging
from datetime import timedelta
from difflib import SequenceMatcher
from pathlib import Path
from typing import Optional, cast

from git.exc import InvalidGitRepositoryError, NoSuchPathError
from sqlalchemy import desc, func, or_, select, text
from sqlalchemy.orm import aliased

from .config import Settings, get_settings
from .db import ensure_schema, get_session
from .errors import ToolExecutionError
from .models import Agent, Message, Project, ProjectSiblingSuggestion
from .storage import ensure_archive, _git_repo
from .time_utils import _iso, _naive_utc
from .utils import slugify
from .paths import _latest_filesystem_activity, _latest_git_activity

logger = logging.getLogger(__name__)

# Constants
_PROJECT_PROFILE_FILENAMES: tuple[str, ...] = (
    "README.md",
    "Readme.md",
    "readme.md",
    "AGENTS.md",
    "CLAUDE.md",
    "Claude.md",
    "agents/README.md",
    "docs/README.md",
    "docs/overview.md",
)
_PROJECT_PROFILE_MAX_TOTAL_CHARS = 6000
_PROJECT_PROFILE_PER_FILE_CHARS = 1800
_PROJECT_SIBLING_REFRESH_TTL = timedelta(hours=12)
_PROJECT_SIBLING_REFRESH_LIMIT = 3
_PROJECT_SIBLING_MIN_SUGGESTION_SCORE = 0.92


def _project_to_dict(project: Project) -> dict[str, object]:
    return {
        "id": project.id,
        "slug": project.slug,
        "human_key": project.human_key,
        "created_at": _iso(project.created_at),
    }


def _compute_project_slug(human_key: str) -> str:
    """
    Compute the project slug with strict backward compatibility by default.
    When worktree-friendly behavior is enabled, we still default to 'dir' mode
    until additional identity modes are implemented.
    """
    settings = get_settings()
    # Gate: preserve existing behavior unless explicitly enabled
    if not settings.worktrees_enabled:
        return slugify(human_key)
    # Helpers for identity modes (privacy-safe)
    def _short_sha1(text: str, n: int = 10) -> str:
        return hashlib.sha256(text.encode("utf-8")).hexdigest()[:n]

    def _norm_remote(url: str | None) -> str | None:
        if not url:
            return None
        url = url.strip()
        try:
            if url.startswith("git@"):
                host = url.split("@", 1)[1].split(":", 1)[0]
                path = url.split(":", 1)[1]
            else:
                from urllib.parse import urlparse as _urlparse

                p = _urlparse(url)
                host = p.hostname or ""
                path = (p.path or "")
        except Exception:
            return None
        if not host:
            return None
        path = path.lstrip("/")
        if path.endswith(".git"):
            path = path[:-4]
        parts = [seg for seg in path.split("/") if seg]
        if len(parts) < 2:
            return None
        owner, repo = parts[0], parts[1]
        return f"{host}/{owner}/{repo}"

    mode = (settings.project_identity_mode or "dir").strip().lower()
    # Mode: git-remote
    if mode == "git-remote":
        try:
            # Attempt to use GitPython for robustness across worktrees
            with _git_repo(human_key) as repo:
                remote_name = settings.project_identity_remote or "origin"
                remote_url: str | None = None
                # Prefer 'git remote get-url' to support multiple urls/rewrite rules
                try:
                    remote_url = repo.git.remote("get-url", remote_name).strip() or None
                except Exception:
                    # Fallback: use config if available
                    try:
                        remote = next((r for r in repo.remotes if r.name == remote_name), None)
                        if remote and remote.urls:
                            remote_url = next(iter(remote.urls), None)
                    except Exception:
                        remote_url = None
                normalized = _norm_remote(remote_url)
                if normalized:
                    base = normalized.rsplit("/", 1)[-1] or "repo"
                    canonical = normalized  # privacy-safe canonical string
                    return f"{base}-{_short_sha1(canonical)}"
        except (InvalidGitRepositoryError, NoSuchPathError, Exception):
            # Non-git directory or error; fall through to fallback
            pass
        # Fallback to dir behavior if we cannot resolve a normalized remote
        return slugify(human_key)

    # Mode: git-toplevel
    if mode == "git-toplevel":
        try:
            with _git_repo(human_key) as repo:
                top = repo.git.rev_parse("--show-toplevel").strip()
                if top:
                    from pathlib import Path as _P

                    top_real = str(_P(top).resolve())
                    base = _P(top_real).name or "repo"
                    return f"{base}-{_short_sha1(top_real)}"
        except (InvalidGitRepositoryError, NoSuchPathError, Exception):
            return slugify(human_key)
        return slugify(human_key)

    # Mode: git-common-dir
    if mode == "git-common-dir":
        try:
            with _git_repo(human_key) as repo:
                # Prefer GitPython's common_dir which normalizes worktree paths
                try:
                    gdir = getattr(repo, "common_dir", None)
                except Exception:
                    gdir = None
                if not gdir:
                    gdir = repo.git.rev_parse("--git-common-dir").strip()
                if gdir:
                    from pathlib import Path as _P

                    gdir_real = str(_P(gdir).resolve())
                    base = "repo"
                    return f"{base}-{_short_sha1(gdir_real)}"
        except (InvalidGitRepositoryError, NoSuchPathError, Exception):
            return slugify(human_key)
        return slugify(human_key)

    # Default and 'dir' mode: strict back-compat
    return slugify(human_key)


def _resolve_project_identity(human_key: str) -> dict[str, object]:
    """
    Resolve identity details for a given human_key path.
    Returns: { slug, identity_mode_used, canonical_path, human_key,
               repo_root, git_common_dir, branch, worktree_name,
               core_ignorecase, normalized_remote, project_uid }
    Writes a private marker under .git/agent-mail/project-id when WORKTREES_ENABLED=1
    and no marker exists yet.
    """
    settings_local = get_settings()
    mode_config = (settings_local.project_identity_mode or "dir").strip().lower()
    mode_used = "dir" if not settings_local.worktrees_enabled else mode_config
    target_path = str(Path(human_key).expanduser().resolve())

    if not settings_local.worktrees_enabled:
        # Keep default behavior lightweight when worktree features are disabled.
        # (Avoid touching GitPython / spawning git subprocesses unnecessarily.)
        slug_value = slugify(human_key)
        try:
            project_uid = hashlib.sha256(target_path.encode("utf-8")).hexdigest()[:20]
        except Exception:
            project_uid = str(uuid.uuid4())
        return {
            "slug": slug_value,
            "identity_mode_used": "dir",
            "canonical_path": target_path,
            "human_key": human_key,
            "repo_root": None,
            "git_common_dir": None,
            "branch": None,
            "worktree_name": None,
            "core_ignorecase": None,
            "normalized_remote": None,
            "project_uid": project_uid,
            "discovery": None,
        }

    repo_root: Optional[str] = None
    git_common_dir: Optional[str] = None
    branch: Optional[str] = None
    default_branch: Optional[str] = None
    worktree_name: Optional[str] = None
    core_ignorecase: Optional[bool] = None
    normalized_remote: Optional[str] = None
    canonical_path: str = target_path

    def _norm_remote(url: Optional[str]) -> Optional[str]:
        if not url:
            return None
        u = url.strip()
        try:
            host = ""
            path = ""
            # SCP-like: git@host:owner/repo.git
            if "@" in u and ":" in u and not u.startswith(("http://", "https://", "ssh://", "git://")):
                at_pos = u.find("@")
                colon_pos = u.find(":", at_pos + 1)
                if colon_pos != -1:
                    host = u[at_pos + 1 : colon_pos]
                    path = u[colon_pos + 1 :]
            else:
                from urllib.parse import urlparse as _urlparse
                pr = _urlparse(u)
                host = (pr.hostname or "").lower()
                # Some ssh URLs include port; ignore
                path = (pr.path or "")
            host = host.lower()
            if not host:
                return None
            path = path.lstrip("/")
            if path.endswith(".git"):
                path = path[:-4]
            # collapse duplicate slashes
            while "//" in path:
                path = path.replace("//", "/")
            parts = [seg for seg in path.split("/") if seg]
            if len(parts) < 2:
                return None
            # Keep the last two segments (owner/repo) and normalize to lowercase
            # This supports nested group paths (e.g., GitLab subgroups)
            if len(parts) >= 2:
                owner, repo_name = parts[-2].lower(), parts[-1].lower()
            else:
                return None
            return f"{host}/{owner}/{repo_name}"
        except Exception:
            return None

    # Discovery YAML: optional override
    def _read_discovery_yaml(base_dir: str) -> dict[str, object]:
        try:
            ypath = Path(base_dir) / ".agent-mail.yaml"
            if not ypath.exists():
                return {}
            # Prefer PyYAML when available for robust parsing; fallback to minimal parser
            try:
                import yaml as _yaml
                loaded = _yaml.safe_load(ypath.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    # Keep only known keys to avoid surprises
                    allowed = {"project_uid", "product_uid"}
                    return {k: str(v) for k, v in loaded.items() if k in allowed and isinstance(v, (str, int))}
                return {}
            except Exception:
                data = {}
                for line in ypath.read_text(encoding="utf-8").splitlines():
                    s = line.strip()
                    if not s or s.startswith("#") or ":" not in s:
                        continue
                    key, value = s.split(":", 1)
                    k = key.strip()
                    if k not in {"project_uid", "product_uid"}:
                        continue
                    # strip inline comments
                    v = value.split("#", 1)[0].strip().strip("'\"")
                    if v:
                        data[k] = v
                return data
        except Exception:
            return {}

    try:
        with _git_repo(target_path) as repo:
            repo_root = str(Path(repo.working_tree_dir or "").resolve())
            try:
                git_common_dir = repo.git.rev_parse("--git-common-dir").strip()
            except Exception:
                git_common_dir = None
            try:
                branch = repo.active_branch.name
            except Exception:
                try:
                    branch = repo.git.rev_parse("--abbrev-ref", "HEAD").strip()
                except Exception:
                    branch = None
            try:
                worktree_name = Path(repo.working_tree_dir or "").name or None
            except Exception:
                worktree_name = None
            try:
                core_ic = repo.config_reader().get_value("core", "ignorecase", "false")
                core_ignorecase = str(core_ic).strip().lower() == "true"
            except Exception:
                core_ignorecase = None
            remote_name = settings_local.project_identity_remote or "origin"
            remote_url_local: Optional[str] = None
            try:
                remote_url_local = repo.git.remote("get-url", remote_name).strip() or None
            except Exception:
                try:
                    r = next((r for r in repo.remotes if r.name == remote_name), None)
                    if r and r.urls:
                        remote_url_local = next(iter(r.urls), None)
                except Exception:
                    remote_url_local = None
            normalized_remote = _norm_remote(remote_url_local)
            try:
                sym = repo.git.symbolic_ref(
                    f"refs/remotes/{settings_local.project_identity_remote or 'origin'}/HEAD"
                ).strip()
                if sym.startswith("refs/remotes/"):
                    default_branch = sym.rsplit("/", 1)[-1]
            except Exception:
                default_branch = "main"
    except (InvalidGitRepositoryError, NoSuchPathError, Exception):
        pass  # Non-git directory; continue with fallback values

    if mode_used == "git-remote" and normalized_remote:
        canonical_path = normalized_remote
    elif mode_used == "git-toplevel" and repo_root:
        canonical_path = repo_root
    elif mode_used == "git-common-dir" and git_common_dir:
        canonical_path = str(Path(git_common_dir).resolve())
    else:
        canonical_path = target_path

    # Compute project_uid via precedence:
    # committed marker -> discovery yaml -> private marker -> remote fingerprint -> git-common-dir hash -> dir hash
    marker_committed: Optional[Path] = Path(repo_root or "") / ".agent-mail-project-id" if repo_root else None
    marker_private: Optional[Path] = Path(git_common_dir or "") / "agent-mail" / "project-id" if git_common_dir else None
    # Normalize marker_private to absolute if git_common_dir is relative (common for non-linked worktrees)
    if marker_private is not None and not marker_private.is_absolute():
        try:
            base = Path(repo_root or target_path)
            marker_private = (base / marker_private).resolve()
        except Exception:
            pass
    discovery: dict[str, object] = _read_discovery_yaml(repo_root or target_path)
    project_uid: Optional[str] = None
    try:
        if marker_committed and marker_committed.exists():
            project_uid = (marker_committed.read_text(encoding="utf-8").strip() or None)
    except Exception:
        project_uid = None
    if not project_uid:
        # Discovery yaml override
        uid = str(discovery.get("project_uid", "")).strip() if discovery else ""
        if uid:
            project_uid = uid
    if not project_uid:
        try:
            if marker_private and marker_private.exists():
                project_uid = (marker_private.read_text(encoding="utf-8").strip() or None)
        except Exception:
            project_uid = None
    if not project_uid:
        # Remote fingerprint
        remote_uid: Optional[str] = None
        try:
            if normalized_remote:
                fingerprint = f"{normalized_remote}@{default_branch or 'main'}"
                remote_uid = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()[:20]
        except Exception:
            remote_uid = None
        if remote_uid:
            project_uid = remote_uid
    if not project_uid and git_common_dir:
        try:
            project_uid = hashlib.sha256(str(Path(git_common_dir).resolve()).encode("utf-8")).hexdigest()[:20]
        except Exception:
            project_uid = None
    if not project_uid:
        try:
            project_uid = hashlib.sha256(target_path.encode("utf-8")).hexdigest()[:20]
        except Exception:
            project_uid = str(uuid.uuid4())

    # Write private marker if gated and we have a git common dir
    if settings_local.worktrees_enabled and marker_private and not marker_private.exists():
        try:
            marker_private.parent.mkdir(parents=True, exist_ok=True)
            marker_private.write_text(project_uid + "\n", encoding="utf-8")
        except Exception:
            pass

    slug_value = _compute_project_slug(target_path)
    payload = {
        "slug": slug_value,
        "identity_mode_used": mode_used,
        "canonical_path": canonical_path,
        "human_key": target_path,
        "repo_root": repo_root,
        "git_common_dir": git_common_dir,
        "branch": branch,
        "worktree_name": worktree_name,
        "core_ignorecase": core_ignorecase,
        "normalized_remote": normalized_remote,
        "project_uid": project_uid,
        "discovery": discovery or None,
    }
    # Rich-styled identity decision logging (optional)
    try:
        if get_settings().tools_log_enabled:
            from rich.console import Console as _Console  # local import to avoid global dependency
            from rich.table import Table as _Table
            console = _Console()
            table = _Table(title="Identity Resolution", show_header=True, header_style="bold white on blue")
            table.add_column("Field", style="bold cyan")
            table.add_column("Value")
            table.add_row("Mode", str(payload["identity_mode_used"] or "dir"))
            table.add_row("Slug", str(payload["slug"]))
            table.add_row("Canonical", str(payload["canonical_path"]))
            table.add_row("Repo Root", str(payload["repo_root"] or ""))
            table.add_row("Git Common Dir", str(payload["git_common_dir"] or ""))
            table.add_row("Branch", str(payload["branch"] or ""))
            table.add_row("Worktree", str(payload["worktree_name"] or ""))
            table.add_row("Ignorecase", str(payload["core_ignorecase"]))
            table.add_row("Normalized Remote", str(payload["normalized_remote"] or ""))
            table.add_row("Project UID", str(payload["project_uid"] or ""))
            console.print(table)
    except Exception:
        # Never fail due to logging
        pass
    return payload


async def _ensure_project(human_key: str) -> Project:
    await ensure_schema()
    # Resolve symlinks to canonical path so /dp/ntm and /data/projects/ntm
    # resolve to the same project identity
    human_key = str(Path(human_key).resolve())
    slug = _compute_project_slug(human_key)
    for attempt in range(6):
        try:
            async with get_session() as session:
                result = await session.execute(select(Project).where(Project.slug == slug))
                project = result.scalars().first()
                if project:
                    return project
                project = Project(slug=slug, human_key=human_key)
                session.add(project)
                try:
                    await session.commit()
                except IntegrityError:
                    # Concurrent ensure_project: another caller created the row. Treat as idempotent.
                    await session.rollback()
                    result = await session.execute(select(Project).where(Project.slug == slug))
                    project = result.scalars().first()
                    if project:
                        return project
                    raise
                await session.refresh(project)
                return project
        except OperationalError as exc:
            error_msg = str(exc).lower()
            is_lock_error = any(phrase in error_msg for phrase in ("database is locked", "database is busy", "locked"))
            if not is_lock_error or attempt >= 5:
                raise
            await asyncio.sleep(min(0.05 * (2**attempt), 0.5))

    raise RuntimeError("ensure_project retry loop exited unexpectedly")


def _similarity_score(a: str, b: str) -> float:
    """Compute similarity score between two strings (0.0 to 1.0)."""
    return SequenceMatcher(None, a.lower(), b.lower()).ratio()


async def _find_similar_projects(identifier: str, limit: int = 5, min_score: float = 0.4) -> list[tuple[str, str, float]]:
    """Find projects with similar slugs/names. Returns list of (slug, human_key, score)."""
    slug = slugify(identifier)
    suggestions: list[tuple[str, str, float]] = []
    async with get_session() as session:
        result = await session.execute(select(Project))
        projects = result.scalars().all()
        for p in projects:
            # Check both slug and human_key similarity
            slug_score = _similarity_score(slug, p.slug)
            key_score = _similarity_score(identifier, p.human_key) if p.human_key else 0.0
            best_score = max(slug_score, key_score)
            if best_score >= min_score:
                suggestions.append((p.slug, p.human_key, best_score))
    suggestions.sort(key=lambda x: x[2], reverse=True)
    return suggestions[:limit]


async def _get_project_by_identifier(identifier: str) -> Project:
    """Get project by identifier with helpful error messages and suggestions."""
    await ensure_schema()

    # Validate input
    if not identifier or not identifier.strip():
        raise ToolExecutionError(
            "INVALID_ARGUMENT",
            "Project identifier cannot be empty. Provide a project path like '/data/projects/myproject' or a slug like 'myproject'.",
            recoverable=True,
            data={"parameter": "project_key", "provided": repr(identifier)},
        )

    raw_identifier = identifier.strip()
    canonical_identifier = raw_identifier
    # Resolve absolute paths to canonical form so symlink aliases map to one project.
    try:
        candidate = Path(raw_identifier).expanduser()
        if candidate.is_absolute():
            canonical_identifier = str(candidate.resolve())
    except Exception:
        canonical_identifier = raw_identifier

    # Detect common placeholder patterns - these indicate unconfigured hooks/settings
    _placeholder_patterns = [
        "YOUR_PROJECT",
        "YOUR_PROJECT_PATH",
        "YOUR_PROJECT_KEY",
        "PLACEHOLDER",
        "<PROJECT>",
        "{PROJECT}",
        "$PROJECT",
    ]
    identifier_upper = raw_identifier.upper()
    for pattern in _placeholder_patterns:
        if pattern in identifier_upper or identifier_upper == pattern:
            raise ToolExecutionError(
                "CONFIGURATION_ERROR",
                f"Detected placeholder value '{identifier}' instead of a real project path. "
                f"This typically means a hook or integration script hasn't been configured yet. "
                f"Replace placeholder values in your .claude/settings.json or environment variables "
                f"with actual project paths like '/Users/you/projects/myproject'.",
                recoverable=True,
                data={
                    "parameter": "project_key",
                    "provided": identifier,
                    "detected_placeholder": pattern,
                    "fix_hint": "Update AGENT_MAIL_PROJECT or project_key in your configuration",
                },
            )

    slug = slugify(canonical_identifier)
    async with get_session() as session:
        result = await session.execute(
            select(Project).where(
                or_(
                    Project.slug == slug,
                    Project.human_key == canonical_identifier,
                    Project.human_key == raw_identifier,
                )
            )
        )
        project = result.scalars().first()
        if project:
            return project

    # Project not found - provide helpful suggestions
    suggestions = await _find_similar_projects(raw_identifier)

    if suggestions:
        suggestion_text = ", ".join([f"'{s[0]}'" for s in suggestions[:3]])
        raise ToolExecutionError(
            "NOT_FOUND",
            f"Project '{raw_identifier}' not found. Did you mean: {suggestion_text}? "
            f"Use ensure_project to create a new project, or check spelling.",
            recoverable=True,
            data={
                "identifier": raw_identifier,
                "slug_searched": slug,
                "suggestions": [{"slug": s[0], "human_key": s[1], "score": round(s[2], 2)} for s in suggestions],
            },
        )
    else:
        raise ToolExecutionError(
            "NOT_FOUND",
            f"Project '{raw_identifier}' not found and no similar projects exist. "
            f"Use ensure_project to create a new project first. "
            f"Example: ensure_project(human_key='/path/to/your/project')",
            recoverable=True,
            data={"identifier": raw_identifier, "slug_searched": slug},
        )


def _canonical_project_pair(a_id: int, b_id: int) -> tuple[int, int]:
    if a_id == b_id:
        raise ValueError("Project pair must reference distinct projects.")
    return (a_id, b_id) if a_id < b_id else (b_id, a_id)


async def _build_project_profile(
    project: Project,
    agent_names: list[str],
) -> str:
    pieces: list[str] = [
        f"Identifier: {project.human_key}",
        f"Slug: {project.slug}",
        f"Agents: {', '.join(agent_names) if agent_names else 'None registered'}",
    ]

    base_path = Path(project.human_key)
    if base_path.exists():
        total_chars = 0
        seen_files: set[Path] = set()
        for rel_name in _PROJECT_PROFILE_FILENAMES:
            candidate = base_path / rel_name
            if candidate in seen_files or not candidate.exists() or not candidate.is_file():
                continue
            preview = await _read_file_preview(candidate, max_chars=_PROJECT_PROFILE_PER_FILE_CHARS)
            if not preview:
                continue
            pieces.append(f"===== {rel_name} =====\n{preview}")
            seen_files.add(candidate)
            total_chars += len(preview)
            if total_chars >= _PROJECT_PROFILE_MAX_TOTAL_CHARS:
                break
    return "\n\n".join(pieces)


async def _score_project_pair(
    project_a: Project,
    profile_a: str,
    project_b: Project,
    profile_b: str,
) -> tuple[float, str]:
    settings = get_settings()
    heuristic_score, heuristic_reason = _heuristic_project_similarity(project_a, project_b)

    if not settings.llm.enabled:
        return heuristic_score, heuristic_reason

    system_prompt = (
        "You are an expert analyst who maps whether two software projects are tightly related parts "
        "of the same overall product. Score relationship strength from 0.0 (unrelated) to 1.0 "
        "(same initiative with tightly coupled scope)."
    )
    user_prompt = (
        "Return strict JSON with keys: score (float 0-1), rationale (<=120 words).\n"
        "Focus on whether these projects represent collaborating slices of the same product.\n\n"
        f"Project A Profile:\n{profile_a}\n\nProject B Profile:\n{profile_b}"
    )

    try:
        completion = await complete_system_user(system_prompt, user_prompt, max_tokens=400)
        payload = completion.content.strip()
        try:
            data = json.loads(payload)
        except json.JSONDecodeError as exc:
            logger.debug("project_sibling.json_parse_failed", extra={"payload": payload[:200], "error": str(exc)})
            return heuristic_score, heuristic_reason + " (JSON parse fallback)"
        score = float(data.get("score", heuristic_score))
        rationale = str(data.get("rationale", "")).strip() or heuristic_reason
        return min(max(score, 0.0), 1.0), rationale
    except Exception as exc:
        logger.debug("project_sibling.llm_failed", exc_info=exc)
        return heuristic_score, heuristic_reason + " (LLM fallback)"


async def refresh_project_sibling_suggestions(*, max_pairs: int = _PROJECT_SIBLING_REFRESH_LIMIT) -> None:
    await ensure_schema()
    async with get_session() as session:
        projects = (await session.execute(select(Project))).scalars().all()
        if len(projects) < 2:
            return

        agents_rows = await session.execute(select(Agent.project_id, Agent.name))
        agent_map: dict[int, list[str]] = defaultdict(list)
        for proj_id, name in agents_rows.fetchall():
            agent_map[int(proj_id)].append(name)

        existing_rows = (await session.execute(select(ProjectSiblingSuggestion))).scalars().all()
        existing_map: dict[tuple[int, int], ProjectSiblingSuggestion] = {}
        for suggestion in existing_rows:
            pair = _canonical_project_pair(suggestion.project_a_id, suggestion.project_b_id)
            existing_map[pair] = suggestion

        now = datetime.now(timezone.utc)
        naive_now = _naive_utc(now)
        to_evaluate: list[tuple[Project, Project, ProjectSiblingSuggestion | None]] = []
        for idx, project_a in enumerate(projects):
            if project_a.id is None:
                continue
            for project_b in projects[idx + 1 :]:
                if project_b.id is None:
                    continue

                # CRITICAL: Skip projects with identical human_key - they're the SAME project, not siblings
                # Two agents in /data/projects/smartedgar_mcp are on the SAME project
                # Siblings would be different directories like /data/projects/smartedgar_mcp_frontend
                if project_a.human_key == project_b.human_key:
                    continue

                pair = _canonical_project_pair(project_a.id, project_b.id)
                suggestion = existing_map.get(pair)
                if suggestion is None:
                    to_evaluate.append((project_a, project_b, None))
                else:
                    eval_ts = suggestion.evaluated_ts
                    # Normalize to timezone-aware UTC before arithmetic; SQLite may return naive datetimes
                    if eval_ts is not None:
                        if eval_ts.tzinfo is None or eval_ts.tzinfo.utcoffset(eval_ts) is None:
                            eval_ts = eval_ts.replace(tzinfo=timezone.utc)
                        else:
                            eval_ts = eval_ts.astimezone(timezone.utc)
                        age = now - eval_ts
                    else:
                        age = _PROJECT_SIBLING_REFRESH_TTL
                    if suggestion.status == "dismissed" and age < timedelta(days=7):
                        continue
                    if age >= _PROJECT_SIBLING_REFRESH_TTL and len(to_evaluate) < max_pairs:
                        to_evaluate.append((project_a, project_b, suggestion))
                if len(to_evaluate) >= max_pairs:
                    break

        if not to_evaluate:
            return

        updated = False
        for project_a, project_b, suggestion in to_evaluate[:max_pairs]:
            profile_a = await _build_project_profile(project_a, agent_map.get(project_a.id or -1, []))
            profile_b = await _build_project_profile(project_b, agent_map.get(project_b.id or -1, []))
            score, rationale = await _score_project_pair(project_a, profile_a, project_b, profile_b)

            pair = _canonical_project_pair(project_a.id or 0, project_b.id or 0)
            record = existing_map.get(pair) if suggestion is None else suggestion
            if record is None:
                record = ProjectSiblingSuggestion(
                    project_a_id=pair[0],
                    project_b_id=pair[1],
                    score=score,
                    rationale=rationale,
                    status="suggested",
                )
                session.add(record)
                existing_map[pair] = record
            else:
                record.score = score
                record.rationale = rationale
                # Preserve user decisions
                if record.status not in {"confirmed", "dismissed"}:
                    record.status = "suggested"
            record.evaluated_ts = naive_now
            updated = True

        if updated:
            await session.commit()


async def get_project_sibling_data() -> dict[int, dict[str, list[dict[str, object]]]]:
    await ensure_schema()
    async with get_session() as session:
        rows = await session.execute(
            text(
                """
                SELECT s.id, s.project_a_id, s.project_b_id, s.score, s.status, s.rationale,
                       s.evaluated_ts, pa.slug AS slug_a, pa.human_key AS human_a,
                       pb.slug AS slug_b, pb.human_key AS human_b
                FROM project_sibling_suggestions s
                JOIN projects pa ON pa.id = s.project_a_id
                JOIN projects pb ON pb.id = s.project_b_id
                ORDER BY s.score DESC
                """
            )
        )
        result_map: dict[int, dict[str, list[dict[str, object]]]] = defaultdict(lambda: {"confirmed": [], "suggested": []})

        for row in rows.fetchall():
            suggestion_id = int(row[0])
            a_id = int(row[1])
            b_id = int(row[2])
            entry_base = {
                "suggestion_id": suggestion_id,
                "score": float(row[3] or 0.0),
                "status": row[4],
                "rationale": row[5] or "",
                "evaluated_ts": str(row[6]) if row[6] else None,
            }
            a_info = {"id": a_id, "slug": row[7], "human_key": row[8]}
            b_info = {"id": b_id, "slug": row[9], "human_key": row[10]}

            for current, other in ((a_info, b_info), (b_info, a_info)):
                bucket = result_map[current["id"]]
                entry = {**entry_base, "peer": other}
                if entry["status"] == "confirmed":
                    bucket["confirmed"].append(entry)
                elif entry["status"] != "dismissed" and float(cast(float, entry_base["score"])) >= _PROJECT_SIBLING_MIN_SUGGESTION_SCORE:
                    bucket["suggested"].append(entry)

        return result_map


async def update_project_sibling_status(project_id: int, other_id: int, status: str) -> dict[str, object]:
    normalized_status = status.lower()
    if normalized_status not in {"confirmed", "dismissed", "suggested"}:
        raise ValueError("Invalid status")

    await ensure_schema()
    async with get_session() as session:
        pair = _canonical_project_pair(project_id, other_id)
        suggestion = (
            await session.execute(
                select(ProjectSiblingSuggestion).where(
                    ProjectSiblingSuggestion.project_a_id == pair[0],
                    ProjectSiblingSuggestion.project_b_id == pair[1],
                )
            )
        ).scalars().first()

        if suggestion is None:
            # Create a baseline suggestion via refresh for this specific pair
            project_a_obj = await session.get(Project, pair[0])
            project_b_obj = await session.get(Project, pair[1])
            projects = [proj for proj in (project_a_obj, project_b_obj) if proj is not None]
            if len(projects) != 2:
                raise NoResultFound("Project pair not found")
            project_map = {proj.id: proj for proj in projects if proj.id is not None}
            agents_rows = await session.execute(
                select(Agent.project_id, Agent.name).where(
                    or_(Agent.project_id == pair[0], cast(Any, Agent.project_id) == pair[1])
                )
            )
            agent_map: dict[int, list[str]] = defaultdict(list)
            for proj_id, name in agents_rows.fetchall():
                agent_map[int(proj_id)].append(name)
            profile_a = await _build_project_profile(project_map[pair[0]], agent_map.get(pair[0], []))
            profile_b = await _build_project_profile(project_map[pair[1]], agent_map.get(pair[1], []))
            score, rationale = await _score_project_pair(project_map[pair[0]], profile_a, project_map[pair[1]], profile_b)
            suggestion = ProjectSiblingSuggestion(
                project_a_id=pair[0],
                project_b_id=pair[1],
                score=score,
                rationale=rationale,
                status="suggested",
            )
            session.add(suggestion)
            await session.flush()

        now = datetime.now(timezone.utc)
        naive_now = _naive_utc(now)
        suggestion.status = normalized_status
        suggestion.evaluated_ts = naive_now
        if normalized_status == "confirmed":
            suggestion.confirmed_ts = naive_now
            suggestion.dismissed_ts = None
        elif normalized_status == "dismissed":
            suggestion.dismissed_ts = naive_now
            suggestion.confirmed_ts = None

        await session.commit()

        project_a_obj = await session.get(Project, suggestion.project_a_id)
        project_b_obj = await session.get(Project, suggestion.project_b_id)
        project_lookup = {
            proj.id: proj
            for proj in (project_a_obj, project_b_obj)
            if proj is not None and proj.id is not None
        }

        def _project_payload(proj_id: int) -> dict[str, object]:
            proj = project_lookup.get(proj_id)
            if proj is None:
                return {"id": proj_id, "slug": "", "human_key": ""}
            return {"id": proj.id, "slug": proj.slug, "human_key": proj.human_key}

        return {
            "id": suggestion.id,
            "status": suggestion.status,
            "score": suggestion.score,
            "rationale": suggestion.rationale,
            "project_a": _project_payload(suggestion.project_a_id),
            "project_b": _project_payload(suggestion.project_b_id),
            "evaluated_ts": str(suggestion.evaluated_ts) if suggestion.evaluated_ts else None,
        }


def _heuristic_project_similarity(project_a: Project, project_b: Project) -> tuple[float, str]:
    """Calculate heuristic similarity score between two projects.

    Returns (score, rationale) where score is 0.0-1.0.
    Higher scores indicate stronger similarity suggesting potential sibling relationship.
    """
    # CRITICAL: Projects with identical human_key are the SAME project, not siblings
    # This should be filtered earlier, but adding safeguard here
    if project_a.human_key == project_b.human_key:
        return 0.0, "ERROR: Identical human_key - these are the SAME project, not siblings"

    slug_ratio = SequenceMatcher(None, project_a.slug, project_b.slug).ratio()
    human_ratio = SequenceMatcher(None, project_a.human_key, project_b.human_key).ratio()
    shared_prefix = 0.0
    try:
        prefix_a = Path(project_a.human_key).name.lower()
        prefix_b = Path(project_b.human_key).name.lower()
        shared_prefix = SequenceMatcher(None, prefix_a, prefix_b).ratio()
    except Exception:
        shared_prefix = 0.0

    score = max(slug_ratio, human_ratio, shared_prefix)
    reasons: list[str] = []
    if slug_ratio > 0.6:
        reasons.append(f"Slugs are similar ({slug_ratio:.2f})")
    if human_ratio > 0.6:
        reasons.append(f"Human keys align ({human_ratio:.2f})")
    parent_a = Path(project_a.human_key).parent
    parent_b = Path(project_b.human_key).parent
    if parent_a == parent_b:
        score = max(score, 0.85)
        reasons.append("Projects share the same parent directory")
    if not reasons:
        reasons.append("Heuristic comparison found limited overlap; treating as weak relation")
    return min(max(score, 0.0), 1.0), ", ".join(reasons)


