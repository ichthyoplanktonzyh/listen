#!/usr/bin/env python3
"""Build and verify deterministic contract and local-runtime release artifacts."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import json
import os
import re
import stat
import subprocess
import tarfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Iterable


ROOT = Path(__file__).resolve().parent.parent
CONTRACT_FILES = (
    "contracts/openapi/v1.yaml",
    "contracts/events/v1.schema.json",
    "contracts/events/examples.json",
    "contracts/player-adapter/player-contract.schema.json",
    "contracts/player-adapter/examples.json",
    "testdata/rhythm-frame-qa/fixture-no-phone-rhythm.lltimeline.json",
    "testdata/rhythm-frame-qa/fixture-rhythm.lltimeline.json",
    "testdata/semantic-task/gold-fixture-v1.json",
)


@dataclass(frozen=True)
class ArtifactEntry:
    archive_path: str
    data: bytes
    mode: int = 0o644


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()


def repository_git_sha(root: Path, allow_dirty: bool) -> str:
    if not allow_dirty:
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        if status.strip():
            raise SystemExit(
                "refusing to publish artifacts from a dirty worktree; "
                "commit first or pass --allow-dirty for local verification"
            )
    return subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def openapi_contract_version(openapi: bytes) -> str:
    text = openapi.decode()
    info = re.search(r"(?m)^info:\n(?:^[ \t].*\n)*?^  version: ([0-9]+\.[0-9]+\.[0-9]+)\s*$", text)
    if info is None:
        raise SystemExit("OpenAPI info.version must be a plain semantic version")
    return info.group(1)


def workspace_runtime_version(cargo_toml: bytes) -> str:
    text = cargo_toml.decode()
    workspace = re.search(
        r"(?ms)^\[workspace\.package\]\s*$.*?^version\s*=\s*\"([0-9]+\.[0-9]+\.[0-9]+)\"",
        text,
    )
    if workspace is None:
        raise SystemExit("Cargo workspace.package.version is missing")
    return workspace.group(1)


def write_deterministic_tar_gz(entries: Iterable[ArtifactEntry], destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    ordered = sorted(entries, key=lambda entry: entry.archive_path)
    with destination.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
                for entry in ordered:
                    archive_path = PurePosixPath(entry.archive_path)
                    if archive_path.is_absolute() or ".." in archive_path.parts:
                        raise SystemExit(f"unsafe artifact path: {entry.archive_path}")
                    info = tarfile.TarInfo(str(archive_path))
                    info.size = len(entry.data)
                    info.mode = entry.mode
                    info.mtime = 0
                    info.uid = 0
                    info.gid = 0
                    info.uname = ""
                    info.gname = ""
                    archive.addfile(info, io.BytesIO(entry.data))


def write_sidecars(destination: Path, manifest: dict[str, object]) -> None:
    manifest_path = destination.with_suffix("").with_suffix(".manifest.json")
    manifest_path.write_bytes(canonical_json(manifest))
    digest = sha256_bytes(destination.read_bytes())
    destination.with_suffix(destination.suffix + ".sha256").write_text(
        f"{digest}  {destination.name}\n",
        encoding="utf-8",
    )


def build_contract_artifact(args: argparse.Namespace) -> Path:
    root = Path(args.root).resolve()
    source_entries = []
    file_hashes = {}
    for relative in CONTRACT_FILES:
        data = (root / relative).read_bytes()
        source_entries.append(ArtifactEntry(relative, data))
        file_hashes[relative] = sha256_bytes(data)
    version = openapi_contract_version((root / CONTRACT_FILES[0]).read_bytes())
    git_sha = args.git_sha or repository_git_sha(root, args.allow_dirty)
    manifest: dict[str, object] = {
        "manifest_version": 1,
        "artifact_kind": "listen-contracts",
        "contract_version": version,
        "core_git_sha": git_sha,
        "api_version": 1,
        "event_schema_version": 1,
        "files": file_hashes,
    }
    destination = Path(args.output_dir).resolve() / f"listen-contracts-{version}.tar.gz"
    write_deterministic_tar_gz(
        [ArtifactEntry("manifest.json", canonical_json(manifest)), *source_entries],
        destination,
    )
    write_sidecars(destination, manifest)
    verify_artifact(destination)
    return destination


def executable_mode(path: Path) -> int:
    return 0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644


def runtime_source_entries(
    api_http: Path,
    runtime_dir: Path,
    runtime_manifest: Path,
    notices: Path,
) -> list[ArtifactEntry]:
    entries = [
        ArtifactEntry("bin/api-http", api_http.read_bytes(), executable_mode(api_http)),
        ArtifactEntry("runtime/manifest.json", runtime_manifest.read_bytes()),
        ArtifactEntry("THIRD_PARTY_NOTICES.md", notices.read_bytes()),
    ]
    for path in sorted(runtime_dir.rglob("*")):
        if path.is_file():
            relative = path.relative_to(runtime_dir).as_posix()
            entries.append(
                ArtifactEntry(
                    f"runtime/{relative}",
                    path.read_bytes(),
                    executable_mode(path),
                )
            )
    return entries


def build_runtime_artifact(args: argparse.Namespace) -> Path:
    root = Path(args.root).resolve()
    api_http = Path(args.api_http).resolve()
    runtime_dir = Path(args.runtime_dir).resolve()
    runtime_manifest = Path(args.runtime_manifest).resolve()
    notices = Path(args.notices).resolve()
    for required in (api_http, runtime_dir, runtime_manifest, notices):
        if not required.exists():
            raise SystemExit(f"required runtime input is missing: {required}")
    contract_version = openapi_contract_version(
        (root / "contracts/openapi/v1.yaml").read_bytes()
    )
    runtime_version = workspace_runtime_version((root / "Cargo.toml").read_bytes())
    git_sha = args.git_sha or repository_git_sha(root, args.allow_dirty)
    source_entries = runtime_source_entries(api_http, runtime_dir, runtime_manifest, notices)
    files = {entry.archive_path: sha256_bytes(entry.data) for entry in source_entries}
    manifest: dict[str, object] = {
        "manifest_version": 1,
        "artifact_kind": "listen-core-runtime",
        "runtime_version": runtime_version,
        "contract_version": contract_version,
        "core_git_sha": git_sha,
        "platform": args.platform,
        "arch": args.arch,
        "files": files,
    }
    destination = (
        Path(args.output_dir).resolve()
        / f"listen-core-runtime-{runtime_version}-{args.platform}-{args.arch}.tar.gz"
    )
    write_deterministic_tar_gz(
        [ArtifactEntry("manifest.json", canonical_json(manifest)), *source_entries],
        destination,
    )
    write_sidecars(destination, manifest)
    verify_artifact(destination)
    return destination


def verify_artifact(path: Path) -> dict[str, object]:
    archive_bytes = path.read_bytes()
    if not archive_bytes:
        raise SystemExit(f"artifact is empty: {path}")
    with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        if len(names) != len(set(names)):
            raise SystemExit("artifact contains duplicate paths")
        for name in names:
            parsed = PurePosixPath(name)
            if parsed.is_absolute() or ".." in parsed.parts:
                raise SystemExit(f"artifact contains unsafe path: {name}")
        manifest_member = archive.getmember("manifest.json")
        manifest_file = archive.extractfile(manifest_member)
        if manifest_file is None:
            raise SystemExit("artifact manifest is unreadable")
        manifest = json.load(manifest_file)
        expected_files = manifest.get("files")
        if not isinstance(expected_files, dict):
            raise SystemExit("artifact manifest files map is missing")
        actual_names = set(names) - {"manifest.json"}
        if actual_names != set(expected_files):
            raise SystemExit(
                "artifact contents disagree with manifest: "
                f"missing={sorted(set(expected_files) - actual_names)}, "
                f"unexpected={sorted(actual_names - set(expected_files))}"
            )
        for name, expected in expected_files.items():
            member_file = archive.extractfile(archive.getmember(name))
            if member_file is None:
                raise SystemExit(f"artifact member is unreadable: {name}")
            actual = sha256_bytes(member_file.read())
            if actual != expected:
                raise SystemExit(f"artifact member hash mismatch: {name}")
        return manifest


def command_verify(args: argparse.Namespace) -> Path:
    path = Path(args.artifact).resolve()
    manifest = verify_artifact(path)
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return path


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--root", default=ROOT)
    subcommands = result.add_subparsers(dest="command", required=True)

    contract = subcommands.add_parser("contract")
    contract.add_argument("--output-dir", default=ROOT / "dist/contracts")
    contract.add_argument("--git-sha")
    contract.add_argument("--allow-dirty", action="store_true")
    contract.set_defaults(handler=build_contract_artifact)

    runtime = subcommands.add_parser("runtime")
    runtime.add_argument("--output-dir", default=ROOT / "dist/runtime")
    runtime.add_argument("--api-http", default=ROOT / "target/release/api-http")
    runtime.add_argument(
        "--runtime-dir", default=ROOT / "third_party/runtime/macos-arm64"
    )
    runtime.add_argument(
        "--runtime-manifest", default=ROOT / "third_party/runtime/manifest.json"
    )
    runtime.add_argument(
        "--notices", default=ROOT / "third_party/runtime/THIRD_PARTY_NOTICES.md"
    )
    runtime.add_argument("--platform", default="macos")
    runtime.add_argument("--arch", default="arm64")
    runtime.add_argument("--git-sha")
    runtime.add_argument("--allow-dirty", action="store_true")
    runtime.set_defaults(handler=build_runtime_artifact)

    verify = subcommands.add_parser("verify")
    verify.add_argument("artifact")
    verify.set_defaults(handler=command_verify)
    return result


def main() -> None:
    args = parser().parse_args()
    destination = args.handler(args)
    if args.command != "verify":
        print(destination)


if __name__ == "__main__":
    main()
