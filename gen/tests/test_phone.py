from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

from listen_gen.phone import (
    CommandPhoneAdapter,
    FixturePhoneAdapter,
    PhoneRequest,
    Wav2Vec2CtcPhoneAdapter,
    _anchor_phones,
    _parse_result,
    run_phone,
)
from listen_gen.protocol import RichStageFailure, protocol_capabilities
from listen_gen.rich import RichWord

ROOT = Path(__file__).resolve().parents[1]


def assert_process_reaped(test: unittest.TestCase, pid: int) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    test.fail(f"phone provider process {pid} is still alive")


class PhoneUnitTests(unittest.TestCase):
    def test_cancellation_is_never_degraded(self) -> None:
        class CancellingAnalyzer:
            def analyze(self, request: PhoneRequest):
                raise KeyboardInterrupt

        with self.assertRaises(KeyboardInterrupt):
            run_phone(
                analyzer=CancellingAnalyzer(),
                audio_path=Path("audio.wav"),
                words=(RichWord(0, 0, 0, 100, "s1"),),
                word_timeline=None,  # type: ignore[arg-type]
                media_fingerprint="sha256:" + "0" * 64,
                created_at_ms=0,
            )

    def test_fixture_is_audio_evidence_and_anchors_every_phone(self) -> None:
        adapter = FixturePhoneAdapter(ROOT / "tests/fixtures/phone-result.json")
        words = (
            RichWord(0, 0, 100, 500, "s1"),
            RichWord(0, 3, 550, 1100, "s1"),
            RichWord(1, 0, 1300, 1600, "s2"),
            RichWord(1, 2, 1650, 2050, "s2"),
        )
        result = adapter.analyze(PhoneRequest(Path("unused.wav"), words))
        anchored = _anchor_phones(result, words)
        self.assertEqual(len(anchored), 10)
        self.assertTrue(all(item["word_ref"]["sentence_id"] for item in anchored))
        self.assertEqual(anchored[0]["word_ref"], {"sentence_id": "s1", "token_index": 0})
        self.assertEqual(anchored[-1]["word_ref"], {"sentence_id": "s2", "token_index": 2})

    def test_unanchored_phone_abstains(self) -> None:
        result = _parse_result({
            "schema": "listen_gen.phone-result.v1",
            "provider": {"id": "p", "version": "1"},
            "phone_set": "ipa",
            "phones": [{"symbol": "x", "start_ms": 900, "end_ms": 950}],
        })
        with self.assertRaises(RichStageFailure) as caught:
            _anchor_phones(result, (RichWord(0, 0, 0, 100, "s1"),))
        self.assertEqual(caught.exception.code, "phone_qualification_failed")

    def test_malformed_output_is_redacted(self) -> None:
        for raw in ([], {"schema": "private/path", "phones": []}):
            with self.assertRaises(RichStageFailure) as caught:
                _parse_result(raw)
            self.assertEqual(caught.exception.code, "phone_output_invalid")
            self.assertNotIn("private", str(caught.exception))

    def test_capabilities_advertise_optional_audio_backed_phone(self) -> None:
        capabilities = protocol_capabilities()
        self.assertEqual(capabilities["phone"]["production"], "optional_audio_backed")
        self.assertEqual(capabilities["phone"]["unselected"], "abstain")
        self.assertFalse(capabilities["phone"]["text_derived"])
        self.assertIn("wav2vec2-ctc", capabilities["rich_resources"]["phone"]["adapters"])

    def test_command_failure_is_redacted(self) -> None:
        helper = ROOT / "tests/fixtures/fake_phone_command.py"
        adapter = CommandPhoneAdapter(
            sys.executable, [str(helper), "{media}"], 2.0
        )
        previous = os.environ.get("LISTEN_GEN_TEST_PHONE_MODE")
        os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = "fail"
        try:
            with self.assertRaises(RichStageFailure) as caught:
                adapter.analyze(PhoneRequest(ROOT / "tests/fixtures/sample-media.wav", ()))
        finally:
            if previous is None:
                os.environ.pop("LISTEN_GEN_TEST_PHONE_MODE", None)
            else:
                os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = previous
        self.assertEqual(caught.exception.code, "phone_failed")
        self.assertNotIn("secret", str(caught.exception))

    def test_command_provenance_binds_bytes_and_detects_mutation(self) -> None:
        from listen_gen.command_identity import (
            command_identity_sha256,
            compose_config_sha256,
        )

        helper = ROOT / "tests/fixtures/fake_phone_command.py"
        adapter = CommandPhoneAdapter(
            sys.executable, [str(helper), "{media}"], 2.0
        )
        result = adapter.analyze(
            PhoneRequest(ROOT / "tests/fixtures/sample-media.wav", ())
        )
        identity = command_identity_sha256(
            sys.executable, (str(helper), "{media}"),
            frozenset({"{media}"}), 2.0,
        )
        self.assertEqual(
            result.config_sha256,
            compose_config_sha256("sha256:" + "c" * 64, identity),
        )

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mutable = root / "provider.py"
            mutable.write_bytes(helper.read_bytes())
            (root / "phone-result.json").write_bytes(
                (ROOT / "tests/fixtures/phone-result.json").read_bytes()
            )
            mutating = CommandPhoneAdapter(
                sys.executable, [str(mutable), "{media}"], 2.0
            )
            previous = os.environ.get("LISTEN_GEN_TEST_PHONE_MODE")
            os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = "mutate-self"
            try:
                with self.assertRaises(RichStageFailure) as caught:
                    mutating.analyze(
                        PhoneRequest(ROOT / "tests/fixtures/sample-media.wav", ())
                    )
            finally:
                if previous is None:
                    os.environ.pop("LISTEN_GEN_TEST_PHONE_MODE", None)
                else:
                    os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = previous
            self.assertEqual(caught.exception.code, "phone_failed")

    def test_command_timeout_is_typed(self) -> None:
        helper = ROOT / "tests/fixtures/fake_phone_command.py"
        adapter = CommandPhoneAdapter(
            sys.executable, [str(helper), "{media}"], 0.1
        )
        previous = os.environ.get("LISTEN_GEN_TEST_PHONE_MODE")
        previous_observed = os.environ.get("LISTEN_GEN_TEST_PHONE_OBSERVED")
        with tempfile.TemporaryDirectory() as directory:
            observed = Path(directory) / "observed.json"
            os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = "hang"
            os.environ["LISTEN_GEN_TEST_PHONE_OBSERVED"] = str(observed)
            try:
                with self.assertRaises(RichStageFailure) as caught:
                    adapter.analyze(PhoneRequest(ROOT / "tests/fixtures/sample-media.wav", ()))
            finally:
                if previous is None:
                    os.environ.pop("LISTEN_GEN_TEST_PHONE_MODE", None)
                else:
                    os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = previous
                if previous_observed is None:
                    os.environ.pop("LISTEN_GEN_TEST_PHONE_OBSERVED", None)
                else:
                    os.environ["LISTEN_GEN_TEST_PHONE_OBSERVED"] = previous_observed
            pid = int(json.loads(observed.read_text(encoding="utf-8"))["pid"])
            assert_process_reaped(self, pid)
        self.assertEqual(caught.exception.code, "phone_timeout")

    def test_wav2vec2_adapter_binds_bytes_and_detects_mutation(self) -> None:
        helper = ROOT / "tests/fixtures/fake_phone_command.py"
        with tempfile.TemporaryDirectory() as directory:
            model = Path(directory) / "model"
            model.mkdir()
            (model / "weights.bin").write_bytes(b"stable-model")
            adapter = Wav2Vec2CtcPhoneAdapter(
                Path(sys.executable), helper, model, "fixture-ctc", "r1", 2.0
            )
            words = (RichWord(0, 0, 100, 500, "s1"),)
            old_mode = os.environ.get("LISTEN_GEN_TEST_PHONE_MODE")
            old_mutate = os.environ.get("LISTEN_GEN_TEST_PHONE_MUTATE")
            os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = "core"
            try:
                result = adapter.analyze(PhoneRequest(Path("audio.wav"), words))
                self.assertEqual(result.provider_id, "wav2vec2-ctc-phoneme")
                self.assertRegex(result.config_sha256 or "", r"^sha256:[0-9a-f]{64}$")
                self.assertNotIn(str(model), result.config_sha256 or "")
                os.environ["LISTEN_GEN_TEST_PHONE_MUTATE"] = "1"
                with self.assertRaises(RichStageFailure) as caught:
                    adapter.analyze(PhoneRequest(Path("audio.wav"), words))
                self.assertEqual(caught.exception.code, "phone_failed")
            finally:
                if old_mode is None:
                    os.environ.pop("LISTEN_GEN_TEST_PHONE_MODE", None)
                else:
                    os.environ["LISTEN_GEN_TEST_PHONE_MODE"] = old_mode
                if old_mutate is None:
                    os.environ.pop("LISTEN_GEN_TEST_PHONE_MUTATE", None)
                else:
                    os.environ["LISTEN_GEN_TEST_PHONE_MUTATE"] = old_mutate


class PhonePackageTests(unittest.TestCase):
    def _argv(self, output: Path) -> list[str]:
        return [
            sys.executable, "-m", "listen_gen", "package", "from-media",
            "tests/fixtures/sample-media.wav", "--output", str(output),
            "--provider", "fixture", "--fixture", "tests/fixtures/sample.asr.json",
            "--aligner", "fixture", "--alignment-fixture", "tests/fixtures/alignment-result.json",
            "--phone", "fixture", "--phone-fixture", "tests/fixtures/phone-result.json",
            "--title", "Phone fixture", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1785542400000",
        ]

    def _generate(self, output: Path) -> dict:
        env = dict(os.environ)
        env["PYTHONPATH"] = str(ROOT / "src")
        completed = subprocess.run(self._argv(output), cwd=ROOT, env=env, capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        return json.loads(completed.stdout)

    def test_package_phone_has_exact_word_dependency_and_refs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "phone.listenpkg"
            result = self._generate(output)
            self.assertEqual(result["rich_resources"]["phone"]["status"], "produced")
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                entries = {entry["kind"]: entry for entry in manifest["resources"]}
                phone = json.loads(archive.read(entries["phone_timeline"]["path"]))
            self.assertEqual(phone["dependencies"], [{
                "resource_id": entries["word_timeline"]["resource_id"],
                "kind": "word_timeline",
            }])
            self.assertEqual(phone["payload"]["precision"], "detected")
            self.assertTrue(all(item["word_ref"] is not None for item in phone["payload"]["phones"]))
            self.assertEqual(phone["provenance"]["tool"], {"id": "listen-gen.phone", "version": "0.4.0"})

    def test_package_is_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory) / "a.listenpkg", Path(directory) / "b.listenpkg"
            self._generate(first)
            self._generate(second)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_machine_events_report_phone_phase_and_outcome(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "phone.listenpkg"
            env = dict(os.environ)
            env["PYTHONPATH"] = str(ROOT / "src")
            completed = subprocess.run(
                [*self._argv(output), "--machine-events"], cwd=ROOT, env=env,
                capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = [json.loads(line) for line in completed.stdout.splitlines()]
            phases = [event.get("phase") for event in events if event["event"] == "phase"]
            self.assertIn("analyzing_phones", phases)
            self.assertEqual(events[-1]["rich_resources"]["phone"], {
                "status": "produced", "warnings": [],
            })

    def test_core_inspector_accepts_phone_fixture(self) -> None:
        checkout = os.environ.get("LISTEN_CORE_CHECKOUT")
        if checkout is None:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        core = Path(checkout)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "phone.listenpkg"
            self._generate(output)
            probe = Path(directory) / "probe"
            (probe / "src").mkdir(parents=True)
            (probe / "Cargo.toml").write_text(
                "[package]\nname = \"listen-gen-phone-probe\"\nversion = \"0.0.0\"\nedition = \"2024\"\n"
                f"[dependencies]\ncontent-package = {{ path = {json.dumps(str(core / 'crates/content-package'))} }}\n",
                encoding="utf-8",
            )
            (probe / "src/main.rs").write_text(
                "fn main() { content_package::inspect_path(std::env::args_os().nth(1).unwrap()).unwrap(); }\n",
                encoding="utf-8",
            )
            subprocess.run(
                ["cargo", "run", "-q", "--manifest-path", str(probe / "Cargo.toml"), "--", str(output)],
                cwd=probe, check=True, capture_output=True, text=True,
            )

    def test_sigterm_during_phone_reaps_provider_and_preserves_output(self) -> None:
        helper = ROOT / "tests/fixtures/fake_phone_command.py"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observed = root / "observed.json"
            output = root / "cancelled.listenpkg"
            output.write_bytes(b"sentinel-must-survive")
            argv = [
                sys.executable, "-m", "listen_gen", "package", "from-media",
                str(ROOT / "tests/fixtures/single-audio-media.json"),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(ROOT / "tests/fixtures/sample.asr.json"),
                "--aligner", "fixture", "--alignment-fixture", str(ROOT / "tests/fixtures/alignment-result.json"),
                "--phone", "command", "--phone-command", sys.executable,
                "--phone-command-arg", str(helper),
                "--phone-command-arg", "{media}",
                "--phone-command-timeout-seconds", "600",
                "--ffprobe-command", str(ROOT / "tests/fixtures/fake_ffprobe.py"),
                "--ffmpeg-command", str(ROOT / "tests/fixtures/fake_ffmpeg.py"),
                "--title", "Phone cancellation", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                "--machine-events",
            ]
            env = dict(os.environ)
            env["PYTHONPATH"] = str(ROOT / "src")
            env["LISTEN_GEN_TEST_PHONE_MODE"] = "hang"
            env["LISTEN_GEN_TEST_PHONE_OBSERVED"] = str(observed)
            process = subprocess.Popen(
                argv, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                stderr=subprocess.PIPE, text=True,
            )
            deadline = time.monotonic() + 30
            while not observed.is_file() and time.monotonic() < deadline:
                if process.poll() is not None:
                    break
                time.sleep(0.05)
            self.assertTrue(observed.is_file(), "phone stage did not start")
            pid = int(json.loads(observed.read_text(encoding="utf-8"))["pid"])
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=60)
            self.assertEqual(process.returncode, 130, stderr)
            terminal = [
                json.loads(line)["event"] for line in stdout.splitlines()
                if json.loads(line)["event"] in {"completed", "failed", "cancelled"}
            ]
            self.assertEqual(terminal, ["cancelled"])
            self.assertEqual(output.read_bytes(), b"sentinel-must-survive")
            assert_process_reaped(self, pid)


if __name__ == "__main__":
    unittest.main()
