#!/usr/bin/env python3
"""Report and verify the local listen-app/Core/Gen relationship.

The tool is local-only: it never fetches.  In an App git worktree, Core and Gen
are discovered beside App's canonical checkout (the parent of git-common-dir),
not beside the worktree directory.  Explicit CLI paths take precedence over
LISTEN_{APP,CORE,GEN}_REPO environment variables and discovery.

The report separates two facts that are easy to conflate:

- Pinned lock integrity: does each committed lock pin an identity that
  really exists and is internally consistent (resolvable commits, a
  content-package contract lock matching the pinned Gen commit, a Core pin
  whose own contract/OpenAPI versions agree)?
- Runnable pinned stack: can the App code as checked out run on the exact
  artifacts those locks pin?  The App requires Core contract 4.0+ and a Gen
  capability engine (machine-event v2, content-package v3, the three ASR
  provider requirements); a lock that pins the last published Core 3.2 /
  Gen 0.4.0 is honest but not runnable until a new Core/Gen release lands.
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
CONTRACT_FIELDS = ("package_schema", "schema_version")
CONTRACT_CONST = re.compile(r'CONTRACT_VERSION:\s*&str\s*=\s*"([^"]+)"')
OPENAPI_VERSION = re.compile(r"^\s{2}version:\s*(\S+)", re.MULTILINE)

# App-side compatibility requirements, extracted from the App source so the
# report follows the code instead of duplicating constants that drift.
SUPPORTED_CONTRACT_MAJOR = re.compile(
    r"const\s+supportedContractMajor\s*=\s*(\d+)"
)
SUPPORTED_CONTRACT_MINOR = re.compile(
    r"const\s+supportedContractMinor\s*=\s*(\d+)"
)
GEN_MACHINE_SCHEMA = re.compile(r"_machineSchema\s*=\s*'([^']+)'")
GEN_MACHINE_VERSION = re.compile(r"_machineVersion\s*=\s*(\d+)")
GEN_CONTRACT_SCHEMA_VERSION = re.compile(r"_contractSchemaVersion\s*=\s*(\d+)")
GEN_PACKAGE_SCHEMA = re.compile(r"_packageSchema\s*=\s*'([^']+)'")
GEN_AUTHORITY_PATH = re.compile(r"_authorityPath\s*=\s*'([^']+)'")
GEN_PROVIDER_REQUIREMENTS = re.compile(
    r"_requiredProviderRequirements\s*=\s*\{(.*?)\}",
    re.DOTALL,
)


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


@dataclass(frozen=True)
class AppRequirements:
    core_contract: str
    gen_machine: tuple[str, int] | None
    gen_contract_schema_version: int | None
    gen_package_schema: str | None
    gen_authority_path: str | None
    gen_providers: frozenset[str]


def read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def contract_version_at(core: Repo, sha: str) -> str | None:
    source = core.file_at(sha, "crates/api-http/src/lib.rs")
    found = CONTRACT_CONST.search(source or "")
    return found.group(1) if found else None


def openapi_version_at(core: Repo, sha: str) -> str | None:
    source = core.file_at(sha, "contracts/openapi/v1.yaml")
    found = OPENAPI_VERSION.search(source or "")
    return found.group(1) if found else None


def content_package_schema_sha_at(core: Repo, sha: str) -> str | None:
    """Digest the canonical v3 release schema at the exact pinned Core commit.

    Gen's release manifest records the SHA-256 of Core's
    ``release.schema.json`` artifact entry.  ``contracts.lock.json`` only
    names the authority and schema generation; hashing that lock is a
    different identity and would reject a valid Gen release.
    """
    result = subprocess.run(
        [
            "git",
            "-C",
            str(core.path),
            "show",
            f"{sha}:contracts/content-package/v3/release.schema.json",
        ],
        capture_output=True,
        timeout=15,
    )
    if result.returncode != 0:
        return None
    return "sha256:" + hashlib.sha256(result.stdout).hexdigest()


def compare_contract_locks(
    app_contract: dict[str, Any], gen_contract: dict[str, Any]
) -> list[str]:
    problems: list[str] = []
    if app_contract.get("authority") != gen_contract.get("authority"):
        problems.append(
            "App listen_gen.lock.json 与钉住 Gen commit 的 contracts.lock.json 的 authority 不一致"
        )
    for field in CONTRACT_FIELDS:
        if app_contract.get(field) != gen_contract.get(field):
            problems.append(
                f"App listen_gen.lock.json 与钉住 Gen commit 的 contracts.lock.json 的 {field} 不一致"
            )
    if (
        "release_schema_id" in gen_contract
        and app_contract.get("release_schema_id")
        != gen_contract.get("release_schema_id")
    ):
        problems.append(
            "App listen_gen.lock.json 与钉住 Gen commit 的 contracts.lock.json 的 release_schema_id 不一致"
        )
    return problems


def app_requirements(app: Repo) -> AppRequirements:
    api_service = app.file_at("HEAD", "lib/services/api_service.dart") or ""
    major = SUPPORTED_CONTRACT_MAJOR.search(api_service)
    minor = SUPPORTED_CONTRACT_MINOR.search(api_service)
    core_contract = (
        f"{major.group(1)}.{minor.group(1)}.0"
        if major and minor
        else "?.?.0"
    )
    release_service = (
        app.file_at("HEAD", "lib/services/listen_gen_release_service.dart") or ""
    )
    machine_schema = GEN_MACHINE_SCHEMA.search(release_service)
    machine_version = GEN_MACHINE_VERSION.search(release_service)
    contract_schema_version = GEN_CONTRACT_SCHEMA_VERSION.search(release_service)
    package_schema = GEN_PACKAGE_SCHEMA.search(release_service)
    authority_path = GEN_AUTHORITY_PATH.search(release_service)
    providers = frozenset(
        re.findall(r"'([^']+)'\s*:", GEN_PROVIDER_REQUIREMENTS.search(release_service).group(1))
        if GEN_PROVIDER_REQUIREMENTS.search(release_service)
        else []
    )
    return AppRequirements(
        core_contract=core_contract,
        gen_machine=(
            (machine_schema.group(1), int(machine_version.group(1)))
            if machine_schema and machine_version
            else None
        ),
        gen_contract_schema_version=(
            int(contract_schema_version.group(1)) if contract_schema_version else None
        ),
        gen_package_schema=package_schema.group(1) if package_schema else None,
        gen_authority_path=authority_path.group(1) if authority_path else None,
        gen_providers=providers,
    )


def inspect(
    repos: dict[str, Repo],
) -> tuple[
    CorePin | None, GenReleasePin | None, AppRequirements, list[str], list[str]
]:
    integrity: list[str] = []
    runnable: list[str] = []
    app = repos["listen-app"]
    core = repos["listen-core"]
    gen = repos["listen-gen"]
    backend = read_json(app.path / "backend.lock.json")
    app_gen = read_json(app.path / "listen_gen.lock.json")
    requirements = app_requirements(app)

    core_pin = None
    if backend:
        core_pin = CorePin(
            str(backend.get("core_git_sha", "")),
            str(backend.get("contract", {}).get("version", "")),
            str(backend.get("runtime", {}).get("version", "")),
        )
    else:
        integrity.append("App backend.lock.json 缺失或不是有效 JSON object")

    gen_pin = None
    if app_gen:
        gen_pin = GenReleasePin(
            str(app_gen.get("source_git_sha", "")),
            str(app_gen.get("tool", {}).get("version", "")),
        )
    else:
        integrity.append("App listen_gen.lock.json 缺失或不是有效 JSON object")

    if not core.present:
        integrity.append("listen-core 本地 checkout 不存在，无法校验 Core binary pin")
    elif core_pin:
        if not core_pin.sha or core.commit_date(core_pin.sha) is None:
            integrity.append(
                f"App 钉的 Core commit {core_pin.sha[:8] or '(empty)'} 在本地解析不到"
            )
        else:
            declared = contract_version_at(core, core_pin.sha)
            openapi = openapi_version_at(core, core_pin.sha)
            if declared != core_pin.contract_version:
                integrity.append(
                    f"backend.lock.json 记着 contract {core_pin.contract_version}，"
                    f"但 Core pin 实际声明 {declared or '(missing)'}"
                )
            if declared and openapi and declared != openapi:
                integrity.append(
                    f"Core pin 自身不一致：CONTRACT_VERSION={declared}，OpenAPI={openapi}"
                )

    if not gen.present:
        integrity.append("listen-gen 本地 checkout 不存在，无法校验 Gen release pin/contract lock")
    elif gen_pin:
        if not gen_pin.sha or gen.commit_date(gen_pin.sha) is None:
            integrity.append(
                f"App 钉的 Gen commit {gen_pin.sha[:8] or '(empty)'} 在本地解析不到"
            )
        elif not gen.contains(gen_pin.sha):
            integrity.append(
                f"当前 Gen checkout 的 HEAD 不包含 App 钉的 commit {gen_pin.sha[:8]}"
            )

    if app_gen and gen_pin and gen.present:
        pinned_contract_lock = None
        pinned_lock_source = gen.file_at(gen_pin.sha, "contracts.lock.json")
        if pinned_lock_source:
            try:
                pinned_contract_lock = json.loads(pinned_lock_source)
            except json.JSONDecodeError:
                pinned_contract_lock = None
        app_contract = app_gen.get("content_package_contract")
        if pinned_contract_lock is None:
            integrity.append("钉住 Gen commit 的 contracts.lock.json 缺失或不是有效 JSON object")
        elif not isinstance(app_contract, dict):
            integrity.append("App listen_gen.lock.json 缺少 content_package_contract")
        else:
            integrity.extend(
                compare_contract_locks(app_contract, pinned_contract_lock)
            )
            if core_pin and core.present and core.commit_date(core_pin.sha) is not None:
                if app_contract.get("contract_version") != core_pin.contract_version:
                    integrity.append(
                        "App listen_gen.lock.json 的 contract_version 与 "
                        "backend.lock.json 钉住的 Core contract 不一致"
                    )
                expected_schema_digest = content_package_schema_sha_at(
                    core, core_pin.sha
                )
                if expected_schema_digest is None:
                    integrity.append(
                        "钉住 Core commit 的 Content Package v3 release schema 缺失"
                    )
                elif (
                    app_contract.get("canonical_sha256")
                    != expected_schema_digest
                ):
                    integrity.append(
                        "App listen_gen.lock.json 的 canonical_sha256 与钉住 "
                        "Core commit 的 Content Package v3 release schema 摘要不一致"
                        f"（应为 {expected_schema_digest}）"
                    )

    if core_pin:
        required = requirements.core_contract
        pinned = core_pin.contract_version
        if not _at_least(pinned, required):
            runnable.append(
                f"App 代码要求 Core contract {required}+（api_service.dart 的 "
                f"supportedContractMajor/Minor），backend.lock.json 钉的是 {pinned}"
            )

    if app_gen and requirements.gen_machine:
        machine = app_gen.get("machine_protocol")
        expected_schema, expected_version = requirements.gen_machine
        if not isinstance(machine, dict) or (
            machine.get("schema"),
            machine.get("version"),
        ) != (expected_schema, expected_version):
            runnable.append(
                f"App 代码要求 Gen machine protocol {expected_schema} v{expected_version}，"
                f"listen_gen.lock.json 钉的是 {machine or '缺失'}"
            )
        contract = app_gen.get("content_package_contract")
        if requirements.gen_contract_schema_version is not None and (
            not isinstance(contract, dict)
            or contract.get("schema_version") != requirements.gen_contract_schema_version
        ):
            runnable.append(
                f"App 代码要求 content-package schema v{requirements.gen_contract_schema_version}"
                f"（{requirements.gen_package_schema}，{requirements.gen_authority_path}），"
                f"listen_gen.lock.json 钉的是 {contract or '缺失'}"
            )
        providers = app_gen.get("runtime", {}).get("provider_requirements")
        if isinstance(providers, dict):
            missing = sorted(requirements.gen_providers - set(providers))
            if missing:
                runnable.append(
                    f"App 代码要求 Gen 提供 {', '.join(sorted(requirements.gen_providers))} "
                    f"ASR provider，listen_gen.lock.json 钉的产物缺少 {', '.join(missing)}"
                )

    return core_pin, gen_pin, requirements, integrity, runnable


def _at_least(pinned: str, required: str) -> bool:
    def parts(version: str) -> tuple[int, ...]:
        return tuple(int(part) if part.isdigit() else -1 for part in version.split("."))

    return parts(pinned) >= parts(required)


def render(
    repos: dict[str, Repo],
    core_pin: CorePin | None,
    gen_pin: GenReleasePin | None,
    requirements: AppRequirements,
    integrity: list[str],
    runnable: list[str],
    markdown: bool,
) -> str:
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
    lines += ["", "Pinned lock integrity"]
    if integrity:
        lines.extend(f"  ⚠ {problem}" for problem in integrity)
    else:
        lines.append(
            "  ✓ 两个 lock 钉的身份真实存在且内部自洽（commit 可解析、contract lock 一致）"
        )
    lines += ["", "Runnable pinned stack"]
    if runnable:
        lines.extend(f"  ⚠ {problem}" for problem in runnable)
    else:
        lines.append(
            f"  ✓ App 代码（要求 Core {requirements.core_contract}+）可运行钉住的产物"
        )
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
    core_pin, gen_pin, requirements, integrity, runnable = inspect(repos)
    print(render(repos, core_pin, gen_pin, requirements, integrity, runnable, args.markdown))
    return 1 if args.strict and (integrity or runnable) else 0


if __name__ == "__main__":
    sys.exit(main())
