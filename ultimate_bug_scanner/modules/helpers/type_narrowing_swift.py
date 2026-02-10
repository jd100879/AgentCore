#!/usr/bin/env python3
"""Detect Swift guard let / optional bindings that continue without exiting."""
from __future__ import annotations

import re
import sys
from pathlib import Path

SKIP_DIRS = {".git", ".hg", ".svn", "build", "DerivedData", ".swiftpm", ".idea", "node_modules"}
GUARD_PATTERN = re.compile(r"guard\s+let\s+([A-Za-z_][\w]*)\s*=\s*[^\n]+\s+else\s*\{", re.MULTILINE)
NEGATIVE_NIL_GUARD = re.compile(r"if\s*\(?\s*([A-Za-z_][\w]*)\s*==\s*nil[^)\{]*\)?", re.MULTILINE)
POSITIVE_NIL_GUARD = re.compile(r"if\s*\(?\s*([A-Za-z_][\w]*)\s*!=\s*nil[^)\{]*\)?", re.MULTILINE)
OPTIONAL_CHAIN_GUARD = re.compile(r"if\s*\(?\s*([A-Za-z_][\w]*)\s*\?\.[^)\{]*\)?", re.MULTILINE)
FORCE_TEMPLATE = r"{name}\s*!"
ASSIGN_TEMPLATE = r"{name}\s*="
COMMENT_PATTERN = re.compile(r"//.*?$|/\*.*?\*/", re.MULTILINE | re.DOTALL)
EXIT_PATTERN = re.compile(
    r"\b(?:return|throw|break|continue)\b|\b(?:fatalError|preconditionFailure)\b",
    re.IGNORECASE,
)


def iter_swift_files(root: Path):
    if root.is_file():
        if root.suffix == ".swift" and not any(part in SKIP_DIRS for part in root.parts):
            yield root
        return
    for path in root.rglob("*.swift"):
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.is_file():
            yield path


def find_block_end(text: str, brace_start: int) -> int:
    depth = 0
    for idx in range(brace_start, len(text)):
        ch = text[idx]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return idx
    return len(text) - 1


def block_has_exit(block: str) -> bool:
    stripped = COMMENT_PATTERN.sub("", block)
    return bool(EXIT_PATTERN.search(stripped))


def line_col(text: str, pos: int) -> tuple[int, int]:
    line = text.count("\n", 0, pos) + 1
    last_newline = text.rfind("\n", 0, pos)
    if last_newline == -1:
        col = pos + 1
    else:
        col = pos - last_newline
    return line, col


def skip_ws(text: str, idx: int) -> int:
    while idx < len(text) and text[idx].isspace():
        idx += 1
    return idx


def extract_guard_region(text: str, match_end: int) -> tuple[str, int]:
    idx = skip_ws(text, match_end)
    if idx < len(text) and text[idx] == "{":
        block_end = find_block_end(text, idx)
        return text[idx : block_end + 1], block_end + 1
    newline = text.find("\n", idx)
    if newline == -1:
        newline = len(text)
    return text[idx:newline], newline


def collect_guard_issues(text: str, pattern: re.Pattern[str], message: str, skip_on_exit: bool = True):
    issues = []
    for match in pattern.finditer(text):
        name = match.group(1)
        block_text, guard_end = extract_guard_region(text, match.end())
        if skip_on_exit and block_has_exit(block_text):
            continue
        assign_regex = re.compile(ASSIGN_TEMPLATE.format(name=re.escape(name)))
        force_regex = re.compile(FORCE_TEMPLATE.format(name=re.escape(name)))
        search_from = guard_end
        while True:
            force_match = force_regex.search(text, search_from)
            if not force_match:
                break
            assign_match = assign_regex.search(text, search_from, force_match.start())
            if assign_match:
                break
            line, col = line_col(text, force_match.start())
            issues.append((line, col, message.format(name=name)))
            break
    return issues


def analyze_file(path: Path):
    text = path.read_text(encoding="utf-8", errors="ignore")
    issues = []
    # == nil: if (x == nil) { return } -> x! is safe. Skip on exit.
    issues.extend(collect_guard_issues(text, NEGATIVE_NIL_GUARD, "{name}! used after == nil guard without exit", skip_on_exit=True))
    
    # != nil: if (x != nil) { return } -> x! is unsafe (guaranteed crash). Don't skip.
    issues.extend(collect_guard_issues(text, POSITIVE_NIL_GUARD, "{name}! used after '!= nil' guard without exit", skip_on_exit=False))
    
    # ?. : if (x?.p) { return } -> x! is unsafe. Don't skip.
    issues.extend(collect_guard_issues(text, OPTIONAL_CHAIN_GUARD, "{name}! forced after ?. guard without exit", skip_on_exit=False))
    
    for match in GUARD_PATTERN.finditer(text):
        name = match.group(1)
        brace_start = max(match.end() - 1, match.start())
        block_end = find_block_end(text, brace_start)
        block_text = text[brace_start : block_end + 1]
        if block_has_exit(block_text):
            continue
        line, col = line_col(text, match.start())
        message = f"guard let '{name}' else-block does not exit before continuing"
        issues.append((line, col, message))
    return issues


def main() -> int:
    if len(sys.argv) < 2:
        print("Usage: type_narrowing_swift.py <project_dir>", file=sys.stderr)
        return 1
    root = Path(sys.argv[1]).resolve()
    if not root.exists():
        return 0
    for path in iter_swift_files(root):
        try:
            issues = analyze_file(path)
        except OSError:
            continue
        for line, col, message in issues:
            print(f"{path}:{line}:{col}\t{message}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
