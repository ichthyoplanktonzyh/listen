import argparse
import hashlib
import io
import json
import os
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import backend_artifacts as artifacts


def write_archive(path: Path, manifest: dict, files: dict[str, tuple[bytes, int]]):
    manifest = {
        **manifest,
        "files": {
            name: hashlib.sha256(value[0]).hexdigest()
            for name, value in files.items()
        },
    }
    with tarfile.open(path, "w:gz") as archive:
        values = {
            "manifest.json": (
                (json.dumps(manifest, sort_keys=True) + "\n").encode(),
                0o644,
            ),
            **files,
        }
        for name, (data, mode) in values.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = mode
            archive.addfile(info, io.BytesIO(data))


class BackendArtifactTests(unittest.TestCase):
    def test_installs_locked_artifacts_and_syncs_frontend_fixtures(self):
        with tempfile.TemporaryDirectory() as directory:
            frontend = Path(directory) / "listen-app"
            frontend.mkdir()
            original_root = artifacts.ROOT
            artifacts.ROOT = frontend
            try:
                core_sha = "c" * 40
                contract_archive = Path(directory) / "contracts.tar.gz"
                contract_files = {
                    source: (f"{source}\n".encode(), 0o644)
                    for source in artifacts.FIXTURE_MAP
                }
                write_archive(
                    contract_archive,
                    {
                        "artifact_kind": "listen-contracts",
                        "contract_version": "1.0.0",
                        "core_git_sha": core_sha,
                    },
                    contract_files,
                )
                runtime_archive = Path(directory) / "runtime.tar.gz"
                write_archive(
                    runtime_archive,
                    {
                        "artifact_kind": "listen-core-runtime",
                        "runtime_version": "0.7.0",
                        "contract_version": "1.0.0",
                        "core_git_sha": core_sha,
                    },
                    {
                        "bin/api-http": (b"runtime", 0o755),
                        "runtime/whisper-cli": (b"whisper", 0o755),
                        "THIRD_PARTY_NOTICES.md": (b"notices", 0o644),
                    },
                )
                lock_path = frontend / "backend.lock.json"
                lock_path.write_text(
                    json.dumps(
                        {
                            "manifest_version": 1,
                            "core_git_sha": core_sha,
                            "contract": {
                                "version": "1.0.0",
                                "sha256": artifacts.sha256(contract_archive),
                            },
                            "runtime": {
                                "version": "0.7.0",
                                "sha256": artifacts.sha256(runtime_archive),
                            },
                        }
                    ),
                    encoding="utf-8",
                )

                artifacts.command_install(
                    argparse.Namespace(
                        lock=lock_path,
                        contract_archive=str(contract_archive),
                        runtime_archive=str(runtime_archive),
                    )
                )

                self.assertTrue(
                    os.access(
                        frontend / ".backend/runtime/bin/api-http",
                        os.X_OK,
                    )
                )
                for destination in artifacts.FIXTURE_MAP.values():
                    self.assertTrue((frontend / destination).is_file())
            finally:
                artifacts.ROOT = original_root

    def test_rejects_artifact_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "artifact.tar.gz"
            archive.write_bytes(b"wrong")
            with self.assertRaisesRegex(SystemExit, "SHA-256 mismatch"):
                artifacts.verify_download(archive, "0" * 64, "fixture")


if __name__ == "__main__":
    unittest.main()
