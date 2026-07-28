import argparse
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_artifacts as artifacts


class ReleaseArtifactTests(unittest.TestCase):
    def test_contract_archive_is_deterministic_and_self_verifying(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in artifacts.CONTRACT_FILES:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                if relative.endswith("openapi/v1.yaml"):
                    path.write_text(
                        "openapi: 3.1.0\ninfo:\n  title: Fixture\n  version: 1.2.3\n",
                        encoding="utf-8",
                    )
                else:
                    path.write_text("{}\n", encoding="utf-8")
            first_dir = root / "first"
            second_dir = root / "second"
            base = {
                "root": root,
                "git_sha": "a" * 40,
                "allow_dirty": False,
            }
            first = artifacts.build_contract_artifact(
                argparse.Namespace(output_dir=first_dir, **base)
            )
            second = artifacts.build_contract_artifact(
                argparse.Namespace(output_dir=second_dir, **base)
            )

            self.assertEqual(first.read_bytes(), second.read_bytes())
            manifest = artifacts.verify_artifact(first)
            self.assertEqual(manifest["contract_version"], "1.2.3")
            self.assertEqual(manifest["core_git_sha"], "a" * 40)

    def test_runtime_archive_records_every_file_and_executable_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "contracts/openapi").mkdir(parents=True)
            (root / "contracts/openapi/v1.yaml").write_text(
                "openapi: 3.1.0\ninfo:\n  title: Fixture\n  version: 1.0.0\n",
                encoding="utf-8",
            )
            (root / "Cargo.toml").write_text(
                '[workspace.package]\nversion = "0.7.0"\n',
                encoding="utf-8",
            )
            api_http = root / "api-http"
            api_http.write_bytes(b"api")
            os.chmod(api_http, 0o755)
            runtime_dir = root / "runtime-input"
            runtime_dir.mkdir()
            runtime_tool = runtime_dir / "whisper-cli"
            runtime_tool.write_bytes(b"runtime")
            os.chmod(runtime_tool, 0o755)
            runtime_manifest = root / "runtime-manifest.json"
            runtime_manifest.write_text('{"version": 1}\n', encoding="utf-8")
            notices = root / "notices.md"
            notices.write_text("notices\n", encoding="utf-8")
            args = argparse.Namespace(
                root=root,
                output_dir=root / "output",
                api_http=api_http,
                runtime_dir=runtime_dir,
                runtime_manifest=runtime_manifest,
                notices=notices,
                platform="macos",
                arch="arm64",
                git_sha="b" * 40,
                allow_dirty=False,
            )

            artifact = artifacts.build_runtime_artifact(args)
            manifest = artifacts.verify_artifact(artifact)

            self.assertEqual(manifest["runtime_version"], "0.7.0")
            self.assertEqual(manifest["contract_version"], "1.0.0")
            self.assertIn("bin/api-http", manifest["files"])
            self.assertIn("runtime/whisper-cli", manifest["files"])

    def test_verifier_rejects_tampered_member(self):
        entries = [
            artifacts.ArtifactEntry(
                "manifest.json",
                artifacts.canonical_json(
                    {
                        "files": {
                            "payload": artifacts.sha256_bytes(b"expected"),
                        }
                    }
                ),
            ),
            artifacts.ArtifactEntry("payload", b"tampered"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "tampered.tar.gz"
            artifacts.write_deterministic_tar_gz(entries, archive)
            with self.assertRaisesRegex(SystemExit, "hash mismatch"):
                artifacts.verify_artifact(archive)


if __name__ == "__main__":
    unittest.main()
