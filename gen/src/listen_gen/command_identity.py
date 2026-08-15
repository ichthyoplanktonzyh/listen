"""Path-free byte identities for external provider commands."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path


def _sha256_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def _tree_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    files = sorted(item for item in path.rglob("*") if item.is_file())
    if not files:
        raise OSError("provider directory contains no files")
    for item in files:
        digest.update(item.relative_to(path).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(_file_sha256(item).encode("ascii"))
        digest.update(b"\0")
    return f"sha256:{digest.hexdigest()}"


def _argument_identity(argument: str, placeholders: frozenset[str]) -> dict[str, str]:
    if argument in placeholders:
        return {"placeholder": argument}
    path = Path(argument)
    try:
        if path.is_file():
            return {"file_sha256": _file_sha256(path)}
        if path.is_dir():
            return {"tree_sha256": _tree_sha256(path)}
    except OSError:
        raise
    return {"value_sha256": _sha256_bytes(argument.encode("utf-8"))}


def command_identity_sha256(
    executable: str,
    arguments: tuple[str, ...],
    placeholders: frozenset[str],
    timeout_seconds: float,
) -> str:
    """Bind command bytes/config without persisting paths or argument values."""
    resolved = shutil.which(executable)
    executable_path = Path(resolved) if resolved is not None else Path(executable)
    if not executable_path.is_file():
        raise OSError("provider executable is unavailable")
    document = {
        "schema": "listen_gen.command-identity.v1",
        "executable_sha256": _file_sha256(executable_path),
        "arguments": [
            _argument_identity(argument, placeholders) for argument in arguments
        ],
        "timeout_seconds": timeout_seconds,
    }
    encoded = json.dumps(
        document, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")
    return _sha256_bytes(encoded)


def compose_config_sha256(provider_config: str | None, command_identity: str) -> str:
    """Compose provider-declared config with the independently observed command."""
    encoded = json.dumps(
        {
            "schema": "listen_gen.command-provider-config.v1",
            "provider_config_sha256": provider_config,
            "command_identity_sha256": command_identity,
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return _sha256_bytes(encoded)
