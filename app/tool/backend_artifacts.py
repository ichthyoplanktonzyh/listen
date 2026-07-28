#!/usr/bin/env python3
"""Install and verify the exact listen-core artifacts pinned by backend.lock."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path, PurePosixPath


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOCK = ROOT / "backend.lock.json"
FIXTURE_MAP = {
    "contracts/events/examples.json": "test/fixtures/events/examples.json",
    "testdata/rhythm-frame-qa/fixture-no-phone-rhythm.lltimeline.json": (
        "test/fixtures/rhythm-frame/fixture-no-phone-rhythm.lltimeline.json"
    ),
    "testdata/rhythm-frame-qa/fixture-rhythm.lltimeline.json": (
        "test/fixtures/rhythm-frame/fixture-rhythm.lltimeline.json"
    ),
    "testdata/semantic-task/gold-fixture-v1.json": (
        "test/fixtures/semantic-task/gold-fixture-v1.json"
    ),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def load_lock(path: Path) -> dict[str, object]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("manifest_version") != 1:
        raise SystemExit("unsupported backend.lock manifest_version")
    return value


def verify_download(path: Path, expected: str, label: str) -> None:
    actual = sha256(path)
    if actual != expected:
        raise SystemExit(f"{label} SHA-256 mismatch: expected {expected}, got {actual}")


def fetch(url: str, destination: Path) -> None:
    headers = {}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request) as response, destination.open("wb") as output:
        shutil.copyfileobj(response, output)


def archive_manifest(path: Path) -> dict[str, object]:
    with tarfile.open(path, "r:gz") as archive:
        names = [member.name for member in archive.getmembers()]
        if len(names) != len(set(names)):
            raise SystemExit(f"{path.name} contains duplicate members")
        for name in names:
            parsed = PurePosixPath(name)
            if parsed.is_absolute() or ".." in parsed.parts:
                raise SystemExit(f"{path.name} contains unsafe member {name}")
        manifest_file = archive.extractfile("manifest.json")
        if manifest_file is None:
            raise SystemExit(f"{path.name} has no readable manifest")
        manifest = json.load(manifest_file)
        files = manifest.get("files")
        if not isinstance(files, dict):
            raise SystemExit(f"{path.name} manifest has no files map")
        if set(names) - {"manifest.json"} != set(files):
            raise SystemExit(f"{path.name} contents disagree with its manifest")
        for name, expected in files.items():
            member = archive.extractfile(name)
            if member is None:
                raise SystemExit(f"{path.name} member is unreadable: {name}")
            actual = hashlib.sha256(member.read()).hexdigest()
            if actual != expected:
                raise SystemExit(f"{path.name} member hash mismatch: {name}")
        return manifest


def resolve_artifact(
    explicit: str | None,
    metadata: dict[str, object],
    temporary: Path,
    label: str,
) -> Path:
    if explicit:
        return Path(explicit).resolve()
    url = metadata.get("url")
    if not isinstance(url, str) or not url:
        raise SystemExit(f"{label} artifact path is required because backend.lock has no URL")
    destination = temporary / url.rsplit("/", 1)[-1]
    fetch(url, destination)
    return destination


def extract_atomic(archive_path: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        staging = Path(temporary) / "artifact"
        staging.mkdir()
        with tarfile.open(archive_path, "r:gz") as archive:
            for member in archive.getmembers():
                target = staging / member.name
                parsed = PurePosixPath(member.name)
                if parsed.is_absolute() or ".." in parsed.parts or not member.isfile():
                    raise SystemExit(f"refusing unsafe archive member {member.name}")
                target.parent.mkdir(parents=True, exist_ok=True)
                source = archive.extractfile(member)
                if source is None:
                    raise SystemExit(f"archive member is unreadable: {member.name}")
                target.write_bytes(source.read())
                target.chmod(member.mode)
        replacement = destination.parent / f".{destination.name}.replacement"
        if replacement.exists():
            shutil.rmtree(replacement)
        staging.rename(replacement)
        if destination.exists():
            shutil.rmtree(destination)
        replacement.rename(destination)


def sync_fixtures(contract_root: Path, core_git_sha: str) -> None:
    hashes = {}
    for source_name, destination_name in FIXTURE_MAP.items():
        source = contract_root / source_name
        destination = ROOT / destination_name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        hashes[destination_name] = hashlib.sha256(source.read_bytes()).hexdigest()
    fixture_manifest = {
        "manifest_version": 1,
        "core_git_sha": core_git_sha,
        "files": hashes,
    }
    (ROOT / "test/fixtures/manifest.json").write_text(
        json.dumps(fixture_manifest, ensure_ascii=False, indent=2, sort_keys=True)
        + "\n",
        encoding="utf-8",
    )


def command_install(args: argparse.Namespace) -> None:
    lock = load_lock(Path(args.lock))
    contract_metadata = lock.get("contract")
    runtime_metadata = lock.get("runtime")
    if not isinstance(contract_metadata, dict) or not isinstance(runtime_metadata, dict):
        raise SystemExit("backend.lock must contain contract and runtime objects")
    backend_root = ROOT / ".backend"
    backend_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(dir=backend_root) as temporary:
        temporary_path = Path(temporary)
        contract_archive = resolve_artifact(
            args.contract_archive,
            contract_metadata,
            temporary_path,
            "contract",
        )
        runtime_archive = resolve_artifact(
            args.runtime_archive,
            runtime_metadata,
            temporary_path,
            "runtime",
        )
        verify_download(
            contract_archive, str(contract_metadata["sha256"]), "contract artifact"
        )
        verify_download(
            runtime_archive, str(runtime_metadata["sha256"]), "runtime artifact"
        )
        contract_manifest = archive_manifest(contract_archive)
        runtime_manifest = archive_manifest(runtime_archive)
        expected_sha = lock.get("core_git_sha")
        for label, manifest in (
            ("contract", contract_manifest),
            ("runtime", runtime_manifest),
        ):
            if manifest.get("core_git_sha") != expected_sha:
                raise SystemExit(f"{label} artifact core commit does not match backend.lock")
        if contract_manifest.get("contract_version") != contract_metadata.get("version"):
            raise SystemExit("contract artifact version does not match backend.lock")
        if runtime_manifest.get("runtime_version") != runtime_metadata.get("version"):
            raise SystemExit("runtime artifact version does not match backend.lock")
        if runtime_manifest.get("contract_version") != contract_metadata.get("version"):
            raise SystemExit("runtime and contract artifacts are incompatible")
        extract_atomic(contract_archive, backend_root / "contracts")
        extract_atomic(runtime_archive, backend_root / "runtime")
        sync_fixtures(backend_root / "contracts", str(expected_sha))
    command_verify(argparse.Namespace(lock=args.lock))


def command_verify(args: argparse.Namespace) -> None:
    lock = load_lock(Path(args.lock))
    backend_root = ROOT / ".backend"
    contract_manifest = json.loads(
        (backend_root / "contracts/manifest.json").read_text(encoding="utf-8")
    )
    runtime_manifest = json.loads(
        (backend_root / "runtime/manifest.json").read_text(encoding="utf-8")
    )
    expected_sha = lock.get("core_git_sha")
    if contract_manifest.get("core_git_sha") != expected_sha:
        raise SystemExit("installed contract commit does not match backend.lock")
    if runtime_manifest.get("core_git_sha") != expected_sha:
        raise SystemExit("installed runtime commit does not match backend.lock")
    fixture_manifest = json.loads(
        (ROOT / "test/fixtures/manifest.json").read_text(encoding="utf-8")
    )
    if fixture_manifest.get("core_git_sha") != expected_sha:
        raise SystemExit("frontend fixture commit does not match backend.lock")
    for name, expected in fixture_manifest["files"].items():
        path = ROOT / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit(f"frontend fixture hash mismatch: {name}")
    api_http = backend_root / "runtime/bin/api-http"
    if not api_http.is_file() or not os.access(api_http, os.X_OK):
        raise SystemExit("installed runtime has no executable api-http")
    print(
        f"Verified listen-core {expected_sha}: "
        f"contract {contract_manifest['contract_version']}, "
        f"runtime {runtime_manifest['runtime_version']}"
    )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--lock", default=DEFAULT_LOCK)
    commands = result.add_subparsers(dest="command", required=True)
    install = commands.add_parser("install")
    install.add_argument("--contract-archive")
    install.add_argument("--runtime-archive")
    install.set_defaults(handler=command_install)
    verify = commands.add_parser("verify")
    verify.set_defaults(handler=command_verify)
    return result


def main() -> None:
    args = parser().parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
