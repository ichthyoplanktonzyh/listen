#!/usr/bin/env python3
"""Deterministic listen-gen release bundle builder and verifier.

Produces an immutable Gen handoff consisting of a runnable Python zipapp
and a sidecar release manifest. Builds do not call Git and do not access
the network; the source commit is supplied by the caller and pinned in the
manifest only.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import io
import json
import os
import re
import shutil
import sys
import tempfile
import tomllib
import zipfile
from pathlib import Path

RELEASE_BUNDLE_SCHEMA = "listen_gen.release-bundle.v1"
SOURCE_REPOSITORY = "https://github.com/ichthyoplanktonzyh/listen-gen"
TOOL_NAME = "listen-gen"
REQUIRED_PYTHON = ">=3.11"
MACHINE_EVENT_SCHEMA = "listen_gen.machine-event.v1"
MACHINE_PROTOCOL_VERSION = 1
TOOL_ID = "listen-gen"
PROVIDER_REQUIREMENTS = {
    "fixture": [],
    "command": ["ffprobe", "ffmpeg", "asr-wrapper"],
    "whisper-cpp": ["ffprobe", "ffmpeg", "whisper-cli", "whisper-model"],
    "sense-groups-fixture": [],
    "sense-groups-command": ["sense-group-extractor"],
    "sense-groups-baseline": [],
    "acoustics-fixture": [],
    "acoustics-command": ["ffprobe", "ffmpeg", "acoustics-extractor"],
    "acoustics-baseline": ["ffprobe", "ffmpeg"],
    "prosody-fixture": [],
    "prosody-command": ["prosody-extractor"],
    "prosody-baseline": [],
    "phone-fixture": [],
    "phone-command": ["ffprobe", "ffmpeg", "phone-analyzer"],
    "phone-wav2vec2-ctc": [
        "ffprobe", "ffmpeg", "python", "wav2vec2-phone-sidecar", "wav2vec2-phone-model"
    ],
}
EXPECTED_LOCK = {
    "authority": {
        "path": "contracts/content-package/v1",
        "repository": "ichthyoplanktonzyh/listen-core",
    },
    "manifest_schema_id": "https://listen.dev/contracts/content-package/v1/manifest.schema.json",
    "package_schema": "listen.resource-package.v1",
    "resource_schema_id": "https://listen.dev/contracts/content-package/v1/resource.schema.json",
    "schema_version": 1,
}

SOURCE_COMMIT_RE = re.compile(r"[0-9a-f]{40}")
SHA256_RE = re.compile(r"sha256:[0-9a-f]{64}")
SHEBANG = b"#!/usr/bin/env python3\n"
FIXED_DATE_TIME = (1980, 1, 1, 0, 0, 0)
ENTRY_MODE = 0o100644
ARCHIVE_MODE = 0o755

ROOT_MAIN_SOURCE = """\
from __future__ import annotations

import sys

if sys.version_info < (3, 11):
    raise SystemExit("listen-gen requires Python 3.11 or newer")

from listen_gen.cli import main

raise SystemExit(main())
"""

MANIFEST_ROOT_FIELDS = frozenset(
    {
        "schema",
        "tool",
        "source",
        "machine_protocol",
        "content_package_contract",
        "runtime",
        "artifact",
    }
)
MANIFEST_TOOL_FIELDS = frozenset({"id", "version"})
MANIFEST_SOURCE_FIELDS = frozenset({"repository", "commit"})
MANIFEST_PROTOCOL_FIELDS = frozenset({"schema", "version"})
MANIFEST_CONTRACT_FIELDS = frozenset(
    {
        "authority",
        "manifest_schema_id",
        "resource_schema_id",
        "package_schema",
        "schema_version",
        "canonical_sha256",
    }
)
MANIFEST_AUTHORITY_FIELDS = frozenset({"repository", "path"})
MANIFEST_RUNTIME_FIELDS = frozenset({"python_requires", "provider_requirements"})
MANIFEST_ARTIFACT_FIELDS = frozenset(
    {"filename", "format", "entrypoint", "size_bytes", "sha256"}
)


class ReleaseBundleError(Exception):
    pass


def _canonical_json_bytes(document: object) -> bytes:
    return json.dumps(
        document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def _canonical_json_file_bytes(document: object) -> bytes:
    return _canonical_json_bytes(document) + b"\n"


def _sha256_hex(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _load_protocol_constants(repo_root: Path) -> dict[str, object]:
    """Import protocol constants from the checkout source, never an install.

    All cached ``listen_gen`` modules are removed for the duration of the
    import so a different checkout is never shadowed by the caller's state,
    and the caller's module state is fully restored afterwards.
    """
    src = str(repo_root / "src")
    saved_modules = {
        name: module
        for name, module in sys.modules.items()
        if name == "listen_gen" or name.startswith("listen_gen.")
    }
    for name in saved_modules:
        del sys.modules[name]
    sys.path.insert(0, src)
    try:
        try:
            protocol = importlib.import_module("listen_gen.protocol")
            constants = {
                "tool_id": protocol.TOOL_ID,
                "tool_version": protocol.TOOL_VERSION,
                "machine_event_schema": protocol.MACHINE_EVENT_SCHEMA,
                "machine_protocol_version": protocol.MACHINE_PROTOCOL_VERSION,
            }
        except Exception:
            raise ReleaseBundleError("release source package is missing")
        finally:
            for name in [
                name
                for name in sys.modules
                if name == "listen_gen" or name.startswith("listen_gen.")
            ]:
                del sys.modules[name]
        return constants
    finally:
        sys.modules.update(saved_modules)
        try:
            sys.path.remove(src)
        except ValueError:
            pass


def _read_project_metadata(repo_root: Path) -> tuple[str, str]:
    try:
        raw = (repo_root / "pyproject.toml").read_bytes()
    except FileNotFoundError:
        raise ReleaseBundleError("release manifest is invalid")
    try:
        data = tomllib.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError):
        raise ReleaseBundleError("release manifest is invalid")
    project = data.get("project")
    if not isinstance(project, dict):
        raise ReleaseBundleError("release manifest is invalid")
    name = project.get("name")
    version = project.get("version")
    requires_python = project.get("requires-python")
    if name != TOOL_NAME or not isinstance(version, str) or requires_python != REQUIRED_PYTHON:
        raise ReleaseBundleError("release manifest is invalid")
    return version, requires_python


def _read_contract_lock(repo_root: Path) -> dict[str, object]:
    path = repo_root / "contracts.lock.json"
    if not path.is_file():
        raise ReleaseBundleError("content package contract lock is invalid")
    try:
        parsed = json.loads(path.read_text("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ReleaseBundleError("content package contract lock is invalid")
    if parsed != EXPECTED_LOCK:
        raise ReleaseBundleError("content package contract lock is invalid")
    return parsed


def _collect_source_entries(repo_root: Path) -> list[tuple[str, bytes]]:
    package_root = repo_root / "src" / "listen_gen"
    if not package_root.is_dir():
        raise ReleaseBundleError("release archive content does not match source")
    entries: list[tuple[str, bytes]] = []
    for path in sorted(package_root.rglob("*.py")):
        if path.is_symlink() or not path.is_file():
            continue
        archive_path = "listen_gen/" + path.relative_to(package_root).as_posix()
        try:
            raw = path.read_bytes()
            text = raw.decode("utf-8")
        except (OSError, UnicodeDecodeError):
            raise ReleaseBundleError("release archive content does not match source")
        normalized = text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")
        entries.append((archive_path, normalized))
    entries.append(("__main__.py", ROOT_MAIN_SOURCE.encode("utf-8")))
    entries.sort(key=lambda item: item[0])
    return entries


def _build_pyz_bytes(entries: list[tuple[str, bytes]]) -> bytes:
    seen: set[str] = set()
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        for archive_path, data in entries:
            if archive_path in seen:
                raise ReleaseBundleError("release archive is invalid")
            if "\\" in archive_path or archive_path.startswith("/"):
                raise ReleaseBundleError("release archive is invalid")
            if ".." in archive_path.split("/"):
                raise ReleaseBundleError("release archive is invalid")
            seen.add(archive_path)
            info = zipfile.ZipInfo(filename=archive_path, date_time=FIXED_DATE_TIME)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = ENTRY_MODE << 16
            archive.writestr(info, data)
    return SHEBANG + buffer.getvalue()


def _write_pyz(path: Path, data: bytes) -> None:
    path.write_bytes(data)
    try:
        # Best effort: execution must not depend on the executable bit.
        path.chmod(ARCHIVE_MODE)
    except OSError:
        pass


def _build_manifest(
    version: str,
    source_commit: str,
    constants: dict[str, object],
    lock: dict[str, object],
    pyz_bytes: bytes,
) -> dict[str, object]:
    authority = lock["authority"]
    assert isinstance(authority, dict)
    return {
        "schema": RELEASE_BUNDLE_SCHEMA,
        "tool": {
            "id": constants["tool_id"],
            "version": constants["tool_version"],
        },
        "source": {
            "repository": SOURCE_REPOSITORY,
            "commit": source_commit,
        },
        "machine_protocol": {
            "schema": constants["machine_event_schema"],
            "version": constants["machine_protocol_version"],
        },
        "content_package_contract": {
            "authority": {
                "repository": authority["repository"],
                "path": authority["path"],
            },
            "manifest_schema_id": lock["manifest_schema_id"],
            "resource_schema_id": lock["resource_schema_id"],
            "package_schema": lock["package_schema"],
            "schema_version": lock["schema_version"],
            "canonical_sha256": _sha256_hex(_canonical_json_bytes(lock)),
        },
        "runtime": {
            "python_requires": REQUIRED_PYTHON,
            "provider_requirements": PROVIDER_REQUIREMENTS,
        },
        "artifact": {
            "filename": f"listen-gen-{version}.pyz",
            "format": "python-zipapp",
            "entrypoint": "__main__.py",
            "size_bytes": len(pyz_bytes),
            "sha256": _sha256_hex(pyz_bytes),
        },
    }


def build_release_bundle(
    repo_root: Path,
    output_parent: Path,
    source_commit: str,
) -> tuple[Path, Path]:
    repo_root = Path(repo_root)
    output_parent = Path(output_parent)
    if not isinstance(source_commit, str) or not SOURCE_COMMIT_RE.fullmatch(
        source_commit
    ):
        raise ReleaseBundleError("source commit must be a lowercase 40-character SHA")
    version, _ = _read_project_metadata(repo_root)
    constants = _load_protocol_constants(repo_root)
    if constants["tool_id"] != TOOL_ID:
        raise ReleaseBundleError("release manifest is invalid")
    if constants["tool_version"] != version:
        raise ReleaseBundleError("release manifest is invalid")
    if constants["machine_event_schema"] != MACHINE_EVENT_SCHEMA:
        raise ReleaseBundleError("release manifest is invalid")
    if constants["machine_protocol_version"] != MACHINE_PROTOCOL_VERSION:
        raise ReleaseBundleError("release manifest is invalid")
    lock = _read_contract_lock(repo_root)

    bundle_dir = output_parent / f"listen-gen-{version}"
    if bundle_dir.exists():
        raise ReleaseBundleError("release bundle directory already exists")
    output_parent.mkdir(parents=True, exist_ok=True)

    staging = None
    try:
        staging = Path(
            tempfile.mkdtemp(
                prefix=f".listen-gen-{version}.staging.", dir=str(output_parent)
            )
        )
        entries = _collect_source_entries(repo_root)
        pyz_bytes = _build_pyz_bytes(entries)
        manifest = _build_manifest(version, source_commit, constants, lock, pyz_bytes)
        pyz_name = f"listen-gen-{version}.pyz"
        manifest_name = f"listen-gen-{version}.release.json"
        _write_pyz(staging / pyz_name, pyz_bytes)
        (staging / manifest_name).write_bytes(_canonical_json_file_bytes(manifest))
        verify_release_bundle(repo_root, staging / manifest_name)
        os.replace(str(staging), str(bundle_dir))
        staging = None
        return bundle_dir / pyz_name, bundle_dir / manifest_name
    finally:
        if staging is not None:
            shutil.rmtree(staging, ignore_errors=True)


def _check_keys(mapping: object, expected: frozenset[str]) -> None:
    if not isinstance(mapping, dict) or set(mapping) != expected:
        raise ReleaseBundleError("release manifest is invalid")


def _parse_manifest(manifest_path: Path) -> dict[str, object]:
    try:
        raw = manifest_path.read_bytes()
    except OSError:
        raise ReleaseBundleError("release manifest is invalid")
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ReleaseBundleError("release manifest is invalid")
    if not isinstance(parsed, dict):
        raise ReleaseBundleError("release manifest is invalid")
    if raw != _canonical_json_file_bytes(parsed):
        raise ReleaseBundleError("release manifest is invalid")
    _check_keys(parsed, MANIFEST_ROOT_FIELDS)
    if parsed["schema"] != RELEASE_BUNDLE_SCHEMA:
        raise ReleaseBundleError("release manifest is invalid")
    tool = parsed["tool"]
    _check_keys(tool, MANIFEST_TOOL_FIELDS)
    version = tool["version"]
    if tool["id"] != TOOL_ID or not isinstance(version, str) or not version:
        raise ReleaseBundleError("release manifest is invalid")
    if manifest_path.name != f"listen-gen-{version}.release.json":
        raise ReleaseBundleError("release manifest is invalid")
    source = parsed["source"]
    _check_keys(source, MANIFEST_SOURCE_FIELDS)
    if source["repository"] != SOURCE_REPOSITORY:
        raise ReleaseBundleError("release manifest is invalid")
    commit = source["commit"]
    if not isinstance(commit, str) or not SOURCE_COMMIT_RE.fullmatch(commit):
        raise ReleaseBundleError("release manifest is invalid")
    machine_protocol = parsed["machine_protocol"]
    _check_keys(machine_protocol, MANIFEST_PROTOCOL_FIELDS)
    if machine_protocol["schema"] != MACHINE_EVENT_SCHEMA:
        raise ReleaseBundleError("release manifest is invalid")
    protocol_version = machine_protocol["version"]
    if type(protocol_version) is not int:
        raise ReleaseBundleError("release manifest is invalid")
    if protocol_version != MACHINE_PROTOCOL_VERSION:
        raise ReleaseBundleError("release manifest is invalid")
    contract = parsed["content_package_contract"]
    _check_keys(contract, MANIFEST_CONTRACT_FIELDS)
    authority = contract["authority"]
    _check_keys(authority, MANIFEST_AUTHORITY_FIELDS)
    if authority != EXPECTED_LOCK["authority"]:
        raise ReleaseBundleError("release manifest is invalid")
    if contract["manifest_schema_id"] != EXPECTED_LOCK["manifest_schema_id"]:
        raise ReleaseBundleError("release manifest is invalid")
    if contract["resource_schema_id"] != EXPECTED_LOCK["resource_schema_id"]:
        raise ReleaseBundleError("release manifest is invalid")
    if contract["package_schema"] != EXPECTED_LOCK["package_schema"]:
        raise ReleaseBundleError("release manifest is invalid")
    schema_version = contract["schema_version"]
    if type(schema_version) is not int:
        raise ReleaseBundleError("release manifest is invalid")
    if schema_version != EXPECTED_LOCK["schema_version"]:
        raise ReleaseBundleError("release manifest is invalid")
    canonical_sha256 = contract["canonical_sha256"]
    if not isinstance(canonical_sha256, str) or not SHA256_RE.fullmatch(
        canonical_sha256
    ):
        raise ReleaseBundleError("release manifest is invalid")
    if canonical_sha256 != _sha256_hex(_canonical_json_bytes(EXPECTED_LOCK)):
        raise ReleaseBundleError("release manifest is invalid")
    runtime = parsed["runtime"]
    _check_keys(runtime, MANIFEST_RUNTIME_FIELDS)
    if runtime["python_requires"] != REQUIRED_PYTHON:
        raise ReleaseBundleError("release manifest is invalid")
    if runtime["provider_requirements"] != PROVIDER_REQUIREMENTS:
        raise ReleaseBundleError("release manifest is invalid")
    artifact = parsed["artifact"]
    _check_keys(artifact, MANIFEST_ARTIFACT_FIELDS)
    filename = artifact["filename"]
    expected_filename = f"listen-gen-{version}.pyz"
    if (
        not isinstance(filename, str)
        or filename != expected_filename
        or "/" in filename
        or "\\" in filename
        or ".." in filename
    ):
        raise ReleaseBundleError("release manifest is invalid")
    if artifact["format"] != "python-zipapp":
        raise ReleaseBundleError("release manifest is invalid")
    if artifact["entrypoint"] != "__main__.py":
        raise ReleaseBundleError("release manifest is invalid")
    size_bytes = artifact["size_bytes"]
    if type(size_bytes) is not int or size_bytes < 0:
        raise ReleaseBundleError("release manifest is invalid")
    sha256 = artifact["sha256"]
    if not isinstance(sha256, str) or not SHA256_RE.fullmatch(sha256):
        raise ReleaseBundleError("release manifest is invalid")
    return parsed


def _check_archive_structure(archive: zipfile.ZipFile) -> None:
    if archive.comment:
        raise ReleaseBundleError("release archive is invalid")
    names = archive.namelist()
    if len(names) != len(set(names)):
        raise ReleaseBundleError("release archive is invalid")
    if names != sorted(names):
        raise ReleaseBundleError("release archive is invalid")
    for name in names:
        if name.startswith("/") or "\\" in name:
            raise ReleaseBundleError("release archive is invalid")
        if ".." in name.split("/"):
            raise ReleaseBundleError("release archive is invalid")
        info = archive.getinfo(name)
        if info.is_dir():
            raise ReleaseBundleError("release archive is invalid")
        if info.compress_type != zipfile.ZIP_STORED:
            raise ReleaseBundleError("release archive is invalid")
        if info.date_time != FIXED_DATE_TIME:
            raise ReleaseBundleError("release archive is invalid")
        if info.create_system != 3:
            raise ReleaseBundleError("release archive is invalid")
        if info.external_attr != ENTRY_MODE << 16:
            raise ReleaseBundleError("release archive is invalid")


def verify_release_bundle(
    repo_root: Path,
    manifest_path: Path,
) -> dict[str, object]:
    repo_root = Path(repo_root)
    manifest_path = Path(manifest_path)
    manifest = _parse_manifest(manifest_path)
    project_version, requires_python = _read_project_metadata(repo_root)
    constants = _load_protocol_constants(repo_root)
    if constants["tool_id"] != TOOL_ID:
        raise ReleaseBundleError("release manifest is invalid")
    if constants["tool_version"] != project_version:
        raise ReleaseBundleError("release manifest is invalid")
    if constants["machine_event_schema"] != MACHINE_EVENT_SCHEMA:
        raise ReleaseBundleError("release manifest is invalid")
    if constants["machine_protocol_version"] != MACHINE_PROTOCOL_VERSION:
        raise ReleaseBundleError("release manifest is invalid")
    if manifest["tool"] != {
        "id": constants["tool_id"],
        "version": constants["tool_version"],
    }:
        raise ReleaseBundleError("release manifest is invalid")
    if manifest["machine_protocol"] != {
        "schema": constants["machine_event_schema"],
        "version": constants["machine_protocol_version"],
    }:
        raise ReleaseBundleError("release manifest is invalid")
    if manifest["runtime"]["python_requires"] != requires_python:
        raise ReleaseBundleError("release manifest is invalid")
    version = manifest["tool"]["version"]
    artifact = manifest["artifact"]
    artifact_path = manifest_path.parent / artifact["filename"]
    if not artifact_path.is_file():
        raise ReleaseBundleError("release artifact is missing")
    data = artifact_path.read_bytes()
    if len(data) != artifact["size_bytes"]:
        raise ReleaseBundleError("release artifact size mismatch")
    if _sha256_hex(data) != artifact["sha256"]:
        raise ReleaseBundleError("release artifact checksum mismatch")
    if not data.startswith(SHEBANG):
        raise ReleaseBundleError("release archive is invalid")
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise ReleaseBundleError("release archive is invalid")
    with archive:
        _check_archive_structure(archive)
        expected_entries = _collect_source_entries(repo_root)
        if archive.namelist() != [name for name, _ in expected_entries]:
            raise ReleaseBundleError("release archive content does not match source")
        for name, expected_bytes in expected_entries:
            if archive.read(name) != expected_bytes:
                raise ReleaseBundleError("release archive content does not match source")
    lock = _read_contract_lock(repo_root)
    contract = manifest["content_package_contract"]
    authority = contract["authority"]
    assert isinstance(authority, dict)
    lock_authority = lock["authority"]
    assert isinstance(lock_authority, dict)
    if authority["repository"] != lock_authority["repository"]:
        raise ReleaseBundleError("content package contract lock is invalid")
    if authority["path"] != lock_authority["path"]:
        raise ReleaseBundleError("content package contract lock is invalid")
    if contract["manifest_schema_id"] != lock["manifest_schema_id"]:
        raise ReleaseBundleError("content package contract lock is invalid")
    if contract["resource_schema_id"] != lock["resource_schema_id"]:
        raise ReleaseBundleError("content package contract lock is invalid")
    if contract["package_schema"] != lock["package_schema"]:
        raise ReleaseBundleError("content package contract lock is invalid")
    if contract["schema_version"] != lock["schema_version"]:
        raise ReleaseBundleError("content package contract lock is invalid")
    if contract["canonical_sha256"] != _sha256_hex(_canonical_json_bytes(lock)):
        raise ReleaseBundleError("content package contract lock is invalid")
    return {
        "status": "verified",
        "tool": {"id": TOOL_ID, "version": version},
        "artifact_sha256": artifact["sha256"],
    }


def _resolve_repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _cmd_build(args: argparse.Namespace) -> int:
    artifact_path, manifest_path = build_release_bundle(
        _resolve_repo_root(), Path(args.output_parent), args.source_commit
    )
    bundle_name = artifact_path.parent.name
    print(
        json.dumps(
            {
                "status": "created",
                "artifact": f"{bundle_name}/{artifact_path.name}",
                "manifest": f"{bundle_name}/{manifest_path.name}",
            },
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
    )
    return 0


def _cmd_verify(args: argparse.Namespace) -> int:
    result = verify_release_bundle(_resolve_repo_root(), Path(args.manifest))
    print(
        json.dumps(
            result,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        )
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="release_bundle",
        description="Build and verify the deterministic listen-gen release bundle.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    build_parser = subparsers.add_parser("build", help="build the release bundle")
    build_parser.add_argument(
        "--source-commit", required=True, help="40-character lowercase Git SHA"
    )
    build_parser.add_argument(
        "--output-parent", required=True, help="directory that receives the bundle"
    )
    build_parser.set_defaults(func=_cmd_build)
    verify_parser = subparsers.add_parser("verify", help="verify a release bundle")
    verify_parser.add_argument("manifest", help="path to the release manifest")
    verify_parser.set_defaults(func=_cmd_verify)
    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ReleaseBundleError as error:
        print(f"release bundle error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
