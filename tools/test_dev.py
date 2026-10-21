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
from unittest import mock


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


class PreviewDistributionTests(unittest.TestCase):
    def test_preview_metadata_requires_numeric_bundle_version_and_build_number(self):
        metadata = dev._load_preview_metadata(ROOT)

        self.assertEqual(metadata["version"], "0.7.0-dev.1")
        self.assertEqual(metadata["tag"], "v0.7.0-dev.1")
        self.assertEqual(metadata["bundle_version"], "0.7.0")
        self.assertEqual(metadata["build_number"], "9")
        self.assertEqual(metadata["archive_name"], "Listen-v0.7.0-dev.1-macos-arm64.zip")

    def test_arm64_release_audit_rejects_intel_build_host(self):
        with self.assertRaisesRegex(dev.DevError, "Apple Silicon"):
            dev._validate_macos_arm64_target("x86_64", {}, ())

    def test_arm64_release_audit_rejects_any_x86_only_macho(self):
        binaries = {
            "Contents/MacOS/listen": ["arm64", "x86_64"],
            "Contents/MacOS/api-http": ["arm64"],
            "Contents/Resources/runtime/whisper-cli": ["arm64"],
            "Contents/Resources/runtime/ffmpeg": ["arm64"],
            "Contents/Resources/runtime/ffprobe": ["arm64"],
            "Contents/Frameworks/Unexpected.framework/Unexpected": ["x86_64"],
        }

        with self.assertRaisesRegex(dev.DevError, "Unexpected.framework"):
            dev._validate_macos_arm64_target(
                "arm64",
                binaries,
                (
                    "Contents/MacOS/listen",
                    "Contents/MacOS/api-http",
                    "Contents/Resources/runtime/whisper-cli",
                    "Contents/Resources/runtime/ffmpeg",
                    "Contents/Resources/runtime/ffprobe",
                ),
            )

    def test_arm64_release_audit_requires_critical_executables(self):
        with self.assertRaisesRegex(dev.DevError, "api-http"):
            dev._validate_macos_arm64_target(
                "arm64",
                {"Contents/MacOS/listen": ["arm64"]},
                ("Contents/MacOS/listen", "Contents/MacOS/api-http"),
            )

    def test_otool_minimum_parser_ignores_non_macos_platform(self):
        output = """Load command 1
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform 2
    minos 99.0
       sdk 99.1
Load command 2
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform 1
    minos 13.0
       sdk 26.2
Load command 3
      cmd LC_VERSION_MIN_MACOSX
  cmdsize 16
   version 10.15
      sdk 26.2
"""

        self.assertEqual(dev._parse_macos_minimums(output), [(13, 0), (10, 15)])

    def test_distribution_writes_consistent_manifest_and_checksum_list(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            archive = output / "app" / "listen-macos-arm64.zip"
            archive.parent.mkdir()
            archive.write_bytes(b"test app archive")
            metadata = {
                "version": "0.7.0-dev.1",
                "tag": "v0.7.0-dev.1",
                "channel": "development-preview",
                "platform": "macos-arm64",
                "archive_name": "Listen-v0.7.0-dev.1-macos-arm64.zip",
                "manifest_name": "Listen-v0.7.0-dev.1-macos-arm64.release.json",
            }
            facts = {
                "bundle_id": "com.shadow.listen.desktop",
                "bundle_version": "0.7.0",
                "build_number": "9",
                "minimum_macos": "26.0",
                "mach_o_files": 5,
                "arm64_mach_o_files": 5,
                "tested_macos": "26.6.2",
                "tested_architecture": "arm64",
            }

            distribution = dev._assemble_preview_distribution(
                output,
                archive,
                "a" * 40,
                metadata,
                facts,
            )

            asset = distribution / metadata["archive_name"]
            manifest_path = distribution / metadata["manifest_name"]
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            checksums = (distribution / "SHA256SUMS").read_text(encoding="ascii")
            self.assertEqual(manifest["source"]["commit"], "a" * 40)
            self.assertEqual(manifest["application"]["minimum_macos"], "26.0")
            self.assertEqual(manifest["application"]["build_number"], "9")
            self.assertTrue(manifest["gen_runtime"]["zipapp_bundled"])
            self.assertFalse(manifest["gen_runtime"]["interpreter_bundled"])
            self.assertEqual(manifest["gen_runtime"]["required_dependencies"], [])
            self.assertEqual(
                manifest["gen_runtime"]["optional_extras"],
                ["align", "asr-qwen", "asr-sensevoice"],
            )
            self.assertFalse(
                manifest["verification"]["launch_environment"][
                    "source_checkout_available_to_app"
                ]
            )
            self.assertFalse(manifest["whisper_model"]["bundled"])
            self.assertEqual(manifest["whisper_model"]["id"], "whisper.cpp:base@main")
            self.assertEqual(manifest["whisper_model"]["size_bytes"], 147951465)
            self.assertEqual(
                manifest["whisper_model"]["sha256"],
                "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
            )
            self.assertEqual(
                manifest["whisper_model"]["download_trigger"],
                "running local media transcription when no compatible Whisper model is installed",
            )
            self.assertTrue(
                manifest["whisper_model"]["download_requires_explicit_user_confirmation"]
            )
            self.assertIn(hashlib.sha256(asset.read_bytes()).hexdigest(), checksums)
            self.assertIn(hashlib.sha256(manifest_path.read_bytes()).hexdigest(), checksums)


class ReleasePipelineTests(unittest.TestCase):
    def test_each_app_release_script_passes_an_individual_bash_syntax_check(self):
        app = ROOT / "app"
        for name in ("build-macos-release.sh", "verify-macos-release.sh"):
            with self.subTest(script=name):
                result = subprocess.run(
                    ["bash", "-n", str(app / "tool" / name)],
                    check=False,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_verifier_preflight_rejects_deferred_shell_parse_errors_before_trap(self):
        source = (ROOT / "app" / "tool" / "verify-macos-release.sh").read_text(
            encoding="utf-8"
        )
        malformed_suffix = """\nif [[ -n x ]]; then
  python3 - <<'PY' ||
    false
print('unreachable')
PY
fi
"""
        with tempfile.TemporaryDirectory() as temporary:
            script_path = Path(temporary) / "app" / "tool" / "verify-macos-release.sh"
            script_path.parent.mkdir(parents=True)
            script_path.write_text(source + malformed_suffix, encoding="utf-8")
            script_path.chmod(0o755)
            result = subprocess.run(
                [str(script_path)],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("syntax error near unexpected token", result.stderr)
        self.assertIn("Refusing to run the macOS release verifier", result.stderr)

    def test_failed_packaged_verifier_prevents_distribution_assembly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "app"
            tool = app / "tool"
            tool.mkdir(parents=True)
            build = tool / "build-macos-release.sh"
            verify = tool / "verify-macos-release.sh"
            build.write_text("#!/bin/bash\nexit 0\n", encoding="utf-8")
            verify.write_text(
                "#!/bin/bash\necho 'simulated packaged smoke failure' >&2\nexit 2\n",
                encoding="utf-8",
            )
            build.chmod(0o755)
            verify.chmod(0o755)
            output = root / "release-output"
            output.mkdir()

            with mock.patch.object(dev, "_assemble_preview_distribution") as assemble:
                with self.assertRaisesRegex(dev.DevError, "exit status 2"):
                    dev._build_verify_and_assemble_preview(
                        app,
                        {},
                        output,
                        "a" * 40,
                        {},
                    )

            assemble.assert_not_called()
            self.assertFalse((output / "distribution").exists())


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

    def test_release_environment_does_not_leak_verification_only_mode(self):
        environment = dev._app_release_environment(
            {"LLPLAYERNEXT_VERIFY_GEN_BUNDLE": "1", "PATH": "/bin"},
            flutter="/tools/flutter",
            backend_lock=Path("/release/backend.lock.json"),
            gen_lock=Path("/release/listen_gen.lock.json"),
            gen_manifest=Path("/release/listen-gen.release.json"),
            output=Path("/release/app"),
            metadata={
                "version": "0.7.0-dev.1",
                "channel": "development-preview",
                "minimum_macos": "26.0",
                "build_number": "9",
            },
            source_commit="a" * 40,
        )

        self.assertNotIn("LLPLAYERNEXT_VERIFY_GEN_BUNDLE", environment)
        self.assertEqual(
            environment["LISTEN_GEN_RELEASE_MANIFEST"],
            "/release/listen-gen.release.json",
        )
        self.assertEqual(environment["PATH"], "/bin")
        self.assertEqual(environment["LISTEN_SOURCE_COMMIT"], "a" * 40)
        self.assertEqual(environment["LISTEN_RELEASE_MINIMUM_MACOS_VERSION"], "26.0")
        self.assertEqual(environment["LISTEN_RELEASE_BUILD_NUMBER"], "9")


if __name__ == "__main__":
    unittest.main()
