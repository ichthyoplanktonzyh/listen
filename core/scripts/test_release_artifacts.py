import argparse
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_artifacts as artifacts


V2_INVENTORY = (
    "contracts/content-package/v2/README.md",
    "contracts/content-package/v2/release.schema.json",
    "contracts/content-package/v2/resource.schema.json",
    "contracts/content-package/v2/delivery.schema.json",
    "contracts/content-package/v2/payload/document-text.v1.schema.json",
    "contracts/content-package/v2/payload/timed-text-track.v2.schema.json",
    "contracts/content-package/v2/payload/translation.v1.schema.json",
    "contracts/content-package/v2/payload/subtitle-text-track.v1.schema.json",
    "contracts/content-package/v2/payload/word-timeline.v1.schema.json",
    "contracts/content-package/v2/payload/phone-timeline.v1.schema.json",
    "contracts/content-package/v2/payload/sense-group-analysis.v1.schema.json",
    "contracts/content-package/v2/payload/word-acoustics.v1.schema.json",
    "contracts/content-package/v2/payload/prosody-analysis.v1.schema.json",
    "contracts/content-package/v2/examples/text-full/release.json",
    "contracts/content-package/v2/examples/text-full/delivery.json",
    "contracts/content-package/v2/examples/text-full/blobs/sha256/49128790cdb73915d8eef1a4c0cc9bb953c2d875e2e366bac8fd2276920f7c6f",
    "contracts/content-package/v2/examples/detached-media/release.json",
    "contracts/content-package/v2/examples/detached-media/delivery.json",
    "contracts/content-package/v2/examples/detached-media/blobs/sha256/29ecf0e48149f3706ded9e9ea048df6635f977b55e20ecb29365e810cf58fbb9",
    "contracts/content-package/v2/examples/hybrid-multilingual/release.json",
    "contracts/content-package/v2/examples/hybrid-multilingual/delivery.json",
    "contracts/content-package/v2/examples/hybrid-multilingual/blobs/sha256/1bee26b045e7c90d616405bb6d173a2db22b6d3f2851d02242e5adccda41cbff",
    "contracts/content-package/v2/examples/hybrid-multilingual/blobs/sha256/a9c749023a1e0b8273c13317c591f974e4df6c9c2fc861865840e138e13d7b28",
)


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

    def test_contract_archive_packages_exact_v2_inventory_bytes(self):
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
                    path.write_bytes(b"fixture-" + relative.encode("utf-8"))

            artifact = artifacts.build_contract_artifact(
                argparse.Namespace(
                    root=root,
                    output_dir=root / "out",
                    git_sha="a" * 40,
                    allow_dirty=False,
                )
            )
            manifest = artifacts.verify_artifact(artifact)
            files = manifest["files"]

            for relative in V2_INVENTORY:
                self.assertIn(relative, files)
                self.assertEqual(
                    files[relative],
                    artifacts.sha256_bytes(b"fixture-" + relative.encode("utf-8")),
                )

            # The v2 contract slice of the manifest is exactly V2_INVENTORY:
            # no v2 path may be added or dropped without updating the
            # inventory.
            v2_files = {
                relative
                for relative in files
                if relative.startswith("contracts/content-package/v2/")
            }
            self.assertEqual(v2_files, set(V2_INVENTORY))

            (root / V2_INVENTORY[0]).unlink()
            with self.assertRaises(FileNotFoundError):
                artifacts.build_contract_artifact(
                    argparse.Namespace(
                        root=root,
                        output_dir=root / "out-missing",
                        git_sha="a" * 40,
                        allow_dirty=False,
                    )
                )

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
