from __future__ import annotations

import hashlib
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

ROOT = Path(__file__).resolve().parents[1]
MACHINE_EVENT_SCHEMA = "listen_gen.machine-event.v1"
TERMINAL_EVENTS = {"completed", "failed", "cancelled"}


def _env() -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    return env


def run_cli(argv: list[str], timeout: float = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "listen_gen", *argv],
        capture_output=True,
        text=True,
        env=_env(),
        timeout=timeout,
    )


def parse_events(stdout: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in stdout.splitlines() if line]


class MachineEventCliTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    helper = ROOT / "tests" / "fixtures" / "fake_asr_command.py"
    ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
    ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"
    command_media = ROOT / "tests" / "fixtures" / "single-audio-media.json"

    def fixture_argv(
        self, output: Path, *, machine: bool = True
    ) -> list[str]:
        argv = [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(self.fixture),
            "--title", "Machine protocol sample", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
        ]
        if machine:
            argv.append("--machine-events")
        return argv

    def command_argv(
        self,
        output: Path,
        mode: str,
        observed: Path,
        *,
        command_timeout: str = "5",
    ) -> list[str]:
        return [
            "package", "from-media", str(self.command_media),
            "--output", str(output),
            "--provider", "command", "--command", sys.executable,
            "--command-arg", str(self.helper), "--command-arg", mode,
            "--command-arg", "{media}", "--command-arg", str(self.fixture),
            "--command-arg", str(observed),
            "--command-timeout-seconds", command_timeout,
            "--ffprobe-command", str(self.ffprobe),
            "--ffmpeg-command", str(self.ffmpeg),
            "--title", "Machine protocol sample", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            "--machine-events",
        ]

    def assert_terminal_uniqueness(
        self, events: list[dict[str, object]]
    ) -> dict[str, object]:
        terminals = [
            event for event in events if event["event"] in TERMINAL_EVENTS
        ]
        self.assertEqual(len(terminals), 1)
        return terminals[0]

    def test_success_event_order_and_sequence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            completed = run_cli(self.fixture_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                ["protocol", "started", "phase", "phase", "phase", "completed"],
            )
            self.assertEqual(
                [event["phase"] for event in events if event["event"] == "phase"],
                ["validating", "transcribing", "building_package"],
            )
            self.assertEqual(
                [event["sequence"] for event in events],
                list(range(len(events))),
            )
            self.assertEqual(events[0]["event"], "protocol")
            self.assertEqual(events[0]["sequence"], 0)
            self.assertEqual(events[-1]["event"], "completed")
            terminal = self.assert_terminal_uniqueness(events)
            self.assertEqual(terminal["event"], "completed")
            self.assertEqual(completed.stdout, "\n".join(completed.stdout.splitlines()) + "\n")

    def test_command_provider_emits_probing_and_normalization_phases(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "command.listenpkg"
            observed = Path(directory) / "observed.txt"
            completed = run_cli(
                self.command_argv(output, "success", observed)
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                [
                    "protocol", "started",
                    "phase", "phase", "phase", "phase", "phase",
                    "completed",
                ],
            )
            self.assertEqual(
                [event["phase"] for event in events if event["event"] == "phase"],
                [
                    "validating",
                    "probing_media",
                    "normalizing_audio",
                    "transcribing",
                    "building_package",
                ],
            )
            self.assertEqual(
                [event["sequence"] for event in events],
                list(range(len(events))),
            )
            self.assert_terminal_uniqueness(events)

    def test_every_line_is_independent_json_with_no_ordinary_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            completed = run_cli(self.fixture_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            lines = completed.stdout.splitlines()
            self.assertTrue(lines)
            for line in lines:
                event = json.loads(line)
                self.assertEqual(event["schema"], MACHINE_EVENT_SCHEMA)
                self.assertEqual(event["protocol_version"], 1)
                self.assertEqual(event["tool"]["id"], "listen-gen")
                self.assertNotIn("status", event)
                self.assertNotIn("error", event)
            self.assertNotIn("Traceback", completed.stdout)
            self.assertNotIn("INFO", completed.stdout)
            self.assertNotIn("DEBUG", completed.stdout)

    def test_completed_digests_match_final_package_and_original_media(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            completed = run_cli(self.fixture_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            final = self.assert_terminal_uniqueness(events)
            self.assertEqual(final["event"], "completed")
            self.assertEqual(
                final["package_sha256"],
                f"sha256:{hashlib.sha256(output.read_bytes()).hexdigest()}",
            )
            self.assertEqual(
                final["media_fingerprint"],
                f"sha256:{hashlib.sha256(self.media.read_bytes()).hexdigest()}",
            )

    def test_completed_resources_match_final_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            completed = run_cli(self.fixture_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            final = self.assert_terminal_uniqueness(events)
            self.assertEqual(final["event"], "completed")
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                expected = [
                    {
                        "resource_id": entry["resource_id"],
                        "kind": entry["kind"],
                        "review_status": json.loads(
                            archive.read(entry["path"])
                        )["quality"]["review_status"],
                    }
                    for entry in manifest["resources"]
                ]
            self.assertEqual(final["resources"], expected)
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track", "word_timeline"],
            )

    def test_missing_input_fails_with_input_not_found(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "missing.mp4"
            output = Path(directory) / "missing.listenpkg"
            argv = self.fixture_argv(output)
            argv[2] = str(missing)
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                ["protocol", "started", "phase", "failed"],
            )
            self.assertEqual(events[2]["phase"], "validating")
            final = self.assert_terminal_uniqueness(events)
            self.assertEqual(final["event"], "failed")
            self.assertEqual(final["code"], "input_not_found")
            self.assertEqual(final["message"], "Input media is unavailable.")

    def test_invalid_provider_output_is_stable_and_redacted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "invalid.listenpkg"
            observed = Path(directory) / "observed.txt"
            completed = run_cli(
                self.command_argv(output, "invalid-json", observed)
            )
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            final = self.assert_terminal_uniqueness(events)
            self.assertEqual(final["event"], "failed")
            self.assertEqual(final["code"], "provider_output_invalid")
            self.assertNotIn("provider_raw", completed.stdout)
            self.assertNotIn("must-not-leak", completed.stdout)

    def test_provider_nonzero_exit_maps_to_provider_failed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "failed.listenpkg"
            observed = Path(directory) / "observed.txt"
            completed = run_cli(self.command_argv(output, "fail", observed))
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            final = self.assert_terminal_uniqueness(events)
            self.assertEqual(final["event"], "failed")
            self.assertEqual(final["code"], "provider_failed")
            self.assertNotIn("must-not-leak", completed.stdout)

    def test_provider_timeout_maps_to_provider_timeout(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "timeout.listenpkg"
            observed = Path(directory) / "observed.txt"
            completed = run_cli(
                self.command_argv(output, "sleep", observed, command_timeout="0.5")
            )
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            final = self.assert_terminal_uniqueness(events)
            self.assertEqual(final["event"], "failed")
            self.assertEqual(final["code"], "provider_timeout")

    def test_sigint_cancels_cleanly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "cancelled.listenpkg"
            observed = Path(directory) / "observed.json"
            argv = self.command_argv(output, "hang", observed, command_timeout="600")
            process = subprocess.Popen(
                [sys.executable, "-m", "listen_gen", *argv],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=_env(),
            )
            deadline = time.monotonic() + 30
            while not observed.is_file() and time.monotonic() < deadline:
                if process.poll() is not None:
                    break
                time.sleep(0.05)
            self.assertTrue(
                observed.is_file(),
                "fake provider did not start before the deadline",
            )
            process.send_signal(signal.SIGINT)
            stdout, stderr = process.communicate(timeout=60)
            self.assertEqual(process.returncode, 130, stderr)
            events = parse_events(stdout)
            self.assertIn("cancelled", [event["event"] for event in events])
            self.assertNotIn(
                "completed", [event["event"] for event in events]
            )
            self.assertNotIn("failed", [event["event"] for event in events])
            terminal = self.assert_terminal_uniqueness(events)
            self.assertEqual(terminal["event"], "cancelled")
            self.assertFalse(output.exists())
            observation = json.loads(observed.read_text(encoding="utf-8"))
            normalized = Path(observation["media_path"])
            self.assertFalse(normalized.parent.exists())
            provider_pid = int(observation["pid"])
            deadline = time.monotonic() + 10
            alive = True
            while time.monotonic() < deadline:
                try:
                    os.kill(provider_pid, 0)
                except ProcessLookupError:
                    alive = False
                    break
                time.sleep(0.05)
            self.assertFalse(alive, "provider process is still alive")

    def test_ordinary_mode_output_is_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            completed = run_cli(self.fixture_argv(output, machine=False))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["status"], "created")
            self.assertEqual(result["output"], str(output))
            self.assertNotIn("schema", completed.stdout)
            self.assertTrue(output.is_file())


if __name__ == "__main__":
    unittest.main()
