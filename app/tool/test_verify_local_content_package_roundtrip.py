import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("verify_local_content_package_roundtrip.sh")
NAME = "local Gen bundle to local Core round trips through capability production, installation, and adoption"
REPO_ROOT = Path(__file__).resolve().parent.parent


def make_repo(path: Path) -> str:
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True)
    subprocess.run(["git", "-C", str(path), "config", "user.email", "t@example.com"], check=True)
    subprocess.run(["git", "-C", str(path), "config", "user.name", "t"], check=True)
    (path / "fixture").write_text("fixture\n")
    subprocess.run(["git", "-C", str(path), "add", "fixture"], check=True)
    subprocess.run(["git", "-C", str(path), "commit", "-q", "-m", "fixture"], check=True)
    return subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()


class ScriptSemanticsTests(unittest.TestCase):
    def run_gate(self, fail_stage=""):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        core, gen = root / "core", root / "gen"
        core_pin, gen_pin = make_repo(core), make_repo(gen)
        cache = root / "pub-cache"
        cache.mkdir()
        runner = root / "runner.py"
        runner.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "stage = sys.argv[1]\n"
            "if stage == os.environ.get('FAIL_STAGE'): sys.exit(23)\n"
            "if stage == 'flutter-test':\n"
            " p = os.environ['VERIFY_ROUNDTRIP_REPORT_PATH']\n"
            f" n = {NAME!r}\n"
            " e = [{'type':'testStart','test':{'id':1,'name':n}}, {'type':'testDone','testID':1,'result':'success','skipped':False}, {'type':'done','success':True}]\n"
            " open(p, 'w').write(''.join(json.dumps(x) + '\\n' for x in e))\n"
        )
        runner.chmod(0o755)
        env = {
            **os.environ,
            "LISTEN_CORE_REPO": str(core),
            "LISTEN_GEN_REPO": str(gen),
            "VERIFY_ROUNDTRIP_STAGE_RUNNER": str(runner),
            "PUB_CACHE": str(cache),
            "FAIL_STAGE": fail_stage,
        }
        return subprocess.run([str(SCRIPT)], capture_output=True, text=True, env=env)

    def test_success_prints_ok_only_after_structured_evidence(self):
        result = self.run_gate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("structured report confirms", result.stdout)
        self.assertIn("verify-roundtrip: OK", result.stdout)

    def test_dependency_failure_is_nonzero_and_never_prints_ok(self):
        result = self.run_gate("dependency-setup")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("verify-roundtrip: OK", result.stdout + result.stderr)

    def test_each_build_or_verify_failure_is_nonzero_and_never_prints_ok(self):
        for stage in ("gen-build", "gen-verify", "core-build"):
            with self.subTest(stage=stage):
                result = self.run_gate(stage)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(
                    "verify-roundtrip: OK", result.stdout + result.stderr
                )

    def test_flutter_runner_failure_is_nonzero_and_never_prints_ok(self):
        result = self.run_gate("flutter-test")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("verify-roundtrip: OK", result.stdout + result.stderr)

    def test_script_builds_the_local_head_without_production_locks(self):
        # The probe gate must run the sibling checkouts at their local HEAD
        # and must never pin production lock identities into its own defaults.
        text = SCRIPT.read_text()
        for lock_name in ("backend.lock.json", "listen_gen.lock.json"):
            self.assertNotIn(lock_name, text)
        self.assertNotIn("5a65b2735325aac18f1eacb736b8d9676adf59a9", text)
        self.assertNotIn("80edcbd7057d4b2e1a7edb8ed9966cd4ecd82e5d", text)
        self.assertIn('--source-commit "$GEN_HEAD"', text)


if __name__ == "__main__":
    unittest.main()
