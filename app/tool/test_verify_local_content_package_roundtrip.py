import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("verify_local_content_package_roundtrip.sh")
APP_TOOL = SCRIPT.parent
sys.path.insert(0, str(APP_TOOL))
import build_content_package_roundtrip_fixtures

NAMES = [
    "local Gen bundle to local Core round trips through capability production, installation, and adoption",
    "audio and video ASR/subtitle inputs produce adopted media packages through Gen, Core, and App",
    "fragmented video subtitles produce one time-aligned transcript with rich speech analysis",
    "a malformed package fails installation cleanly and pollutes no state",
    "adopting an unknown release fails without changing the composition",
    "a provider failure surfaces as a clean failed attempt and retries without hanging or orphaning the generator",
    "a fixture feed item acquires, keeps, reopens after restart, and never duplicates its material on a second refresh",
    "process lifecycle cancellation reports cancelled promptly",
    "process lifecycle cancellation escalates when the generator ignores soft signals",
    "process lifecycle protocol failure is prompt while cleanup reclaims a hung process",
    "process lifecycle does not execute an artifact swapped after verification",
]


def git(root: Path, *args: str, capture: bool = False) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=capture,
        text=True,
    )
    return result.stdout.strip() if capture else ""


class ScriptSemanticsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = (Path(self.temporary.name) / "listen").resolve()
        for tree in ("app", "core", "gen"):
            (self.root / tree).mkdir(parents=True)
        (self.root / "app/pubspec.yaml").write_text("name: fixture_app\n")
        report_tool = self.root / "app/tool/verify_flutter_test_report.py"
        report_tool.parent.mkdir(parents=True)
        shutil.copyfile(SCRIPT.with_name("verify_flutter_test_report.py"), report_tool)
        (self.root / "core/Cargo.toml").write_text("[workspace]\n")
        (self.root / "gen/pyproject.toml").write_text("[project]\nname='fixture'\n")
        git(self.root, "init", "-q", "-b", "main")
        git(self.root, "config", "user.email", "t@example.com")
        git(self.root, "config", "user.name", "t")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "fixture")

        self.cache = self.root.parent / "pub-cache"
        self.cache.mkdir()
        self.runner = self.root.parent / "runner.py"
        self.runner.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "stage = sys.argv[1]\n"
            "with open(os.environ['RUNNER_CWD_FILE'], 'a') as f:\n"
            " f.write(stage + '|' + os.getcwd() + '|' + ' '.join(sys.argv[2:]) + '\\n')\n"
            "if stage == os.environ.get('FAIL_STAGE'): sys.exit(23)\n"
            "if stage == 'core-contract':\n"
            " out = sys.argv[sys.argv.index('--output-dir') + 1]\n"
            " os.makedirs(out, exist_ok=True)\n"
            " m = {'contract_version': '5.0.0', 'files': {'release.schema.json': 'a' * 64}}\n"
            " open(os.path.join(out, 'listen-contracts-5.0.0.manifest.json'), 'w').write(json.dumps(m))\n"
            "if stage == 'gen-build':\n"
            " out = sys.argv[sys.argv.index('--output-parent') + 1]\n"
            " version = 'listen-gen-0.5.2'\n"
            " release = os.path.join(out, version)\n"
            " os.makedirs(release, exist_ok=True)\n"
            " open(os.path.join(release, version + '.release.json'), 'w').write('{}')\n"
            " open(os.path.join(release, version + '.pyz'), 'wb').write(b'fixture')\n"
            "if stage == 'flutter-test':\n"
            " p = os.environ['VERIFY_ROUNDTRIP_REPORT_PATH']\n"
            " if 'GEN_PYTHON_CAPTURE' in os.environ:\n"
            "  runtime = next((arg.split('=', 1)[1] for arg in sys.argv if arg.startswith('LISTEN_E2E_GEN_PYTHON=')), '')\n"
            "  open(os.environ['GEN_PYTHON_CAPTURE'], 'w').write(runtime)\n"
            f" names = {NAMES!r}\n"
            " events = []\n"
            " for test_id, name in enumerate(names, 1):\n"
            "  events.extend([{'type':'testStart','test':{'id':test_id,'name':name}}, {'type':'testDone','testID':test_id,'result':'success','skipped':False}])\n"
            " events.append({'type':'done','success':True})\n"
            " open(p, 'w').write(''.join(json.dumps(event) + '\\n' for event in events))\n"
        )
        self.runner.chmod(0o755)
        self.cwd_file = self.root.parent / "runner-cwd.txt"

    def test_fixture_builder_emits_hashed_media_and_analysis_files_only(self):
        fixtures = self.root.parent / "media-fixtures"
        fake_ffmpeg = self.root.parent / "ffmpeg"
        fake_ffprobe = self.root.parent / "ffprobe"
        fake_ffmpeg.write_text(
            "#!/bin/sh\nfor arg do output=$arg; done\nprintf 'fixture-video' > \"$output\"\n",
            encoding="utf-8",
        )
        fake_ffprobe.write_text(
            "#!/bin/sh\nfor arg do media=$arg; done\n"
            "case \"$media\" in *.wav) printf 'audio\\n' ;; *) printf 'video\\naudio\\n' ;; esac\n",
            encoding="utf-8",
        )
        fake_ffmpeg.chmod(0o755)
        fake_ffprobe.chmod(0o755)

        build_content_package_roundtrip_fixtures.build(
            fixtures,
            str(fake_ffmpeg),
            str(fake_ffprobe),
        )

        manifest = json.loads((fixtures / "manifest.json").read_text())
        self.assertEqual(
            set(manifest["files"]),
            {
                "full.acoustics.json",
                "full.alignment.json",
                "full.phones.json",
                "full.prosody.json",
                "full.sense-groups.json",
                "sample-media.wav",
                "sample-video.mp4",
                "sample.asr.json",
                "simple.acoustics.json",
                "simple.alignment.json",
                "simple.phones.json",
                "simple.prosody.json",
                "simple.sense-groups.json",
            },
        )
        for name, expected_hash in manifest["files"].items():
            self.assertEqual(
                hashlib.sha256((fixtures / name).read_bytes()).hexdigest(),
                expected_hash,
                name,
            )
        self.assertEqual(
            manifest["media_streams"],
            {"sample-media.wav": ["audio"], "sample-video.mp4": ["video", "audio"]},
        )

    def run_gate(self, fail_stage="", dirty=False, capture_gen_python=False):
        if dirty:
            (self.root / "app/pubspec.yaml").write_text("name: edited_app\n")
            (self.root / "core/uncommitted.rs").write_text("// source edit\n")
            (self.root / "gen/untracked.py").write_text("# source edit\n")
        initial = (
            git(self.root, "rev-parse", "HEAD", capture=True),
            git(self.root, "status", "--porcelain", capture=True),
        )
        capture_path = self.root.parent / "gen-python.txt"
        env = {
            **os.environ,
            "VERIFY_ROUNDTRIP_STAGE_RUNNER": str(self.runner),
            "PUB_CACHE": str(self.cache),
            "LISTEN_GEN_PYTHON": str(self.root / "gen/.venv/bin/python"),
            "FAIL_STAGE": fail_stage,
            "RUNNER_CWD_FILE": str(self.cwd_file),
        }
        if capture_gen_python:
            env["GEN_PYTHON_CAPTURE"] = str(capture_path)
        result = subprocess.run(
            [str(SCRIPT), "--source-root", str(self.root)],
            capture_output=True,
            text=True,
            env=env,
        )
        final = (
            git(self.root, "rev-parse", "HEAD", capture=True),
            git(self.root, "status", "--porcelain", capture=True),
        )
        self.assertEqual(final, initial)
        return result, capture_path

    def stages(self):
        return {
            line.split("|", 2)[0]: tuple(line.split("|", 2)[1:])
            for line in self.cwd_file.read_text().splitlines()
        }

    def test_success_prints_ok_only_after_structured_evidence(self):
        result, _ = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("structured report confirms", result.stdout)
        self.assertIn("verify-roundtrip: OK", result.stdout)

    def test_dependency_and_build_failures_are_nonzero_without_ok(self):
        for stage in ("dependency-setup", "gen-build", "gen-verify", "fixture-build", "core-build", "core-contract"):
            with self.subTest(stage=stage):
                result, _ = self.run_gate(stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("verify-roundtrip: OK", result.stdout + result.stderr)

    def test_flutter_failure_is_nonzero_without_ok(self):
        result, _ = self.run_gate("flutter-test")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("verify-roundtrip: OK", result.stdout + result.stderr)

    def test_every_component_builds_from_one_preserved_root_snapshot(self):
        result, _ = self.run_gate(dirty=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("one snapshot", result.stdout)
        stages = self.stages()
        for stage, subdir in (("core-contract", "core"), ("gen-build", "gen"), ("gen-verify", "gen"), ("dependency-setup", "app"), ("flutter-test", "app")):
            cwd, _ = stages[stage]
            self.assertIn(f"/source/{subdir}", cwd, stage)
        core_cwd, _ = stages["core-contract"]
        gen_cwd, gen_args = stages["gen-build"]
        self.assertEqual(Path(core_cwd).parents[1], Path(gen_cwd).parents[1])
        self.assertIn("--source-commit", gen_args)
        self.assertIn("--manifest-path", stages["core-build"][1])

    def test_flutter_receives_the_selected_gen_python_runtime(self):
        result, captured = self.run_gate(capture_gen_python=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        expected = self.root / "gen/.venv/bin/python"
        self.assertEqual(Path(captured.read_text()), expected)

    def test_clean_source_root_keeps_its_commit_identity(self):
        expected_commit = git(self.root, "rev-parse", "HEAD", capture=True)
        result, _ = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        stages = self.stages()
        self.assertEqual(stages["core-contract"][0], str(self.root / "core"))
        self.assertEqual(stages["gen-build"][0], str(self.root / "gen"))
        self.assertIn(expected_commit, stages["gen-build"][1])

    def test_no_legacy_cross_repository_inputs_remain(self):
        text = SCRIPT.read_text()
        for obsolete in ("LISTEN_CORE_REPO", "LISTEN_GEN_REPO", "listen-core working tree", "listen-gen working tree"):
            self.assertNotIn(obsolete, text)
        self.assertIn("--source-root", text)
        self.assertIn('git -C "$source_root" archive HEAD', text)

    def test_gate_is_media_only_and_runs_generator_cancel_cleanup_checks(self):
        text = SCRIPT.read_text()
        for removed in (
            "EXPECTED_DOCUMENT_TEST",
            "pypdf",
            "--tts-provider",
            "lesson-scanned.pdf",
            "lesson.epub",
        ):
            self.assertNotIn(removed, text)
        self.assertIn("test/listen_gen_process_service_test.dart", text)
        self.assertIn('"$EXPECTED_CANCEL_TEST"', text)
        self.assertIn('"$EXPECTED_CANCEL_ESCALATION_TEST"', text)
        self.assertIn('"$EXPECTED_PROCESS_CLEANUP_TEST"', text)
        self.assertIn('LISTEN_PACKAGE_E2E=1', text)


if __name__ == "__main__":
    unittest.main()
