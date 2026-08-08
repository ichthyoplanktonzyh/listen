#!/usr/bin/env python3
"""Report and verify the local listen-app/Core/Gen relationship.

The tool is local-only: it never fetches.  In an App git worktree, Core and Gen
are discovered beside App's canonical checkout (the parent of git-common-dir),
not beside the worktree directory.  Explicit CLI paths take precedence over
LISTEN_{APP,CORE,GEN}_REPO environment variables and discovery.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

APP_ROOT = Path(__file__).resolve().parents[1]
CONTRACT_FIELDS = (
    "manifest_schema_id",
    "resource_schema_id",
    "package_schema",
    "schema_version",
)
CONTRACT_CONST = re.compile(r'CONTRACT_VERSION:\s*&str\s*=\s*"([^"]+)"')
OPENAPI_VERSION = re.compile(r"^\s{2}version:\s*(\S+)", re.MULTILINE)


def git(repo: Path, *args: str) -> str | None:
    if not (repo / ".git").exists():
        return None
    try:
        result = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


def canonical_checkout(app_repo: Path) -> Path:
    common = git(app_repo, "rev-parse", "--git-common-dir")
    if not common:
        return app_repo
    common_path = Path(common)
    if not common_path.is_absolute():
        common_path = app_repo / common_path
    common_path = common_path.resolve()
    return common_path.parent if common_path.name == ".git" else app_repo


def discover_repositories(app_repo: Path) -> dict[str, Path]:
    canonical_app = canonical_checkout(app_repo)
    return {
        "listen-app": app_repo.resolve(),
        "listen-core": canonical_app.parent / "listen-core",
        "listen-gen": canonical_app.parent / "listen-gen",
    }


def resolve_repository_paths(args: argparse.Namespace) -> dict[str, Path]:
    app = Path(args.app_repo or os.environ.get("LISTEN_APP_REPO") or APP_ROOT)
    paths = discover_repositories(app)
    overrides = {
        "listen-core": args.core_repo or os.environ.get("LISTEN_CORE_REPO"),
        "listen-gen": args.gen_repo or os.environ.get("LISTEN_GEN_REPO"),
    }
    for name, override in overrides.items():
        if override:
            paths[name] = Path(override).expanduser().resolve()
    return paths


@dataclass
class Repo:
    name: str
    path: Path

    @property
    def present(self) -> bool:
        return git(self.path, "rev-parse", "--git-dir") is not None

    @property
    def branch(self) -> str:
        return git(self.path, "branch", "--show-current") or "(detached)"

    @property
    def head(self) -> str:
        return git(self.path, "log", "-1", "--format=%h") or "?"

    @property
    def head_date(self) -> str:
        return git(self.path, "log", "-1", "--format=%ai") or "?"

    @property
    def dirty(self) -> bool:
        return bool(git(self.path, "status", "--porcelain"))

    def commit_date(self, sha: str) -> str | None:
        return git(self.path, "log", "-1", "--format=%ai", sha)

    def contains(self, sha: str, ref: str = "HEAD") -> bool:
        return git(self.path, "merge-base", "--is-ancestor", sha, ref) is not None

    def file_at(self, sha: str, path: str) -> str | None:
        return git(self.path, "show", f"{sha}:{path}")


@dataclass(frozen=True)
class CorePin:
    sha: str
    contract_version: str
    runtime_version: str


@dataclass(frozen=True)
class GenReleasePin:
    sha: str
    tool_version: str


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def canonical_contract_sha(lock: dict[str, Any]) -> str:
    encoded = json.dumps(
        lock, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return "sha256:" + hashlib.sha256(encoded).hexdigest()


def contract_version_at(core: Repo, sha: str) -> str | None:
    source = core.file_at(sha, "crates/api-http/src/lib.rs")
    found = CONTRACT_CONST.search(source or "")
    return found.group(1) if found else None


def openapi_version_at(core: Repo, sha: str) -> str | None:
    source = core.file_at(sha, "contracts/openapi/v1.yaml")
    found = OPENAPI_VERSION.search(source or "")
    return found.group(1) if found else None


def compare_contract_locks(
    app_contract: dict[str, Any], gen_contract: dict[str, Any]
) -> list[str]:
    problems: list[str] = []
    app_authority = app_contract.get("authority")
    gen_authority = gen_contract.get("authority")
    if app_authority != gen_authority:
        problems.append(
            "App listen_gen.lock.json 与 Gen contracts.lock.json 的 authority 不一致"
        )
    for field in CONTRACT_FIELDS:
        if app_contract.get(field) != gen_contract.get(field):
            problems.append(
                f"App listen_gen.lock.json 与 Gen contracts.lock.json 的 {field} 不一致"
            )
    expected_digest = canonical_contract_sha(gen_contract)
    if app_contract.get("canonical_sha256") != expected_digest:
        problems.append(
            "App listen_gen.lock.json 的 canonical_sha256 与 Gen contracts.lock.json "
            f"规范化摘要不一致（应为 {expected_digest}）"
        )
    return problems


def inspect(repos: dict[str, Repo]) -> tuple[CorePin | None, GenReleasePin | None, list[str]]:
    problems: list[str] = []
    app = repos["listen-app"]
    core = repos["listen-core"]
    gen = repos["listen-gen"]
    backend = read_json(app.path / "backend.lock.json")
    app_gen = read_json(app.path / "listen_gen.lock.json")
    gen_contract = read_json(gen.path / "contracts.lock.json") if gen.present else None

    core_pin = None
    if backend:
        core_pin = CorePin(
            str(backend.get("core_git_sha", "")),
            str(backend.get("contract", {}).get("version", "")),
            str(backend.get("runtime", {}).get("version", "")),
        )
    else:
        problems.append("App backend.lock.json 缺失或不是有效 JSON object")

    gen_pin = None
    if app_gen:
        gen_pin = GenReleasePin(
            str(app_gen.get("source_git_sha", "")),
            str(app_gen.get("tool", {}).get("version", "")),
        )
    else:
        problems.append("App listen_gen.lock.json 缺失或不是有效 JSON object")

    if not core.present:
        problems.append("listen-core 本地 checkout 不存在，无法校验 Core binary pin")
    elif core_pin:
        if not core_pin.sha or core.commit_date(core_pin.sha) is None:
            problems.append(f"App 钉的 Core commit {core_pin.sha[:8] or '(empty)'} 在本地解析不到")
        else:
            declared = contract_version_at(core, core_pin.sha)
            openapi = openapi_version_at(core, core_pin.sha)
            if declared != core_pin.contract_version:
                problems.append(
                    f"backend.lock.json 记着 contract {core_pin.contract_version}，"
                    f"但 Core pin 实际声明 {declared or '(missing)'}"
                )
            if declared and openapi and declared != openapi:
                problems.append(
                    f"Core pin 自身不一致：CONTRACT_VERSION={declared}，OpenAPI={openapi}"
                )

    if not gen.present:
        problems.append("listen-gen 本地 checkout 不存在，无法校验 Gen release pin/contract lock")
    elif gen_pin:
        if not gen_pin.sha or gen.commit_date(gen_pin.sha) is None:
            problems.append(f"App 钉的 Gen commit {gen_pin.sha[:8] or '(empty)'} 在本地解析不到")
        elif not gen.contains(gen_pin.sha):
            problems.append(
                f"当前 Gen checkout 的 HEAD 不包含 App 钉的 commit {gen_pin.sha[:8]}"
            )

    if gen.present and gen_contract is None:
        problems.append("Gen contracts.lock.json 缺失或不是有效 JSON object")
    elif app_gen and gen_contract:
        app_contract = app_gen.get("content_package_contract")
        if not isinstance(app_contract, dict):
            problems.append("App listen_gen.lock.json 缺少 content_package_contract")
        else:
            problems.extend(compare_contract_locks(app_contract, gen_contract))

    return core_pin, gen_pin, problems


def render(repos: dict[str, Repo], core_pin: CorePin | None, gen_pin: GenReleasePin | None, problems: list[str], markdown: bool) -> str:
    if markdown:
        lines = [f"## listen 三仓状态 ({datetime.now():%Y-%m-%d %H:%M})", ""]
        for repo in repos.values():
            state = f"`{repo.branch}` @ `{repo.head}`" if repo.present else "本地不存在"
            lines.append(f"- `{repo.name}`: {state} — `{repo.path}`")
        lines += ["", "### Pins", ""]
    else:
        lines = [f"listen 三仓状态  ({datetime.now():%Y-%m-%d %H:%M})", ""]
        for repo in repos.values():
            state = f"{repo.branch} @ {repo.head}" if repo.present else "本地不存在"
            dirty = " [dirty]" if repo.present and repo.dirty else ""
            lines.append(f"  {repo.name:<12} {state}{dirty}  ({repo.path})")
        lines += ["", "Pins"]
    if core_pin:
        lines.append(
            f"  Core binary core_git_sha: {core_pin.sha}  "
            f"contract {core_pin.contract_version}  runtime {core_pin.runtime_version}"
        )
    if gen_pin:
        lines.append(
            f"  Gen release source_git_sha: {gen_pin.sha}  tool {gen_pin.tool_version}"
        )
    lines += ["", "一致性"]
    if problems:
        lines.extend(f"  ⚠ {problem}" for problem in problems)
    else:
        lines.append("  ✓ Core pin、Gen release pin 与 content-package contract lock 一致")
    return "\n".join(lines)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app-repo", help="listen-app checkout (or LISTEN_APP_REPO)")
    parser.add_argument("--core-repo", help="listen-core checkout (or LISTEN_CORE_REPO)")
    parser.add_argument("--gen-repo", help="listen-gen checkout (or LISTEN_GEN_REPO)")
    parser.add_argument("--markdown", action="store_true")
    parser.add_argument("--strict", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    repos = {
        name: Repo(name, path) for name, path in resolve_repository_paths(args).items()
    }
    core_pin, gen_pin, problems = inspect(repos)
    print(render(repos, core_pin, gen_pin, problems, args.markdown))
    return 1 if args.strict and problems else 0


if __name__ == "__main__":
    sys.exit(main())
