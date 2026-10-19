import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("verify_local_content_package_roundtrip.sh")
NAMES = [
    "local Gen bundle to local Core round trips through capability production, installation, and adoption",
    "a document material produces listen through the fake TTS provider and its derived audio resolves from the adopted composition through Core",
    "the Gen/Core/App matrix keeps one adopted package shape across document and media families",
    "a video subtitle with fragmented cues lands as one complete sentence with every rich timeline",
    "Core-adopted compositions render honest audio and text surfaces for document, audio, and video",
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
            " m = {'contract_version': '4.0.0', 'files': {'release.schema.json': 'a' * 64}}\n"
            " open(os.path.join(out, 'listen-contracts-4.0.0.manifest.json'), 'w').write(json.dumps(m))\n"
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


if __name__ == "__main__":
    unittest.main()
