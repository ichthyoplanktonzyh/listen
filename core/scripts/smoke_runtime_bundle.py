#!/usr/bin/env python3
"""Smoke a packaged listen-core runtime outside the source tree."""

from __future__ import annotations

import argparse
import json
import os
import select
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_artifacts


def read_line_with_timeout(process: subprocess.Popen[str], timeout: float) -> str:
    ready, _, _ = select.select([process.stdout], [], [], timeout)
    if not ready or process.stdout is None:
        raise SystemExit("runtime bundle did not emit a handshake before timeout")
    line = process.stdout.readline()
    if not line:
        raise SystemExit(
            f"runtime bundle exited before handshake with status {process.poll()}"
        )
    return line


def smoke(artifact: Path) -> None:
    manifest = release_artifacts.verify_artifact(artifact)
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        with tarfile.open(artifact, "r:gz") as archive:
            archive.extractall(root, filter="data")
        api_http = root / "bin/api-http"
        api_http.chmod(0o755)
        home = root / "home"
        home.mkdir()
        environment = {
            **os.environ,
            "HOME": str(home),
            "LLPLAYERNEXT_DB": str(home / "runtime-smoke.sqlite"),
        }
        process = subprocess.Popen(
            [str(api_http)],
            env=environment,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        try:
            handshake = json.loads(read_line_with_timeout(process, 30))
            if handshake.get("event") != "api.started":
                raise SystemExit("runtime bundle emitted an invalid handshake event")
            if handshake.get("contract_version") != manifest.get("contract_version"):
                raise SystemExit("runtime handshake contract version disagrees with manifest")
            if handshake.get("runtime_version") != manifest.get("runtime_version"):
                raise SystemExit("runtime handshake version disagrees with manifest")
            address = handshake.get("address")
            if not isinstance(address, str):
                raise SystemExit("runtime handshake address is missing")
            with urllib.request.urlopen(f"http://{address}/v1/health", timeout=10) as response:
                health = json.load(response)
            if health.get("contract_version") != manifest.get("contract_version"):
                raise SystemExit("runtime health contract version disagrees with manifest")
            if health.get("runtime_version") != manifest.get("runtime_version"):
                raise SystemExit("runtime health version disagrees with manifest")
            process.send_signal(signal.SIGINT)
            if process.wait(timeout=20) != 0:
                raise SystemExit("runtime bundle did not stop gracefully")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=10)
    print(
        "Runtime bundle smoke passed: "
        f"{manifest['runtime_version']} / contract {manifest['contract_version']}."
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("artifact")
    args = parser.parse_args()
    smoke(Path(args.artifact).resolve())


if __name__ == "__main__":
    main()
