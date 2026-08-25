#!/usr/bin/env python3
"""Verify and stage the exact listen-gen release pinned by the App lock."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_LOCK = ROOT / "listen_gen.lock.json"
DEFAULT_INSTALL = ROOT / ".listen-gen"


class BundleNotFound(Exception):
    pass


@dataclass(frozen=True)
class LockedBundle:
    manifest_path: Path
    artifact_path: Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1024 * 1024):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def load_lock(path: Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SystemExit(f"cannot read listen-gen lock: {error}") from error
    if not isinstance(value, dict) or value.get("manifest_version") != 1:
        raise SystemExit("unsupported listen_gen.lock manifest_version")
    for name in ("release_manifest", "artifact", "tool"):
        if not isinstance(value.get(name), dict):
            raise SystemExit(f"listen_gen.lock must contain {name}")
    return value


def locked_name(section: dict[str, object], key: str) -> str:
    value = section.get(key)
    if (
        not isinstance(value, str)
        or not value
        or Path(value).name != value
        or value in {".", ".."}
    ):
        raise SystemExit(f"listen_gen.lock has an invalid {key}")
    return value


def expected_path(
    lock: dict[str, object],
    manifest: str | None = None,
    bundle_dir: str | None = None,
) -> Path:
    release = lock["release_manifest"]
    assert isinstance(release, dict)
    filename = locked_name(release, "filename")
    if manifest:
        return Path(manifest).expanduser().absolute()
    if bundle_dir:
        return Path(bundle_dir).expanduser().absolute() / filename

    tool = lock["tool"]
    assert isinstance(tool, dict)
    version = tool.get("version")
    if not isinstance(version, str) or not version:
        raise SystemExit("listen_gen.lock has an invalid tool version")
    candidates = [
        DEFAULT_INSTALL / filename,
        ROOT.parent / "listen-gen" / "dist" / f"listen-gen-{version}" / filename,
    ]
    for candidate in candidates:
        if candidate.exists() or candidate.is_symlink():
            return candidate.absolute()
    raise BundleNotFound(
        "pinned listen-gen release is missing; build it in the sibling "
        "listen-gen repository or install it into .listen-gen"
    )


def verify_bundle(
    lock_path: Path = DEFAULT_LOCK,
    *,
    manifest: str | None = None,
    bundle_dir: str | None = None,
) -> LockedBundle:
    lock = load_lock(lock_path)
    release = lock["release_manifest"]
    artifact = lock["artifact"]
    tool = lock["tool"]
    assert isinstance(release, dict)
    assert isinstance(artifact, dict)
    assert isinstance(tool, dict)

    manifest_path = expected_path(lock, manifest, bundle_dir)
    manifest_name = locked_name(release, "filename")
    if manifest_path.name != manifest_name:
        raise SystemExit(
            f"listen-gen manifest filename mismatch: expected {manifest_name}"
        )
    if manifest_path.is_symlink() or not manifest_path.is_file():
        raise SystemExit("listen-gen release manifest is missing or not a regular file")
    expected_manifest_sha = release.get("sha256")
    if sha256(manifest_path) != expected_manifest_sha:
        raise SystemExit("listen-gen release manifest SHA-256 mismatch")

    artifact_name = locked_name(artifact, "filename")
    artifact_path = manifest_path.parent / artifact_name
    if artifact_path.is_symlink() or not artifact_path.is_file():
        raise SystemExit("listen-gen release artifact is missing or not a regular file")
    expected_size = artifact.get("size_bytes")
    if not isinstance(expected_size, int) or artifact_path.stat().st_size != expected_size:
        raise SystemExit("listen-gen release artifact size mismatch")
    if sha256(artifact_path) != artifact.get("sha256"):
        raise SystemExit("listen-gen release artifact SHA-256 mismatch")

    try:
        manifest_value = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SystemExit(f"listen-gen release manifest is invalid: {error}") from error
    if not isinstance(manifest_value, dict):
        raise SystemExit("listen-gen release manifest must be a JSON object")
    manifest_artifact = manifest_value.get("artifact")
    manifest_tool = manifest_value.get("tool")
    manifest_source = manifest_value.get("source")
    if not all(isinstance(value, dict) for value in (
        manifest_artifact,
        manifest_tool,
        manifest_source,
    )):
        raise SystemExit("listen-gen release manifest identity is incomplete")
    assert isinstance(manifest_artifact, dict)
    assert isinstance(manifest_tool, dict)
    assert isinstance(manifest_source, dict)
    expected_identity = (
        manifest_artifact.get("filename") == artifact_name
        and manifest_artifact.get("size_bytes") == expected_size
        and manifest_artifact.get("sha256") == artifact.get("sha256")
        and manifest_tool.get("id") == tool.get("id")
        and manifest_tool.get("version") == tool.get("version")
        and manifest_source.get("commit") == lock.get("source_git_sha")
    )
    if not expected_identity:
        raise SystemExit("listen-gen release manifest identity does not match the lock")
    return LockedBundle(manifest_path=manifest_path, artifact_path=artifact_path)


def stage_bundle(bundle: LockedBundle, destination: Path) -> None:
    destination = destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temporary:
        staging = Path(temporary) / "listen-gen"
        staging.mkdir()
        shutil.copy2(bundle.manifest_path, staging / bundle.manifest_path.name)
        artifact = staging / bundle.artifact_path.name
        shutil.copy2(bundle.artifact_path, artifact)
        artifact.chmod(artifact.stat().st_mode | 0o111)
        replacement = destination.parent / f".{destination.name}.replacement"
        if replacement.exists():
            shutil.rmtree(replacement)
        staging.rename(replacement)
        if destination.exists():
            shutil.rmtree(destination)
        replacement.rename(destination)


def _source_arguments(command: argparse.ArgumentParser) -> None:
    command.add_argument("--manifest")
    command.add_argument("--bundle-dir")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--lock", default=DEFAULT_LOCK)
    commands = result.add_subparsers(dest="command", required=True)

    verify = commands.add_parser("verify")
    _source_arguments(verify)

    install = commands.add_parser("install")
    _source_arguments(install)
    install.add_argument("--destination", default=DEFAULT_INSTALL)

    stage = commands.add_parser("stage")
    _source_arguments(stage)
    stage.add_argument("--destination", required=True)
    stage.add_argument("--optional", action="store_true")
    return result


def main() -> None:
    args = parser().parse_args()
    try:
        bundle = verify_bundle(
            Path(args.lock),
            manifest=args.manifest,
            bundle_dir=args.bundle_dir,
        )
    except BundleNotFound as error:
        if args.command == "stage" and args.optional:
            print(f"Skipping listen-gen staging: {error}")
            return
        raise SystemExit(str(error)) from error

    if args.command in {"install", "stage"}:
        stage_bundle(bundle, Path(args.destination))
        print(f"Staged listen-gen at {Path(args.destination).resolve()}")
    else:
        print(
            f"Verified listen-gen {bundle.manifest_path.name} and "
            f"{bundle.artifact_path.name}"
        )


if __name__ == "__main__":
    main()
