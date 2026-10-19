#!/usr/bin/env python3
"""Report the state of the unified Listen monorepo checkout."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_ROOT = APP_ROOT.parent
REQUIRED_FILES = {
    "app": "app/pubspec.yaml",
    "core": "core/Cargo.toml",
    "gen": "gen/pyproject.toml",
}


def git(root: Path, *args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def has_monorepo_shape(path: Path) -> bool:
    return all((path / required).is_file() for required in REQUIRED_FILES.values())


def discover_source_root(start: Path) -> Path:
    candidate = start.expanduser().resolve()
    if candidate.name in REQUIRED_FILES and has_monorepo_shape(candidate.parent):
        candidate = candidate.parent
    repo_root = git(candidate, "rev-parse", "--show-toplevel")
    if repo_root:
        resolved = Path(repo_root).resolve()
        if has_monorepo_shape(resolved):
            return resolved
    while True:
        if has_monorepo_shape(candidate):
            return candidate
        parent = candidate.parent
        if parent == candidate:
            return start.expanduser().resolve()
        candidate = parent


@dataclass(frozen=True)
class MonorepoState:
    root: Path
    branch: str | None
    head: str | None
    dirty: bool
    problems: tuple[str, ...]


def inspect(root: Path) -> MonorepoState:
    root = root.resolve()
    problems: list[str] = []
    branch = git(root, "branch", "--show-current")
    head = git(root, "rev-parse", "--short", "HEAD")
    status = git(root, "status", "--porcelain")
    if git(root, "rev-parse", "--show-toplevel") is None:
        problems.append("source root is not inside a readable Git checkout")
    else:
        actual_root = Path(git(root, "rev-parse", "--show-toplevel") or "").resolve()
        if actual_root != root:
            problems.append(f"source root resolves to a nested Git checkout at {actual_root}")

    for tree, required in REQUIRED_FILES.items():
        tree_path = root / tree
        if not (root / required).is_file():
            problems.append(f"{required} is missing")
            continue
        tree_root = git(tree_path, "rev-parse", "--show-toplevel")
        if tree_root is not None and Path(tree_root).resolve() != root:
            problems.append(f"{tree}/ is a separate Git checkout")

    return MonorepoState(
        root=root,
        branch=branch or None,
        head=head or None,
        dirty=bool(status),
        problems=tuple(problems),
    )


def render(state: MonorepoState, markdown: bool) -> str:
    revision = (
        f"{state.branch or '(detached)'} @ {state.head or '(no commit)'}"
    )
    dirty = " [dirty]" if state.dirty else ""
    if markdown:
        lines = [f"## Listen monorepo status ({datetime.now():%Y-%m-%d %H:%M})", ""]
        lines.append(f"- Git: `{revision}`{dirty} — `{state.root}`")
        for tree, required in REQUIRED_FILES.items():
            lines.append(f"- `{tree}/`: `{state.root / required}`")
        lines += ["", "### Structure", ""]
        if state.problems:
            lines.extend(f"- ⚠ {problem}" for problem in state.problems)
        else:
            lines.append("- ✓ app, core, and gen share one Git root")
        return "\n".join(lines)

    lines = [f"Listen monorepo status ({datetime.now():%Y-%m-%d %H:%M})", ""]
    lines.append(f"  Git       {revision}{dirty}  ({state.root})")
    for tree, required in REQUIRED_FILES.items():
        lines.append(f"  {tree:<9} {state.root / required}")
    lines += ["", "Structure"]
    if state.problems:
        lines.extend(f"  ! {problem}" for problem in state.problems)
    else:
        lines.append("  ✓ app, core, and gen share one Git root")
    return "\n".join(lines)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--source-root",
        help="monorepo root (or LISTEN_SOURCE_ROOT); detected from this script by default",
    )
    parser.add_argument("--markdown", action="store_true")
    parser.add_argument("--strict", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    start = Path(args.source_root or os.environ.get("LISTEN_SOURCE_ROOT") or DEFAULT_SOURCE_ROOT)
    root = discover_source_root(start)
    state = inspect(root)
    print(render(state, args.markdown))
    return 1 if args.strict and state.problems else 0


if __name__ == "__main__":
    sys.exit(main())
