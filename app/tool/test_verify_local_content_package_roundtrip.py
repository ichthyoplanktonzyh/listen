import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("verify_local_content_package_roundtrip.sh")
NAME = "pinned Gen 0.5.0 bundle to Core 4.0 round trips through capability production, installation, and adoption"
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
            "VERIFY_ROUNDTRIP_CORE_PIN": core_pin,
            "VERIFY_ROUNDTRIP_GEN_PIN": gen_pin,
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


class DefaultPinTests(unittest.TestCase):
    # One declaration line per pin, with the fallback environment variable and
    # a full 40-hex-digit default. Anything shaped differently is unexpected.
    PIN_DECL = re.compile(
        r'^readonly\s+(?P<const>[A-Z0-9_]+)='
        r'"\$\{VERIFY_ROUNDTRIP_(?P<env>[A-Z0-9_]+):-(?P<pin>[0-9a-f]{40})\}"$'
    )
    PIN_ASSIGN = re.compile(r"\b(?:CORE_PIN|GEN_PIN)\s*=")
    PIN_FALLBACK = re.compile(r"VERIFY_ROUNDTRIP_(?:CORE|GEN)_PIN")

    def setUp(self):
        self.script_text = SCRIPT.read_text()
        self.script_lines = self.script_text.splitlines()

    def declared_default_pins(self):
        """Parse the declared default pins strictly; fail on any anomaly."""
        declared = {}
        for lineno, line in enumerate(self.script_lines, 1):
            match = self.PIN_DECL.match(line)
            if match is None:
                # Anything else that assigns a pin constant or names its
                # fallback variable is an unexpected second source of truth.
                if self.PIN_ASSIGN.search(line) or self.PIN_FALLBACK.search(line):
                    self.fail(
                        f"line {lineno}: unexpected pin declaration or fallback "
                        f"reference: {line.strip()!r}"
                    )
                continue
            const = match.group("const")
            if const in declared:
                self.fail(
                    f"line {lineno}: duplicate default declaration for {const} "
                    f"(already declared on line {declared[const][2]})"
                )
            declared[const] = (match.group("env"), match.group("pin"), lineno)
        self.assertEqual(
            sorted(declared),
            ["CORE_PIN", "GEN_PIN"],
            "script must declare exactly the CORE_PIN and GEN_PIN defaults "
            f"with their VERIFY_ROUNDTRIP_* fallbacks; got {sorted(declared)}",
        )
        pins = {}
        for const, (env, pin, lineno) in declared.items():
            self.assertEqual(
                env,
                const,
                f"line {lineno}: {const} fallback reads "
                f"$VERIFY_ROUNDTRIP_{env}, expected $VERIFY_ROUNDTRIP_{const}",
            )
            pins[const] = pin
        return pins

    def test_removed_print_pins_bypass_hook_stays_absent(self):
        # The VERIFY_ROUNDTRIP_PRINT_PINS early exit was removed: an
        # accidentally-set environment variable must never turn the production
        # gate into a no-op success. The defaults are proven against the locks
        # by text parsing above, not by executing a bypass path.
        self.assertNotIn("VERIFY_ROUNDTRIP_PRINT_PINS", self.script_text)

    def test_default_core_pin_matches_backend_lock(self):
        pins = self.declared_default_pins()
        lock = json.loads((REPO_ROOT / "backend.lock.json").read_text())
        self.assertEqual(pins["CORE_PIN"], lock["core_git_sha"])

    def test_default_gen_pin_matches_gen_lock(self):
        pins = self.declared_default_pins()
        lock = json.loads((REPO_ROOT / "listen_gen.lock.json").read_text())
        self.assertEqual(pins["GEN_PIN"], lock["source_git_sha"])


if __name__ == "__main__":
    unittest.main()
