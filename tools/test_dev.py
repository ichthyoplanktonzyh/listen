"""Regression tests for root snapshot identity and generated Gen lock handoff."""

import hashlib
import json
import os
from pathlib import Path
import sys
import subprocess
import shutil
import tempfile
import unittest


TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))
import dev

APP_TOOL = ROOT / "app" / "tool"
sys.path.insert(0, str(APP_TOOL))
import listen_gen_artifacts


class SourceSnapshotTests(unittest.TestCase):
    def test_snapshot_captures_untracked_working_source_and_changes_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "listen"
            root.mkdir()
            (root / ".gitignore").write_text(
                "/.dev/\n**/.env\n**/.env.*\n!**/.env.example\n"
                "**/.backend/\n**/.listen-gen/\n/gen/models/\n",
                encoding="utf-8",
            )
            (root / "source.py").write_text("value = 1\n", encoding="utf-8")
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            subprocess.run(
                ["git", "-C", str(root), "add", ".gitignore", "source.py"],
                check=True,
            )
            (root / "untracked.md").write_text("working copy\n", encoding="utf-8")
            (root / ".env").write_text("secret=do-not-copy\n", encoding="utf-8")
            app_secret = root / "app" / ".env.local"
            app_secret.parent.mkdir(parents=True, exist_ok=True)
            app_secret.write_text("secret=nested-do-not-copy\n", encoding="utf-8")
            ignored_runtime = root / "app" / ".backend" / "runtime.bin"
            ignored_runtime.parent.mkdir(parents=True, exist_ok=True)
            ignored_runtime.write_bytes(b"large local runtime")
            ignored_bundle = root / "app" / ".listen-gen" / "model.bin"
            ignored_bundle.parent.mkdir(parents=True)
            ignored_bundle.write_bytes(b"local generator data")
            ignored_model = root / "gen" / "models" / "weights.bin"
            ignored_model.parent.mkdir(parents=True)
            ignored_model.write_bytes(b"local model")

            first_snapshot, first_sha = dev.create_source_snapshot(root)

            self.assertEqual((first_snapshot / "source.py").read_text(), "value = 1\n")
            self.assertEqual((first_snapshot / "untracked.md").read_text(), "working copy\n")
            self.assertFalse((first_snapshot / ".env").exists())
            self.assertFalse((first_snapshot / "app" / ".env.local").exists())
            self.assertFalse((first_snapshot / "app" / ".backend").exists())
            self.assertFalse((first_snapshot / "app" / ".listen-gen").exists())
            self.assertFalse((first_snapshot / "gen" / "models").exists())
            self.assertEqual(
                dev._git(first_snapshot, "rev-parse", "HEAD"),
                first_sha,
            )

            (root / "untracked.md").write_text("changed working copy\n", encoding="utf-8")
            second_snapshot, second_sha = dev.create_source_snapshot(root)

            self.assertNotEqual(first_sha, second_sha)
            self.assertEqual(
                (first_snapshot / "untracked.md").read_text(), "working copy\n"
            )
            self.assertEqual(
                (second_snapshot / "untracked.md").read_text(), "changed working copy\n"
            )

    def test_generated_directories_do_not_change_snapshot_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "listen"
            root.mkdir()
            (root / ".gitignore").write_text(
                "/.dev/\n/.dart_tool/\n/target/\n", encoding="utf-8"
            )
            (root / "source.py").write_text("value = 1\n", encoding="utf-8")
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            subprocess.run(
                ["git", "-C", str(root), "add", ".gitignore", "source.py"],
                check=True,
            )
            _, first_sha = dev.create_source_snapshot(root)

            (root / ".dart_tool").mkdir()
            (root / ".dart_tool" / "cache.json").write_text("{}", encoding="utf-8")
            (root / "target").mkdir()
            (root / "target" / "output.bin").write_bytes(b"generated")
            _, second_sha = dev.create_source_snapshot(root)

            self.assertEqual(first_sha, second_sha)

    def test_new_snapshot_does_not_reuse_an_ignored_file_in_an_old_snapshot(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "listen"
            root.mkdir()
            (root / ".gitignore").write_text("/.dev/\n**/.env\n", encoding="utf-8")
            (root / "source.py").write_text("value = 1\n", encoding="utf-8")
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            subprocess.run(
                ["git", "-C", str(root), "add", ".gitignore", "source.py"],
                check=True,
            )
            cached, source_sha = dev.create_source_snapshot(root)
            poisoned = cached / "gen" / "src" / "listen_gen" / ".env"
            poisoned.parent.mkdir(parents=True)
            poisoned.write_text("SECRET=ignored-local-data\n", encoding="utf-8")

            fresh, second_sha = dev.create_source_snapshot(root)

            self.assertEqual(source_sha, second_sha)
            self.assertNotEqual(cached, fresh)
            self.assertTrue(poisoned.exists())
            self.assertEqual((fresh / "source.py").read_text(), "value = 1\n")
            self.assertFalse((fresh / "gen" / "src" / "listen_gen" / ".env").exists())
            self.assertEqual(dev._git(fresh, "rev-parse", "HEAD"), source_sha)
            self.assertEqual(dev._git(fresh, "status", "--porcelain"), "")


class PythonDiscoveryTests(unittest.TestCase):
    def test_external_venv_symlink_is_rejected_without_following_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "listen"
            (root / "gen").mkdir(parents=True)
            external = Path(temporary) / "external-venv"
            external.mkdir()
            (root / "gen" / ".venv").symlink_to(external, target_is_directory=True)

            with self.assertRaisesRegex(dev.DevError, "inside this checkout"):
                dev.discover_gen_python(root)


class ReleaseSourceExportTests(unittest.TestCase):
    def test_release_export_contains_only_the_committed_tree(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "listen"
            root.mkdir()
            (root / ".gitignore").write_text("/.dev/\n**/.env\n", encoding="utf-8")
            (root / "source.py").write_text("committed = True\n", encoding="utf-8")
            subprocess.run(["git", "init", "--quiet", str(root)], check=True)
            subprocess.run(
                ["git", "-C", str(root), "add", ".gitignore", "source.py"],
                check=True,
            )
            commit_env = dict(os.environ)
            commit_env.update(
                {
                    "GIT_AUTHOR_NAME": "Test",
                    "GIT_AUTHOR_EMAIL": "test@example.invalid",
                    "GIT_COMMITTER_NAME": "Test",
                    "GIT_COMMITTER_EMAIL": "test@example.invalid",
                }
            )
            subprocess.run(
                ["git", "-C", str(root), "commit", "-q", "-m", "fixture"],
                env=commit_env,
                check=True,
            )
            source_sha = subprocess.run(
                ["git", "-C", str(root), "rev-parse", "HEAD"],
                check=True,
                capture_output=True,
                text=True,
            ).stdout.strip()
            (root / "ignored.txt").write_text("ignored", encoding="utf-8")
            (root / "gen" / "src" / "listen_gen").mkdir(parents=True)
            (root / "gen" / "src" / "listen_gen" / ".env").write_text(
                "SECRET=not-in-commit", encoding="utf-8"
            )

            export, export_sha = dev._create_committed_source_export(root, source_sha)
            self.addCleanup(shutil.rmtree, export, True)

            self.assertEqual((export / "source.py").read_text(), "committed = True\n")
            self.assertFalse((export / "ignored.txt").exists())
            self.assertFalse((export / "gen" / "src" / "listen_gen" / ".env").exists())
            self.assertEqual(dev._git(export, "rev-parse", "HEAD"), export_sha)
            self.assertEqual(dev._git(export, "status", "--porcelain"), "")


class GeneratedLockTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bundle_dir = self.root / "listen-gen-1.2.3"
        self.bundle_dir.mkdir()
        self.artifact = self.bundle_dir / "listen-gen-1.2.3.pyz"
        self.artifact.write_bytes(b"#!/usr/bin/env python3\nfixture")
        self.manifest = self.bundle_dir / "listen-gen-1.2.3.release.json"
        self.manifest.write_text(
            json.dumps(
                {
                    "schema": "listen_gen.release-bundle.v1",
                    "source": {
                        "repository": "https://github.com/ichthyoplanktonzyh/listen",
                        "commit": "a" * 40,
                    },
                    "tool": {"id": "listen-gen", "version": "1.2.3"},
                    "machine_protocol": {
                        "schema": "listen_gen.machine-event.v2",
                        "version": 2,
                    },
                    "content_package_contract": {
                        "authority": {
                            "repository": "ichthyoplanktonzyh/listen",
                            "path": "core/contracts/content-package/v3",
                        },
                        "release_schema_id": "listen.content-package.release.v3",
                        "package_schema": "listen.content-package.release.v3",
                        "schema_version": 3,
                        "contract_version": "4.1.0",
                        "canonical_sha256": "sha256:" + "b" * 64,
                    },
                    "runtime": {
                        "python_requires": ">=3.11",
                        "provider_requirements": {"fixture": []},
                    },
                    "runtime_identity": {
                        "schema": "listen_gen.runtime-identity.v1",
                        "version": 1,
                        "runtime": {"family": "python", "requires": ">=3.11"},
                        "toolchain": {
                            "schema": "listen_gen.toolchain-identity.v1",
                            "version": 1,
                            "tools": [],
                        },
                    },
                    "artifact": {
                        "filename": self.artifact.name,
                        "format": "python-zipapp",
                        "entrypoint": "__main__.py",
                        "size_bytes": self.artifact.stat().st_size,
                        "sha256": "sha256:" + hashlib.sha256(self.artifact.read_bytes()).hexdigest(),
                    },
                }
            ),
            encoding="utf-8",
        )

    def test_debug_lock_matches_app_artifact_verifier(self):
        lock_path = dev.write_gen_lock(
            self.manifest,
            self.root / "listen_gen.debug.lock.json",
            debug_only=True,
        )

        lock = json.loads(lock_path.read_text(encoding="utf-8"))
        self.assertEqual(lock_path.name, "listen_gen.debug.lock.json")
        self.assertEqual(
            set(lock),
            {
                "manifest_version",
                "repository",
                "source_git_sha",
                "release_manifest",
                "tool",
                "machine_protocol",
                "content_package_contract",
                "runtime",
                "runtime_identity",
                "artifact",
            },
        )
        self.assertEqual(
            lock["content_package_contract"]["authority"]["path"],
            "core/contracts/content-package/v3",
        )
        self.assertEqual(lock["runtime"], {"python_requires": ">=3.11"})
        self.assertEqual(lock["artifact"]["format"], "python-zipapp")
        bundle = listen_gen_artifacts.verify_bundle(
            lock_path,
            manifest=str(self.manifest),
        )
        self.assertEqual(bundle.artifact_path, self.artifact)


if __name__ == "__main__":
    unittest.main()
