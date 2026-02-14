"""Pure time and ISO-8601 utilities for agent mail."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional


def _iso(dt: object) -> str:
    """Return ISO-8601 in UTC from datetime or best-effort from string.

    Accepts datetime or ISO-like string; falls back to str(dt) if unknown.
    Naive datetimes (from SQLite) are assumed to be UTC already.
    """
    try:
        if isinstance(dt, str):
            try:
                parsed = datetime.fromisoformat(dt)
                # Handle naive parsed datetimes (assume UTC)
                if parsed.tzinfo is None or parsed.tzinfo.utcoffset(parsed) is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                return parsed.astimezone(timezone.utc).isoformat()
            except Exception:
                return dt
        if hasattr(dt, "astimezone"):
            # Handle naive datetimes from SQLite (assume UTC)
            if getattr(dt, "tzinfo", None) is None or dt.tzinfo.utcoffset(dt) is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).isoformat()
        return str(dt)
    except Exception:
        return str(dt)


def _ensure_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """Return a timezone-aware UTC datetime."""
    if dt is None:
        return None
    if dt.tzinfo is None or dt.tzinfo.utcoffset(dt) is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _naive_utc(dt: Optional[datetime] = None) -> datetime:
    """Return a naive UTC datetime for SQLite comparisons.

    SQLite stores datetimes without timezone info. When comparing Python
    datetime objects with SQLite DATETIME columns via SQLAlchemy, both must
    be naive to avoid 'can't compare offset-naive and offset-aware datetimes'.
    """
    if dt is None:
        dt = datetime.now(timezone.utc)
    if dt.tzinfo is not None:
        # Convert to UTC first, then strip timezone
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def _max_datetime(*timestamps: Optional[datetime]) -> Optional[datetime]:
    """Return the maximum datetime from a list of timestamps, ignoring None values."""
    values = [ts for ts in timestamps if ts is not None]
    if not values:
        return None
    return max(values)


def _parse_iso(raw_value: Optional[str]) -> Optional[datetime]:
    """Parse ISO-8601 timestamps, accepting a trailing 'Z' as UTC.

    Returns None when parsing fails.
    """
    if raw_value is None:
        return None
    s = raw_value.strip()
    if not s:
        return None
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(s)
    except ValueError:
        return None
