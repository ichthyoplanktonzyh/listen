import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import listen_gen_artifacts as artifacts


class ListenGenArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.parent = Path(self.temporary.name)
        self.app = self.parent / "listen-app"
        self.app.mkdir()
        self.original_root = artifacts.ROOT
        self.original_install = artifacts.DEFAULT_INSTALL
        artifacts.ROOT = self.app
        artifacts.DEFAULT_INSTALL = self.app / ".listen-gen"
        self.addCleanup(self._restore_roots)

    def _restore_roots(self):
        artifacts.ROOT = self.original_root
        artifacts.DEFAULT_INSTALL = self.original_install

    def write_bundle(self) -> tuple[Path, Path, Path]:
        release = self.parent / "listen-gen/dist/listen-gen-0.5.0"
        release.mkdir(parents=True)
        artifact_path = release / "listen-gen-0.5.0.pyz"
        artifact_path.write_bytes(b"#!/usr/bin/env python3\nPK\x03\x04bundle")
        artifact_sha = artifacts.sha256(artifact_path)
        manifest = {
            "schema": "listen_gen.release-bundle.v1",
            "source": {"commit": "c" * 40},
            "tool": {"id": "listen-gen", "version": "0.5.0"},
            "artifact": {
                "filename": artifact_path.name,
                "size_bytes": artifact_path.stat().st_size,
                "sha256": artifact_sha,
            },
        }
        manifest_path = release / "listen-gen-0.5.0.release.json"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        lock = {
            "manifest_version": 1,
            "source_git_sha": "c" * 40,
            "release_manifest": {
                "filename": manifest_path.name,
                "sha256": artifacts.sha256(manifest_path),
            },
            "tool": {"id": "listen-gen", "version": "0.5.0"},
            "artifact": {
                "filename": artifact_path.name,
                "size_bytes": artifact_path.stat().st_size,
                "sha256": artifact_sha,
            },
        }
        lock_path = self.app / "listen_gen.lock.json"
        lock_path.write_text(json.dumps(lock), encoding="utf-8")
        return lock_path, manifest_path, artifact_path

    def test_verifies_sibling_bundle_and_stages_exact_files(self):
        lock_path, manifest_path, artifact_path = self.write_bundle()
        bundle = artifacts.verify_bundle(lock_path)
        destination = self.app / "staged"

        artifacts.stage_bundle(bundle, destination)

        self.assertEqual(
            (destination / manifest_path.name).read_bytes(),
            manifest_path.read_bytes(),
        )
        self.assertEqual(
            (destination / artifact_path.name).read_bytes(),
            artifact_path.read_bytes(),
        )

    def test_rejects_a_manifest_hash_mismatch(self):
        lock_path, manifest_path, _ = self.write_bundle()
        manifest_path.write_text("{}", encoding="utf-8")

        with self.assertRaisesRegex(SystemExit, "manifest SHA-256 mismatch"):
            artifacts.verify_bundle(lock_path)

    def test_rejects_a_symlink_manifest(self):
        lock_path, manifest_path, _ = self.write_bundle()
        real = manifest_path.with_name("real.release.json")
        manifest_path.rename(real)
        manifest_path.symlink_to(real)

        with self.assertRaisesRegex(SystemExit, "not a regular file"):
            artifacts.verify_bundle(lock_path, manifest=str(manifest_path))


if __name__ == "__main__":
    unittest.main()
