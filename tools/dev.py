#!/usr/bin/env python3
"""Local development, integration, and release commands for Listen."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import posixpath
from pathlib import Path
from pathlib import PurePosixPath
import plistlib
import platform as host_platform
import re
import shutil
import shlex
import stat
import subprocess
import sys
import tarfile
import tempfile
import uuid
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


ROOT = Path(__file__).resolve().parents[1]
MIN_GEN_PYTHON = (3, 11)
GEN_EXTRAS = {"tts", "ocr", "align", "asr-qwen", "asr-sensevoice", "all"}
SNAPSHOT_IGNORED_RELATIVE = {
    Path("app/test/failures"),
    Path("app/test/fixtures/smoke/generated"),
    Path("core/third_party/runtime/build"),
    Path("core/third_party/runtime/macos-arm64"),
}
SNAPSHOT_COMMIT_MESSAGE = "Listen working source snapshot"
SNAPSHOT_AUTHOR = "Listen Dev Snapshot"
SNAPSHOT_EMAIL = "listen-dev-snapshot@invalid"
SNAPSHOT_DATE = "2000-01-01T00:00:00Z"
GENERATOR_REPOSITORY = "ichthyoplanktonzyh/listen"
GENERATOR_REPOSITORY_URL = "https://github.com/ichthyoplanktonzyh/listen"
PREVIEW_METADATA_PATH = Path("tools/dev-preview.json")


class DevError(Exception):
    """An expected setup or workflow error with an actionable message."""


def _python_executable(venv: Path) -> Path:
    return venv / "bin" / "python"


def _parse_version(output: str) -> Optional[Tuple[int, int, int]]:
    match = re.search(r"(?:Python\s+)?(\d+)\.(\d+)(?:\.(\d+))?", output)
    if not match:
        return None
    return (int(match.group(1)), int(match.group(2)), int(match.group(3) or 0))


def _version_of(executable: Path) -> Optional[Tuple[int, int, int]]:
    try:
        result = subprocess.run(
            [str(executable), "--version"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    return _parse_version(result.stdout + " " + result.stderr)


def discover_gen_python(root: Path = ROOT) -> Path:
    """Find a Python 3.11+ interpreter without assuming `python3` is new enough."""
    venv = root / "gen" / ".venv"
    if venv.is_symlink():
        raise DevError(
            "gen/.venv must be created inside this checkout, not linked to an external environment. "
            "Move the link aside and rerun ./dev setup."
        )
    existing_venv = _python_executable(venv)
    if existing_venv.is_file():
        version = _version_of(existing_venv)
        if version and version[:2] >= MIN_GEN_PYTHON:
            return existing_venv
        rendered = ".".join(map(str, version)) if version else "unknown"
        raise DevError(
            f"gen/.venv uses Python {rendered}; Gen requires Python 3.11 or newer. "
            "Preserve that environment, move it aside yourself, then rerun ./dev setup."
        )

    configured = os.environ.get("LISTEN_GEN_PYTHON")
    if configured:
        candidates = [Path(configured).expanduser()]
    else:
        candidates = []
        for name in ("python3.14", "python3.13", "python3.12", "python3.11"):
            found = shutil.which(name)
            if found:
                candidates.append(Path(found))
        found = shutil.which("python3")
        if found:
            candidates.append(Path(found))

    seen = set()
    for candidate in candidates:
        resolved = candidate.expanduser()
        if not resolved.is_absolute():
            found = shutil.which(str(resolved))
            if found:
                resolved = Path(found)
        resolved = resolved.resolve()
        if str(resolved) in seen:
            continue
        seen.add(str(resolved))
        version = _version_of(resolved)
        if version and version[:2] >= MIN_GEN_PYTHON:
            return resolved

    configured_note = (
        " The configured LISTEN_GEN_PYTHON was not usable."
        if configured
        else ""
    )
    raise DevError(
        "Listen Gen requires Python 3.11 or newer, but no suitable interpreter was found."
        + configured_note
        + " Install Python 3.11+ or set LISTEN_GEN_PYTHON to its executable."
    )


def _flutter_executable() -> str:
    configured = os.environ.get("FLUTTER")
    if configured:
        return configured
    found = shutil.which("flutter")
    if found:
        return found
    fallback = Path.home() / ".local" / "share" / "flutter" / "bin" / "flutter"
    if fallback.is_file():
        return str(fallback)
    raise DevError("Flutter was not found. Add it to PATH or set FLUTTER=/path/to/flutter.")


def _cargo_executable() -> str:
    configured = os.environ.get("CARGO")
    if configured:
        return configured
    found = shutil.which("cargo")
    if found:
        return found
    raise DevError("Cargo was not found. Install Rust or set CARGO=/path/to/cargo.")


def _print_command(command: Sequence[str], cwd: Path) -> None:
    print(f"$ (cd {shlex.quote(str(cwd))} && {shlex.join(list(command))})", flush=True)


def _run(
    command: Sequence[str],
    cwd: Path,
    env: Optional[Dict[str, str]] = None,
    *,
    quiet: bool = False,
) -> None:
    if not quiet:
        _print_command(command, cwd)
    try:
        result = subprocess.run(list(command), cwd=str(cwd), env=env, check=False)
    except FileNotFoundError as error:
        raise DevError(f"Command not found: {command[0]}") from error
    except OSError as error:
        raise DevError(f"Could not run {command[0]}: {error}") from error
    if result.returncode:
        raise DevError(
            f"Command failed with exit status {result.returncode}: "
            f"{shlex.join(list(command))}"
        )


def _working_source_paths(source_root: Path) -> List[Path]:
    result = subprocess.run(
        [
            "git",
            "-C",
            str(source_root),
            "ls-files",
            "--cached",
            "--others",
            "--exclude-standard",
            "-z",
        ],
        check=False,
        capture_output=True,
    )
    if result.returncode:
        raise DevError(
            f"Source snapshot requires a Git worktree at {source_root}."
        )
    paths = []
    for raw in result.stdout.split(b"\0"):
        if not raw:
            continue
        relative = Path(os.fsdecode(raw))
        if relative.is_absolute() or ".." in relative.parts:
            raise DevError("Git returned an unsafe source path for the snapshot.")
        if relative in SNAPSHOT_IGNORED_RELATIVE:
            continue
        paths.append(relative)
    return paths


def create_source_snapshot(source_root: Path = ROOT) -> Tuple[Path, str]:
    """Copy working source, including untracked files, into a fresh Git snapshot."""
    source_root = source_root.resolve()
    snapshot_parent = source_root / ".dev" / "snapshots"
    snapshot_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pending-", dir=str(snapshot_parent)) as staging:
        staging_root = Path(staging) / "source"
        staging_root.mkdir()
        for relative in _working_source_paths(source_root):
            source = source_root / relative
            if not os.path.lexists(str(source)):
                # A tracked deletion is represented by absence in this snapshot.
                continue
            destination = staging_root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            mode = source.lstat().st_mode
            if stat.S_ISLNK(mode):
                os.symlink(os.readlink(str(source)), str(destination))
            elif stat.S_ISREG(mode):
                shutil.copy2(str(source), str(destination))
        init = subprocess.run(
            ["git", "init", "--quiet", str(staging_root)],
            check=False,
            capture_output=True,
            text=True,
        )
        if init.returncode:
            raise DevError("Could not initialize the isolated source snapshot with Git.")
        add = subprocess.run(
            # Only files selected from Git's tracked/nonignored working set were
            # copied. Force-staging here preserves tracked files that a newer
            # ignore rule may now match without admitting local ignored inputs.
            ["git", "-C", str(staging_root), "add", "--force", "-A"],
            check=False,
            capture_output=True,
            text=True,
        )
        if add.returncode:
            raise DevError("Could not add source files to the isolated snapshot.")
        commit_env = dict(os.environ)
        commit_env.update(
            {
                "GIT_AUTHOR_NAME": SNAPSHOT_AUTHOR,
                "GIT_AUTHOR_EMAIL": SNAPSHOT_EMAIL,
                "GIT_COMMITTER_NAME": SNAPSHOT_AUTHOR,
                "GIT_COMMITTER_EMAIL": SNAPSHOT_EMAIL,
                "GIT_AUTHOR_DATE": SNAPSHOT_DATE,
                "GIT_COMMITTER_DATE": SNAPSHOT_DATE,
            }
        )
        commit = subprocess.run(
            [
                "git",
                "-C",
                str(staging_root),
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "--allow-empty",
                "-m",
                SNAPSHOT_COMMIT_MESSAGE,
            ],
            env=commit_env,
            check=False,
            capture_output=True,
            text=True,
        )
        if commit.returncode:
            detail = (commit.stderr or commit.stdout).strip()
            raise DevError("Could not record the isolated source snapshot." + (f" {detail}" if detail else ""))
        rev = subprocess.run(
            ["git", "-C", str(staging_root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        # Every operation gets its own fresh copy, so ignored files injected
        # into an older developer snapshot can never enter a new build.
        destination = snapshot_parent / f"{rev}-{uuid.uuid4().hex}"
        staging_root.rename(destination)
        return destination, rev


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def write_gen_lock(manifest_path: Path, lock_path: Path, *, debug_only: bool) -> Path:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        artifact = manifest["artifact"]
        tool = manifest["tool"]
        source = manifest["source"]
        artifact_path = manifest_path.parent / artifact["filename"]
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise DevError(f"Could not read Gen release manifest {manifest_path}: {error}") from error
    if not artifact_path.is_file():
        raise DevError(f"Gen release artifact is missing: {artifact_path}")
    if artifact.get("size_bytes") != artifact_path.stat().st_size:
        raise DevError("Gen release artifact size does not match its manifest.")
    if artifact.get("sha256") != _sha256(artifact_path):
        raise DevError("Gen release artifact checksum does not match its manifest.")
    source_commit = source.get("commit")
    if not isinstance(source_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        raise DevError("Gen release manifest has no valid source commit identity.")
    if source.get("repository") != GENERATOR_REPOSITORY_URL:
        raise DevError("Gen release manifest does not identify the Listen monorepo.")
    artifact_filename = artifact.get("filename")
    if (
        not isinstance(artifact_filename, str)
        or Path(artifact_filename).name != artifact_filename
        or artifact_filename in {".", ".."}
        or manifest.get("schema") != "listen_gen.release-bundle.v1"
    ):
        raise DevError("Gen release manifest has an invalid artifact identity.")
    if debug_only != (".debug." in lock_path.name):
        raise DevError("Debug Gen locks must use a `.debug.` filename in ignored dev output.")
    required_sections = (
        "machine_protocol",
        "content_package_contract",
        "runtime",
        "runtime_identity",
    )
    if any(not isinstance(manifest.get(section), dict) for section in required_sections):
        raise DevError("Gen release manifest is missing fields required by the App lock.")
    runtime = manifest["runtime"]
    if "python_requires" not in runtime:
        raise DevError("Gen release manifest has no Python runtime requirement.")
    expected_artifact_keys = {
        "filename",
        "format",
        "entrypoint",
        "size_bytes",
        "sha256",
    }
    if set(artifact) != expected_artifact_keys:
        raise DevError("Gen release manifest artifact does not match the App lock contract.")
    lock = {
        "manifest_version": 1,
        "repository": GENERATOR_REPOSITORY,
        "source_git_sha": source_commit,
        "release_manifest": {
            "schema": manifest["schema"],
            "filename": manifest_path.name,
            "sha256": _sha256(manifest_path),
        },
        "tool": {"id": tool["id"], "version": tool["version"]},
        "machine_protocol": manifest["machine_protocol"],
        "content_package_contract": manifest["content_package_contract"],
        "runtime": {"python_requires": runtime["python_requires"]},
        "runtime_identity": manifest["runtime_identity"],
        "artifact": artifact,
    }
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = lock_path.with_suffix(lock_path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(lock, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    os.replace(str(temporary), str(lock_path))
    return lock_path


def _gen_bundle_paths(output_dir: Path, gen_root: Path) -> Tuple[Path, Path]:
    try:
        project = (gen_root / "pyproject.toml").read_text(encoding="utf-8")
        match = re.search(r"(?ms)^\[project\].*?^version\s*=\s*['\"]([^'\"]+)['\"]", project)
    except OSError as error:
        raise DevError(f"Could not read Gen project metadata: {error}") from error
    if not match:
        raise DevError("Gen project version is missing from pyproject.toml.")
    bundle_dir = output_dir / f"listen-gen-{match.group(1)}"
    return bundle_dir / f"listen-gen-{match.group(1)}.pyz", bundle_dir / f"listen-gen-{match.group(1)}.release.json"


def _build_contract_artifact(snapshot: Path, output_dir: Path, source_sha: str) -> Path:
    contract_dir = output_dir / "contracts"
    package_script = snapshot / "core" / "scripts" / "package-contracts.sh"
    _run(
        [str(package_script), "--output-dir", str(contract_dir), "--git-sha", source_sha],
        snapshot / "core",
    )
    manifests = list(contract_dir.glob("listen-contracts-*.manifest.json"))
    if len(manifests) != 1:
        raise DevError(f"Expected one Core contract manifest in {contract_dir}.")
    return manifests[0]


def _build_gen_bundle(
    snapshot: Path,
    output_dir: Path,
    source_sha: str,
    core_contract_manifest: Path,
    python: Path,
) -> Path:
    gen_root = snapshot / "gen"
    bundle, manifest = _gen_bundle_paths(output_dir, gen_root)
    if manifest.is_file() and bundle.is_file():
        try:
            existing = json.loads(manifest.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            raise DevError(f"Could not read cached Gen release manifest: {error}") from error
        existing_source = existing.get("source") if isinstance(existing, dict) else None
        if not isinstance(existing_source, dict) or existing_source.get("commit") != source_sha:
            raise DevError("Cached Gen release bundle has a different source identity.")
        _run(
            [
                str(python),
                "tools/release_bundle.py",
                "verify",
                str(manifest),
                "--core-contract-manifest",
                str(core_contract_manifest),
            ],
            gen_root,
        )
        return manifest
    _run(
        [
            str(python),
            "tools/release_bundle.py",
            "build",
            "--source-commit",
            source_sha,
            "--core-contract-manifest",
            str(core_contract_manifest),
            "--output-parent",
            str(output_dir),
        ],
        gen_root,
    )
    if not manifest.is_file():
        raise DevError("Gen release bundle build completed without a manifest.")
    return manifest


def _prepare_debug_gen_lock(
    root: Path,
    python: Path,
) -> Tuple[Path, str, Path, Path]:
    snapshot, source_sha = create_source_snapshot(root)
    artifacts = root / ".dev" / "artifacts" / source_sha
    contract_manifest = _build_contract_artifact(snapshot, artifacts, source_sha)
    gen_manifest = _build_gen_bundle(
        snapshot,
        artifacts / "gen",
        source_sha,
        contract_manifest,
        python,
    )
    gen_lock = write_gen_lock(
        gen_manifest,
        artifacts / "listen_gen.debug.lock.json",
        debug_only=True,
    )
    return snapshot, source_sha, gen_manifest, gen_lock


def _install_setup(root: Path = ROOT, extras: Iterable[str] = ()) -> Path:
    gen_root = root / "gen"
    venv = gen_root / ".venv"
    python = discover_gen_python(root)
    if not _python_executable(venv).is_file():
        print(f"Creating Gen virtual environment with {python}.", flush=True)
        _run([str(python), "-m", "venv", str(venv)], root)
    venv_python = _python_executable(venv)
    version = _version_of(venv_python)
    if not version or version[:2] < MIN_GEN_PYTHON:
        raise DevError("Created Gen environment does not use Python 3.11 or newer.")
    extra_set = sorted(set(extras))
    invalid = set(extra_set) - GEN_EXTRAS
    if invalid:
        raise DevError("Unknown Gen extras: " + ", ".join(sorted(invalid)))
    requirement = str(gen_root)
    if extra_set:
        requirement += "[" + ",".join(extra_set) + "]"
    _run(
        [
            str(venv_python),
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "-e",
            requirement,
            "-r",
            str(root / "tools" / "requirements-dev.txt"),
        ],
        root,
    )
    _run([_flutter_executable(), "pub", "get"], root / "app")
    return venv_python


def _require_setup(root: Path = ROOT) -> Path:
    venv = root / "gen" / ".venv"
    if venv.is_symlink():
        raise DevError(
            "gen/.venv must live inside this checkout. Move the external link aside and run `./dev setup`."
        )
    venv_python = _python_executable(venv)
    version = _version_of(venv_python) if venv_python.is_file() else None
    if not version or version[:2] < MIN_GEN_PYTHON:
        raise DevError(
            "Gen's Python 3.11+ environment is missing. Run `./dev setup` once first."
        )
    probe = subprocess.run(
        [str(venv_python), "-c", "import listen_gen, pypdf, jieba"],
        cwd=str(root / "gen"),
        check=False,
        capture_output=True,
        text=True,
    )
    if probe.returncode:
        raise DevError(
            "Gen/Core development dependencies are not installed. Run `./dev setup` once first."
        )
    if not (root / "app" / ".dart_tool" / "package_config.json").is_file():
        raise DevError(
            "Flutter packages are not prepared. Run `./dev setup` once first."
        )
    return venv_python


def command_setup(args: argparse.Namespace) -> None:
    extras = []
    for entry in args.extras:
        extras.extend(item.strip() for item in entry.split(",") if item.strip())
    python = _install_setup(ROOT, extras)
    version = _version_of(python)
    print(
        f"Setup complete. Gen uses Python {'.'.join(map(str, version or (0, 0, 0)))} at {python}. "
        "Heavy model extras are installed only when named with --extras."
    )


def command_run(args: argparse.Namespace) -> None:
    python = _require_setup(ROOT)
    snapshot, source_sha = create_source_snapshot(ROOT)
    artifacts = ROOT / ".dev" / "artifacts" / source_sha
    artifacts.mkdir(parents=True, exist_ok=True)
    target_dir = ROOT / ".dev" / "cargo-target"
    target_dir.mkdir(parents=True, exist_ok=True)

    cargo = _cargo_executable()
    env = dict(os.environ)
    env["CARGO_TARGET_DIR"] = str(target_dir)
    _run([cargo, "build", "--locked", "-p", "api-http"], snapshot / "core", env)

    contract_manifest = _build_contract_artifact(snapshot, artifacts, source_sha)
    gen_manifest = _build_gen_bundle(snapshot, artifacts / "gen", source_sha, contract_manifest, python)
    lock_path = write_gen_lock(
        gen_manifest,
        artifacts / "listen_gen.debug.lock.json",
        debug_only=True,
    )
    api_binary = target_dir / "debug" / "api-http"
    if not api_binary.is_file():
        raise DevError(f"Core build did not produce {api_binary}.")

    run_env = dict(os.environ)
    run_env.update(
        {
            "LLPLAYERNEXT_API_BINARY": str(api_binary),
            "LISTEN_GEN_RELEASE_MANIFEST": str(gen_manifest),
            "LISTEN_GEN_LOCK_PATH": str(lock_path),
            "LISTEN_SOURCE_ROOT": str(ROOT),
        }
    )
    try:
        runtime = _runtime_dir(ROOT)
    except DevError:
        if os.environ.get("LISTEN_CORE_RUNTIME_DIR"):
            raise
        runtime = None
    if runtime is not None:
        run_env["LISTEN_CORE_RUNTIME_DIR"] = str(runtime)
        run_env["LLPLAYERNEXT_WHISPER_CLI"] = str(runtime / "whisper-cli")
        run_env["LLPLAYERNEXT_FFPROBE"] = str(runtime / "ffprobe")
        run_env["LLPLAYERNEXT_FFMPEG"] = str(runtime / "ffmpeg")
    command = [_flutter_executable(), "run", "-d", args.device]
    command.extend(args.flutter_args)
    print(f"Running source snapshot {source_sha[:12]} from working app source.", flush=True)
    _run(command, ROOT / "app", run_env)


def _run_app_tests(root: Path, flutter: str, python: Path) -> None:
    app = root / "app"
    _run([flutter, "analyze", "--fatal-infos", "--fatal-warnings"], app)
    _run([flutter, "test"], app)
    _run(
        [str(python), "-m", "unittest", "discover", "-s", "tool", "-p", "test_*.py"],
        app,
    )


def _run_core_tests(root: Path) -> None:
    core = root / "core"
    env = dict(os.environ)
    env["CARGO_TARGET_DIR"] = str(root / ".dev" / "cargo-target")
    env["PATH"] = str(_python_executable(root / "gen" / ".venv").parent) + os.pathsep + env.get("PATH", "")
    _run([str(core / "scripts" / "test.sh"), "--rust", "--strict"], core, env)
    _run([str(core / "scripts" / "validate-contracts.sh")], core, env)


def _build_gen_inspector(root: Path) -> Dict[str, str]:
    env = dict(os.environ)
    env["CARGO_TARGET_DIR"] = str(root / ".dev" / "cargo-target")
    env["LISTEN_CORE_CHECKOUT"] = str(root / "core")
    _run(
        [
            _cargo_executable(),
            "build",
            "--locked",
            "--manifest-path",
            str(root / "core" / "Cargo.toml"),
            "-p",
            "content-package",
            "--example",
            "inspect-package",
        ],
        root / "core",
        env,
    )
    return env


def _run_gen_tests(root: Path, python: Path) -> None:
    env = dict(os.environ)
    env["CARGO_TARGET_DIR"] = str(root / ".dev" / "cargo-target")
    env["LISTEN_CORE_CHECKOUT"] = str(root / "core")
    _run(
        [str(python), "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py"],
        root / "gen",
        env,
    )


def command_check(args: argparse.Namespace) -> None:
    python = _require_setup(ROOT)
    flutter = _flutter_executable()
    _run_root_tool_tests(ROOT)
    _, source_sha, gen_manifest, gen_lock = _prepare_debug_gen_lock(ROOT, python)
    _run_gen_lock_flutter_probe(ROOT, flutter, gen_manifest, gen_lock)
    _run_app_tests(ROOT, flutter, python)
    _run_core_tests(ROOT)
    _build_gen_inspector(ROOT)
    _run_gen_tests(ROOT, python)


def command_test(args: argparse.Namespace) -> None:
    if args.suite == "integration":
        python = _require_setup(ROOT)
        snapshot, source_sha = create_source_snapshot(ROOT)
        script = snapshot / "app" / "tool" / "verify_local_content_package_roundtrip.sh"
        env = dict(os.environ)
        env["PATH"] = str(python.parent) + os.pathsep + env.get("PATH", "")
        env["CARGO_TARGET_DIR"] = str(ROOT / ".dev" / "cargo-target")
        env["LISTEN_CORE_CHECKOUT"] = str(snapshot / "core")
        env["LISTEN_GEN_PYTHON"] = str(python)
        _run(["bash", str(script), "--source-root", str(snapshot)], snapshot / "app", env)
        print(f"Model-free integration roundtrip passed for source snapshot {source_sha[:12]}.")
        return
    python = _require_setup(ROOT)
    flutter = _flutter_executable()
    _run_root_tool_tests(ROOT)
    _, _, gen_manifest, gen_lock = _prepare_debug_gen_lock(ROOT, python)
    _run_gen_lock_flutter_probe(ROOT, flutter, gen_manifest, gen_lock)
    _run([flutter, "test"], ROOT / "app")
    _run(
        [str(python), "-m", "unittest", "discover", "-s", "tool", "-p", "test_*.py"],
        ROOT / "app",
    )
    _run_core_tests(ROOT)
    _build_gen_inspector(ROOT)
    _run_gen_tests(ROOT, python)


def _git(root: Path, *arguments: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *arguments],
        check=False,
        capture_output=True,
        text=True,
    )
    if check and result.returncode:
        raise DevError(f"Git command failed: git {' '.join(arguments)}")
    return result.stdout.strip()


def _assert_clean_head(root: Path, expected_head: str, stage: str) -> None:
    current_head = _git(root, "rev-parse", "HEAD")
    status = _git(root, "status", "--porcelain", "--untracked-files=all")
    if current_head != expected_head or status:
        detail = (
            f"HEAD changed from {expected_head} to {current_head}."
            if current_head != expected_head
            else ""
        )
        if status:
            detail += ("\n" if detail else "") + status
        raise DevError(
            f"Release source changed {stage}; refusing a mixed-source release.\n{detail}"
        )


def _run_root_tool_tests(root: Path) -> None:
    _run(
        [sys.executable, "-m", "unittest", "discover", "-s", "tools", "-p", "test_*.py"],
        root,
    )


def _run_gen_lock_flutter_probe(
    root: Path,
    flutter: str,
    manifest: Path,
    lock: Path,
) -> None:
    env = dict(os.environ)
    env["LISTEN_GEN_LOCK_PATH"] = str(lock)
    env["LISTEN_GEN_RELEASE_MANIFEST"] = str(manifest)
    _run(
        [
            flutter,
            "test",
            "test/listen_gen_release_service_test.dart",
            "--plain-name",
            "verifies the generated development lock and manifest from the environment",
        ],
        root / "app",
        env,
    )


def _runtime_dir(root: Path) -> Path:
    configured = os.environ.get("LISTEN_CORE_RUNTIME_DIR")
    candidates = (
        [Path(configured).expanduser()]
        if configured
        else [root / "core" / "third_party" / "runtime" / "macos-arm64"]
    )
    for candidate in candidates:
        candidate = candidate.resolve()
        if (candidate / "runtime").is_dir() and not (candidate / "ffmpeg").is_file():
            candidate = candidate / "runtime"
        if all((candidate / binary).is_file() for binary in ("whisper-cli", "ffmpeg", "ffprobe")):
            return candidate
    if configured:
        raise DevError(
            f"LISTEN_CORE_RUNTIME_DIR does not contain whisper-cli, ffmpeg, and ffprobe: {configured}"
        )
    raise DevError(
        "Core release runtime inputs were not found. Set LISTEN_CORE_RUNTIME_DIR to the "
        "existing macOS arm64 runtime directory; release will not download or build third-party binaries."
    )


def _release_lock_paths(output: Path) -> Tuple[Path, Path]:
    lock_dir = output / "locks"
    lock_dir.mkdir(parents=True, exist_ok=True)
    return lock_dir / "backend.lock.json", lock_dir / "listen_gen.lock.json"


def _load_preview_metadata(root: Path) -> Dict[str, str]:
    metadata_path = root / PREVIEW_METADATA_PATH
    try:
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise DevError(f"Could not read preview release metadata {metadata_path}: {error}") from error
    if not isinstance(metadata, dict):
        raise DevError(f"{metadata_path} must contain a JSON object.")
    version = metadata.get("version")
    match = re.fullmatch(r"(?P<bundle>\d+\.\d+\.\d+)-dev\.(?P<iteration>[1-9]\d*)", str(version))
    if (
        metadata.get("schema_version") != 1
        or metadata.get("channel") != "development-preview"
        or metadata.get("platform") != "macos-arm64"
        or not match
        or metadata.get("tag") != f"v{version}"
    ):
        raise DevError(
            f"{metadata_path} must describe a development preview with a numeric app version and v-prefixed tag."
        )
    minimum_macos = metadata.get("minimum_macos")
    if not isinstance(minimum_macos, str) or not re.fullmatch(r"\d+\.\d+", minimum_macos):
        raise DevError(f"{metadata_path} has an invalid minimum_macos value.")
    pubspec_path = root / "app" / "pubspec.yaml"
    try:
        pubspec = pubspec_path.read_text(encoding="utf-8")
    except OSError as error:
        raise DevError(f"Could not read {pubspec_path}: {error}") from error
    pubspec_match = re.search(r"(?m)^version:\s*([^\s#]+)", pubspec)
    if not pubspec_match:
        raise DevError(f"Could not resolve the application version from {pubspec_path}.")
    version_match = re.fullmatch(r"(?P<bundle>\d+\.\d+\.\d+)\+(?P<build>\d+)", pubspec_match.group(1))
    if not version_match or version_match.group("bundle") != match.group("bundle"):
        raise DevError(
            f"{pubspec_path} must use numeric bundle version {match.group('bundle')}+BUILD for preview {version}."
        )
    metadata["bundle_version"] = version_match.group("bundle")
    metadata["build_number"] = version_match.group("build")
    metadata["archive_name"] = f"Listen-{metadata['tag']}-{metadata['platform']}.zip"
    metadata["manifest_name"] = metadata["archive_name"].removesuffix(".zip") + ".release.json"
    return metadata


def _write_backend_lock(
    contract_manifest: Path,
    contract_archive: Path,
    runtime_manifest: Path,
    runtime_archive: Path,
    output_path: Path,
    source_sha: str,
) -> Path:
    try:
        contract = json.loads(contract_manifest.read_text(encoding="utf-8"))
        runtime = json.loads(runtime_manifest.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise DevError(f"Could not read Core artifact manifests: {error}") from error
    if contract.get("core_git_sha") != source_sha or runtime.get("core_git_sha") != source_sha:
        raise DevError("Core release artifacts do not share the requested source identity.")
    lock = {
        "manifest_version": 1,
        "core_repository": "ichthyoplanktonzyh/listen",
        "core_git_sha": source_sha,
        "contract": {
            "version": contract["contract_version"],
            "sha256": hashlib.sha256(contract_archive.read_bytes()).hexdigest(),
        },
        "runtime": {
            "version": runtime["runtime_version"],
            "platform": runtime["platform"],
            "arch": runtime["arch"],
            "sha256": hashlib.sha256(runtime_archive.read_bytes()).hexdigest(),
        },
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(lock, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return output_path


def _ensure_external_output(root: Path, requested: Optional[str], source_sha: str) -> Path:
    if requested:
        output = Path(requested).expanduser().resolve()
    else:
        output = root.parent / f"listen-release-{source_sha[:12]}"
    try:
        output.relative_to(root.resolve())
    except ValueError:
        pass
    else:
        raise DevError("Release output must be outside the source directory.")
    if output.exists() and any(output.iterdir()):
        raise DevError(f"Release output directory is not empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    return output


def _parse_macos_minimums(load_commands: str) -> List[Tuple[int, int]]:
    """Read macOS minimums from the arm64 slice's otool -l output."""
    command = None
    platform_id = None
    minimums: List[Tuple[int, int]] = []
    for line in load_commands.splitlines():
        stripped = line.strip()
        if stripped.startswith("cmd "):
            command = stripped[4:]
            platform_id = None
            continue
        if command == "LC_BUILD_VERSION":
            platform_match = re.fullmatch(r"platform\s+(\d+)", stripped)
            if platform_match:
                platform_id = platform_match.group(1)
            minimum_match = re.fullmatch(r"minos\s+(\d+)\.(\d+)(?:\.\d+)?(?:\s+.*)?", stripped)
            if minimum_match and platform_id == "1":
                minimums.append((int(minimum_match.group(1)), int(minimum_match.group(2))))
        elif command == "LC_VERSION_MIN_MACOSX":
            version_match = re.fullmatch(r"version\s+(\d+)\.(\d+)(?:\.\d+)?", stripped)
            if version_match:
                minimums.append((int(version_match.group(1)), int(version_match.group(2))))
    return minimums


def _format_macos_version(version: Tuple[int, int]) -> str:
    return f"{version[0]}.{version[1]}"


def _validate_macos_arm64_target(
    host_architecture: str,
    macho_architectures: Dict[str, List[str]],
    required_binaries: Iterable[str],
) -> None:
    if host_architecture not in ("arm64", "aarch64"):
        raise DevError(
            f"The macOS arm64 release must be built and smoke-tested on Apple Silicon, not {host_architecture}."
        )
    missing = sorted(set(required_binaries) - set(macho_architectures))
    if missing:
        raise DevError("The macOS arm64 bundle is missing required Mach-O executables: " + ", ".join(missing))
    unsupported = sorted(
        name for name, architectures in macho_architectures.items() if "arm64" not in architectures
    )
    if unsupported:
        raise DevError(
            "Every Mach-O in this macOS arm64 bundle must include an arm64 slice; unsupported: "
            + ", ".join(unsupported)
        )


def _macos_bundle_facts(app: Path, metadata: Dict[str, str]) -> Dict[str, object]:
    if sys.platform != "darwin":
        raise DevError("The macOS release bundle audit requires macOS tooling (file, lipo, otool).")
    host_architecture = host_platform.machine()
    if host_architecture not in ("arm64", "aarch64"):
        raise DevError(
            f"The macOS arm64 release must be built and smoke-tested on Apple Silicon, not {host_architecture}."
        )
    info_path = app / "Contents" / "Info.plist"
    try:
        info = plistlib.loads(info_path.read_bytes())
    except (OSError, ValueError) as error:
        raise DevError(f"Could not read the built App metadata at {info_path}: {error}") from error
    expected_info = {
        "CFBundleIdentifier": "com.shadow.listen.desktop",
        "CFBundleShortVersionString": metadata["bundle_version"],
        "CFBundleVersion": metadata["build_number"],
        "ListenReleaseVersion": metadata["version"],
        "ListenReleaseChannel": metadata["channel"],
        "ListenSourceCommit": metadata["source_commit"],
        "LSMinimumSystemVersion": metadata["minimum_macos"],
    }
    for key, expected in expected_info.items():
        if str(info.get(key, "")) != expected:
            raise DevError(
                f"Built App Info.plist has {key}={info.get(key)!r}; expected {expected!r}."
            )

    minimums = []
    arm64_macho_count = 0
    macho_count = 0
    macho_architectures: Dict[str, List[str]] = {}
    for path in app.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        file_result = subprocess.run(
            ["file", "-b", str(path)], check=False, capture_output=True, text=True
        )
        if file_result.returncode:
            raise DevError(f"Could not inspect packaged file {path}.")
        if "Mach-O" not in file_result.stdout:
            continue
        macho_count += 1
        architectures = subprocess.run(
            ["lipo", "-archs", str(path)], check=False, capture_output=True, text=True
        )
        if architectures.returncode:
            raise DevError(f"Could not inspect Mach-O architectures in {path}.")
        architecture_list = architectures.stdout.split()
        macho_architectures[path.relative_to(app).as_posix()] = architecture_list
        if "arm64" not in architecture_list:
            continue
        arm64_macho_count += 1
        load_commands = subprocess.run(
            ["otool", "-arch", "arm64", "-l", str(path)],
            check=False,
            capture_output=True,
            text=True,
        )
        if load_commands.returncode:
            raise DevError(f"Could not inspect arm64 deployment target in {path}.")
        file_minimums = _parse_macos_minimums(load_commands.stdout)
        if not file_minimums:
            raise DevError(f"No macOS deployment target was found in arm64 Mach-O {path}.")
        minimums.extend(file_minimums)

    _validate_macos_arm64_target(
        host_architecture,
        macho_architectures,
        (
            "Contents/MacOS/listen",
            "Contents/MacOS/api-http",
            "Contents/Resources/runtime/whisper-cli",
            "Contents/Resources/runtime/ffmpeg",
            "Contents/Resources/runtime/ffprobe",
        ),
    )
    if not arm64_macho_count or not minimums:
        raise DevError(f"No arm64 macOS binaries were found in {app}.")
    effective_minimum = max(minimums)
    declared_minimum = tuple(int(part) for part in metadata["minimum_macos"].split("."))
    if effective_minimum != declared_minimum:
        raise DevError(
            "The release minimum macOS version does not match the bundled arm64 Mach-O inputs: "
            f"Info.plist says {metadata['minimum_macos']}, but the bundle requires "
            f"{_format_macos_version(effective_minimum)}. Update tools/dev-preview.json only after reviewing the new runtime requirements."
        )
    model_names = [
        path.name
        for path in app.rglob("*")
        if path.is_file() and re.fullmatch(r"ggml-.*\.(?:bin|gguf)", path.name, re.IGNORECASE)
    ]
    if model_names:
        raise DevError("A Whisper model was unexpectedly included in the app bundle: " + ", ".join(model_names))
    host_version = subprocess.run(
        ["sw_vers", "-productVersion"], check=False, capture_output=True, text=True
    )
    if host_version.returncode or not host_version.stdout.strip():
        raise DevError("Could not determine the macOS version used for packaged release verification.")
    return {
        "bundle_id": info["CFBundleIdentifier"],
        "bundle_version": info["CFBundleShortVersionString"],
        "build_number": info["CFBundleVersion"],
        "minimum_macos": _format_macos_version(effective_minimum),
        "mach_o_files": macho_count,
        "arm64_mach_o_files": arm64_macho_count,
        "tested_macos": host_version.stdout.strip(),
        "tested_architecture": host_architecture,
    }


def _assemble_preview_distribution(
    output: Path,
    archive: Path,
    source_sha: str,
    metadata: Dict[str, str],
    bundle_facts: Dict[str, object],
) -> Path:
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha):
        raise DevError("The preview source identity must be a full lowercase Git SHA.")
    if not archive.is_file():
        raise DevError(f"The verified app archive is missing: {archive}")
    distribution = output / "distribution"
    distribution.mkdir(parents=True, exist_ok=True)
    asset = distribution / metadata["archive_name"]
    release_manifest = distribution / metadata["manifest_name"]
    if any(distribution.iterdir()):
        raise DevError(f"Preview distribution assets already exist: {distribution}")
    shutil.copy2(str(archive), str(asset))
    artifact_sha = hashlib.sha256(asset.read_bytes()).hexdigest()
    release = {
        "schema_version": 1,
        "release": {
            "product": "Listen",
            "channel": metadata["channel"],
            "version": metadata["version"],
            "tag": metadata["tag"],
            "prerelease": True,
        },
        "source": {
            "repository": GENERATOR_REPOSITORY_URL,
            "commit": source_sha,
        },
        "application": {
            "bundle_id": bundle_facts["bundle_id"],
            "bundle_version": bundle_facts["bundle_version"],
            "build_number": bundle_facts["build_number"],
            "platform": metadata["platform"],
            "minimum_macos": bundle_facts["minimum_macos"],
        },
        "verification": {
            "packaged_smoke": "passed",
            "tested_macos": bundle_facts["tested_macos"],
            "tested_architecture": bundle_facts["tested_architecture"],
            "mach_o_files": bundle_facts["mach_o_files"],
            "arm64_mach_o_files": bundle_facts["arm64_mach_o_files"],
            "launch_environment": {
                "home": "isolated temporary directory",
                "path": "/usr/bin:/bin:/usr/sbin:/sbin",
                "source_checkout_available_to_app": False,
            },
        },
        "signing": {
            "type": "ad-hoc",
            "developer_id_signed": False,
            "notarized": False,
        },
        "whisper_model": {
            "bundled": False,
            "id": "whisper.cpp:base@main",
            "display_name": "base",
            "size_bytes": 147951465,
            "source_url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
            "sha256": "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            "download_requires_explicit_user_confirmation": True,
            "download_trigger": "starting a realtime conversation when no compatible model is installed",
        },
        "gen_runtime": {
            "zipapp_bundled": True,
            "interpreter_bundled": False,
            "python_requires": ">=3.11",
            "required_dependencies": ["pypdf>=5.0,<7"],
            "optional_extras": ["tts", "ocr", "align", "asr-qwen", "asr-sensevoice"],
        },
        "artifact": {
            "filename": asset.name,
            "size_bytes": asset.stat().st_size,
            "sha256": artifact_sha,
        },
    }
    release_manifest.write_text(
        json.dumps(release, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    checksum_lines = []
    for path in (asset, release_manifest):
        checksum = hashlib.sha256(path.read_bytes()).hexdigest()
        checksum_lines.append(f"{checksum}  {path.name}")
    (distribution / "SHA256SUMS").write_text("\n".join(checksum_lines) + "\n", encoding="ascii")
    return distribution


def _extract_git_archive(archive_path: Path, destination: Path) -> set:
    destination.mkdir(parents=True, exist_ok=True)
    symlinks = set()
    present = set()
    try:
        archive = tarfile.open(str(archive_path), mode="r:")
    except (OSError, tarfile.TarError) as error:
        raise DevError(f"Could not read committed source archive: {error}") from error
    with archive:
        for member in archive.getmembers():
            relative = PurePosixPath(member.name)
            if relative.is_absolute() or ".." in relative.parts or not relative.parts:
                raise DevError(f"Refusing unsafe committed source path: {member.name}")
            target = destination.joinpath(*relative.parts)
            for parent in target.parents:
                if parent == destination:
                    break
                if parent in symlinks or parent.is_symlink():
                    raise DevError(f"Refusing a file nested under a source symlink: {member.name}")
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if member.issym():
                link = member.linkname
                if posixpath.isabs(link):
                    raise DevError(f"Refusing an absolute source symlink: {member.name}")
                normalized = posixpath.normpath(posixpath.join(str(relative.parent), link))
                if normalized == ".." or normalized.startswith("../"):
                    raise DevError(f"Refusing a source symlink outside the repository: {member.name}")
                os.symlink(link, str(target))
                symlinks.add(target)
                present.add(relative.as_posix())
                continue
            if not member.isfile():
                raise DevError(f"Unsupported committed source entry: {member.name}")
            stream = archive.extractfile(member)
            if stream is None:
                raise DevError(f"Could not read committed source file: {member.name}")
            with stream, target.open("wb") as output:
                shutil.copyfileobj(stream, output)
            target.chmod(member.mode & 0o777)
            present.add(relative.as_posix())
    return present


def _create_committed_source_export(root: Path, source_sha: str) -> Tuple[Path, str]:
    export_parent = root / ".dev" / "release-sources"
    export_parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="pending-", dir=str(export_parent)) as staging:
        staging_root = Path(staging) / "source"
        archive_path = Path(staging) / "source.tar"
        with archive_path.open("wb") as archive_stream:
            result = subprocess.run(
                ["git", "-C", str(root), "archive", "--format=tar", source_sha],
                stdout=archive_stream,
                stderr=subprocess.PIPE,
                check=False,
                text=False,
            )
        if result.returncode:
            raise DevError("Could not export the committed source tree with git archive.")
        actual_paths = _extract_git_archive(archive_path, staging_root)
        expected_result = subprocess.run(
            ["git", "-C", str(root), "ls-tree", "-r", "--name-only", "-z", source_sha],
            check=False,
            capture_output=True,
        )
        if expected_result.returncode:
            raise DevError("Could not enumerate the committed release source tree.")
        expected_paths = {
            os.fsdecode(path)
            for path in expected_result.stdout.split(b"\0")
            if path
        }
        if actual_paths != expected_paths:
            raise DevError("The release source archive does not contain the full committed tree.")
        init = subprocess.run(
            ["git", "init", "--quiet", str(staging_root)],
            check=False,
            capture_output=True,
            text=True,
        )
        if init.returncode:
            raise DevError("Could not initialize the isolated release source tree.")
        add = subprocess.run(
            ["git", "-C", str(staging_root), "add", "--force", "-A"],
            check=False,
            capture_output=True,
            text=True,
        )
        if add.returncode:
            raise DevError("Could not index the isolated release source tree.")
        commit_env = dict(os.environ)
        commit_env.update(
            {
                "GIT_AUTHOR_NAME": SNAPSHOT_AUTHOR,
                "GIT_AUTHOR_EMAIL": SNAPSHOT_EMAIL,
                "GIT_COMMITTER_NAME": SNAPSHOT_AUTHOR,
                "GIT_COMMITTER_EMAIL": SNAPSHOT_EMAIL,
                "GIT_AUTHOR_DATE": SNAPSHOT_DATE,
                "GIT_COMMITTER_DATE": SNAPSHOT_DATE,
            }
        )
        commit = subprocess.run(
            [
                "git",
                "-C",
                str(staging_root),
                "-c",
                "commit.gpgsign=false",
                "commit",
                "--quiet",
                "--allow-empty",
                "-m",
                "Listen committed release source export",
            ],
            env=commit_env,
            check=False,
            capture_output=True,
            text=True,
        )
        if commit.returncode:
            raise DevError("Could not record the isolated release source tree.")
        export_git_sha = subprocess.run(
            ["git", "-C", str(staging_root), "rev-parse", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()
        source_tree = _git(root, "rev-parse", f"{source_sha}^{{tree}}")
        export_tree = _git(staging_root, "rev-parse", "HEAD^{tree}")
        if source_tree != export_tree:
            raise DevError("The release export tree differs from the committed source tree.")
        destination = export_parent / f"{source_sha}-{uuid.uuid4().hex}"
        staging_root.rename(destination)
        return destination, export_git_sha


def command_release(args: argparse.Namespace) -> None:
    python = _require_setup(ROOT)
    source_sha = _git(ROOT, "rev-parse", "HEAD")
    _assert_clean_head(ROOT, source_sha, "before release export")
    metadata = _load_preview_metadata(ROOT)
    output = _ensure_external_output(ROOT, args.output_dir, source_sha)
    runtime = _runtime_dir(ROOT)
    export_root, export_git_sha = _create_committed_source_export(ROOT, source_sha)
    try:
        _release_from_export(
            export_root,
            export_git_sha,
            source_sha,
            output,
            runtime,
            python,
            metadata,
        )
    finally:
        shutil.rmtree(export_root, ignore_errors=True)
    _assert_clean_head(ROOT, source_sha, "after release verification")
    print(f"Development preview verified: {output / 'distribution'}")


def _app_release_environment(
    base_environment: Dict[str, str],
    *,
    flutter: str,
    backend_lock: Path,
    gen_lock: Path,
    gen_manifest: Path,
    output: Path,
    metadata: Dict[str, str],
    source_commit: str,
) -> Dict[str, str]:
    environment = dict(base_environment)
    # The release verifier scopes this flag to its own probe process. Do not
    # let the later desktop smoke launches inherit verification-only mode.
    environment.pop("LLPLAYERNEXT_VERIFY_GEN_BUNDLE", None)
    environment.update(
        {
            "FLUTTER": flutter,
            "BACKEND_LOCK": str(backend_lock),
            "LISTEN_GEN_LOCK_PATH": str(gen_lock),
            "LISTEN_GEN_RELEASE_MANIFEST": str(gen_manifest),
            "LISTEN_RELEASE_OUTPUT_DIR": str(output),
            "LISTEN_RELEASE_VERSION": metadata["version"],
            "LISTEN_RELEASE_CHANNEL": metadata["channel"],
            "LISTEN_RELEASE_MINIMUM_MACOS_VERSION": metadata["minimum_macos"],
            "LISTEN_RELEASE_BUILD_NUMBER": metadata["build_number"],
            "LISTEN_SOURCE_COMMIT": source_commit,
        }
    )
    return environment


def _release_from_export(
    source_root: Path,
    export_git_sha: str,
    source_sha: str,
    output: Path,
    runtime: Path,
    python: Path,
    metadata: Dict[str, str],
) -> None:
    core = source_root / "core"
    app = source_root / "app"
    _check_app_release_script_syntax(app)
    _run(
        [str(core / "scripts" / "verify-asr-runtime.sh"), str(runtime)],
        core,
    )
    cargo = _cargo_executable()
    cargo_target = ROOT / ".dev" / "cargo-target"
    core_target = cargo_target / "release" / "api-http"
    core_env = dict(os.environ)
    core_env["CARGO_TARGET_DIR"] = str(cargo_target)
    _run([cargo, "build", "--locked", "--release", "-p", "api-http"], core, core_env)
    if not core_target.is_file():
        raise DevError(f"Core release build did not produce {core_target}.")

    contract_dir = output / "core" / "contracts"
    contract_manifest = _build_contract_artifact(source_root, output / "core", source_sha)
    contract_archives = list(contract_dir.glob("listen-contracts-*.tar.gz"))
    if len(contract_archives) != 1:
        raise DevError("Core contract packaging did not produce exactly one artifact.")
    contract_archive = contract_archives[0]

    runtime_output = output / "core" / "runtime"
    _run(
        [
            str(core / "scripts" / "package-runtime-bundle.sh"),
            "--output-dir",
            str(runtime_output),
            "--api-http",
            str(core_target),
            "--runtime-dir",
            str(runtime),
            "--runtime-manifest",
            os.environ.get(
                "LISTEN_CORE_RUNTIME_MANIFEST",
                str(core / "third_party" / "runtime" / "manifest.json"),
            ),
            "--notices",
            os.environ.get(
                "LISTEN_CORE_THIRD_PARTY_NOTICES",
                str(core / "third_party" / "runtime" / "THIRD_PARTY_NOTICES.md"),
            ),
            "--git-sha",
            source_sha,
        ],
        core,
    )
    runtime_archives = list(runtime_output.glob("listen-core-runtime-*.tar.gz"))
    runtime_manifests = list(runtime_output.glob("listen-core-runtime-*.manifest.json"))
    if len(runtime_archives) != 1 or len(runtime_manifests) != 1:
        raise DevError("Core runtime packaging did not produce one artifact and its manifest.")
    runtime_archive = runtime_archives[0]
    runtime_manifest = runtime_manifests[0]

    gen_dir = output / "gen"
    gen_manifest = _build_gen_bundle(
        source_root,
        gen_dir,
        source_sha,
        contract_manifest,
        python,
    )
    gen_lock = write_gen_lock(
        gen_manifest,
        output / "locks" / "listen_gen.lock.json",
        debug_only=False,
    )
    backend_lock, _ = _release_lock_paths(output)
    _write_backend_lock(
        contract_manifest,
        contract_archive,
        runtime_manifest,
        runtime_archive,
        backend_lock,
        source_sha,
    )
    _assert_clean_head(source_root, export_git_sha, "during Core and Gen packaging")

    _run(
        [
            sys.executable,
            str(app / "tool" / "backend_artifacts.py"),
            "--lock",
            str(backend_lock),
            "install",
            "--contract-archive",
            str(contract_archive),
            "--runtime-archive",
            str(runtime_archive),
            "--skip-fixture-sync",
        ],
        app,
    )
    _assert_clean_head(source_root, export_git_sha, "before app packaging")
    release_env = _app_release_environment(
        os.environ,
        flutter=_flutter_executable(),
        backend_lock=backend_lock,
        gen_lock=gen_lock,
        gen_manifest=gen_manifest,
        output=output / "app",
        metadata=metadata,
        source_commit=source_sha,
    )
    _build_verify_and_assemble_preview(app, release_env, output, source_sha, metadata)
    _assert_clean_head(source_root, export_git_sha, "after release verification")


def _check_app_release_script_syntax(app: Path) -> None:
    for name in ("build-macos-release.sh", "verify-macos-release.sh"):
        script = app / "tool" / name
        _run(["bash", "-n", str(script)], app)


def _build_verify_and_assemble_preview(
    app: Path,
    release_env: Dict[str, str],
    output: Path,
    source_sha: str,
    metadata: Dict[str, str],
) -> None:
    build_script = app / "tool" / "build-macos-release.sh"
    verify_script = app / "tool" / "verify-macos-release.sh"
    _run([str(build_script)], app, release_env)
    _run([str(verify_script)], app, release_env)
    app_bundle = app / "build" / "macos" / "Build" / "Products" / "Release" / "listen.app"
    bundle_metadata = dict(metadata)
    bundle_metadata["source_commit"] = source_sha
    bundle_facts = _macos_bundle_facts(app_bundle, bundle_metadata)
    _assemble_preview_distribution(
        output,
        output / "app" / "listen-macos-arm64.zip",
        source_sha,
        metadata,
        bundle_facts,
    )


def command_status(args: argparse.Namespace) -> None:
    head = _git(ROOT, "rev-parse", "--short", "HEAD")
    changes = _git(ROOT, "status", "--short", "--untracked-files=normal")
    print(f"Listen monorepo: {ROOT}")
    print(f"HEAD: {head}")
    print("Working tree: " + ("dirty" if changes else "clean"))
    if changes:
        print(changes)
    default_python = Path(sys.executable)
    default_version = _version_of(default_python)
    print(
        "Launcher Python: "
        + (".".join(map(str, default_version)) if default_version else "unknown")
        + f" ({default_python})"
    )
    try:
        gen_python = discover_gen_python(ROOT)
        version = _version_of(gen_python)
        print(f"Gen Python: {'.'.join(map(str, version or (0, 0, 0)))} ({gen_python})")
    except DevError as error:
        print(f"Gen Python: unavailable ({error})")
    flutter = os.environ.get("FLUTTER") or shutil.which("flutter")
    print(f"Flutter: {flutter or 'not found'}")
    print(f"Cargo: {os.environ.get('CARGO') or shutil.which('cargo') or 'not found'}")
    try:
        print(f"Core runtime inputs: {_runtime_dir(ROOT)}")
    except DevError as error:
        print(f"Core runtime inputs: unavailable ({error})")
    snapshots = ROOT / ".dev" / "snapshots"
    if snapshots.is_dir():
        entries = sorted(
            (
                path
                for path in snapshots.iterdir()
                if path.is_dir()
                and re.fullmatch(r"[0-9a-f]{40}(?:-[0-9a-f]{32})?", path.name)
            ),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        if entries:
            print(f"Latest working source snapshot: {entries[0].name}")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        prog="./dev",
        description="Set up, run, check, test, and build the Listen development preview.",
    )
    commands = result.add_subparsers(dest="command", required=True)

    setup = commands.add_parser("setup", help="install Flutter and minimal Gen development dependencies")
    setup.add_argument(
        "--extras",
        action="append",
        default=[],
        metavar="NAME[,NAME...]",
        help="opt in to Gen model/runtime extras (tts, ocr, align, asr-qwen, asr-sensevoice, all)",
    )
    setup.set_defaults(func=command_setup)

    run = commands.add_parser("run", help="build current Core and Gen source, then run the macOS app")
    run.add_argument("--device", default="macos")
    run.add_argument("flutter_args", nargs=argparse.REMAINDER)
    run.set_defaults(func=command_run)

    check = commands.add_parser("check", help="run native app, Core, and Gen quality gates")
    check.set_defaults(func=command_check)

    test = commands.add_parser("test", help="run tests or the model-free integration roundtrip")
    test.add_argument("suite", nargs="?", choices=("unit", "integration"), default="unit")
    test.set_defaults(func=command_test)

    release = commands.add_parser("release", help="build and verify a clean committed macOS development preview")
    release.add_argument(
        "--output-dir",
        help="external, empty directory; upload-ready assets are in its distribution/ subdirectory",
    )
    release.set_defaults(func=command_release)

    status = commands.add_parser("status", help="show source and local toolchain status")
    status.set_defaults(func=command_status)
    return result


def main(argv: Optional[Sequence[str]] = None) -> int:
    try:
        args = parser().parse_args(argv)
        args.func(args)
        return 0
    except DevError as error:
        print(f"dev: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("dev: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
