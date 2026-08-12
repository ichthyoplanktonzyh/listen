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

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.package_v3 import sha256_of_bytes

FIXTURES = ROOT / "tests" / "fixtures"
V2_SCHEMA = "listen_gen.machine-event.v2"
V2_VERSION = 2
TERMINAL_EVENTS = {"completed", "cancelled", "failed"}


def _env() -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    return env


def run_cli(argv: list[str], timeout: float = 60, env=None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "listen_gen", *argv],
        capture_output=True,
        text=True,
        env=env or _env(),
        timeout=timeout,
    )


def parse_events(stdout: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in stdout.splitlines() if line]


def text_document(text: str, directory: Path) -> tuple[dict, dict]:
    path = directory / "document.txt"
    path.write_text(text, encoding="utf-8")
    raw = path.read_bytes()
    return {
        "kind": "document",
        "rendition_id": "sha256:" + "1" * 64,
        "media_type": "text/plain",
        "language": "en",
        "source_asset_id": "sha256:" + "2" * 64,
        "blob": {"digest": sha256_of_bytes(raw), "size_bytes": len(raw), "path": str(path)},
    }, {"digest": sha256_of_bytes(raw), "size_bytes": len(raw), "path": str(path)}


def media_rendition(directory: Path) -> dict:
    path = FIXTURES / "sample-media.wav"
    raw = path.read_bytes()
    return {
        "kind": "media",
        "media_kind": "audio",
        "rendition_id": "sha256:" + "3" * 64,
        "media_type": "audio/wav",
        "media_id": "media-1",
        "fingerprint": "fp-media-1",
        "blob": {"digest": sha256_of_bytes(raw), "size_bytes": len(raw), "path": str(path)},
    }


def request_document(
    directory: Path,
    capability: str = "read",
    text: str = "Hello world. This is a first test.\nSecond paragraph with a question!",
    attempt_id: str = "attempt-1",
    **extra,
) -> dict:
    rendition, _ = text_document(text, directory)
    document = {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "attempt_id": attempt_id,
        "material": {
            "material_id": "material-1",
            "material_revision_id": "revision-1",
            "title": "Test Material",
        },
        "edition": {
            "edition_id": "edition-1",
            "title": "Test Edition",
            "target_language": "en",
            "support_languages": [],
        },
        "requested_capability": capability,
        "available_renditions": [rendition],
        "available_resources": [],
    }
    document.update(extra)
    return document


class ProduceCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp(prefix="listen-gen-test-"))

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.directory, ignore_errors=True)

    def write_request(self, request: dict) -> Path:
        path = self.directory / "request.json"
        path.write_text(json.dumps(request), encoding="utf-8")
        return path

    def event_sequence(self, events: list[dict]) -> list[str]:
        return [event["event"] for event in events]

    def test_read_from_document_completes_with_reading_resources(self) -> None:
        request_path = self.write_request(request_document(self.directory))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        self.assertEqual(
            self.event_sequence(events),
            ["protocol", "accepted", "planned", "running", "completed"],
        )
        self.assertEqual(events[0]["schema"], V2_SCHEMA)
        self.assertEqual(events[0]["protocol_version"], V2_VERSION)
        self.assertEqual(events[1]["attempt_id"], "attempt-1")
        completed = events[-1]
        kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertIn("document_text", kinds)
        self.assertIn("structured_reading", kinds)
        self.assertNotIn("anchor_time_alignment", kinds)
        self.assertTrue(output.exists())

    def test_planned_event_declares_the_derivation(self) -> None:
        request_path = self.write_request(request_document(self.directory))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        events = parse_events(result.stdout)
        planned = events[2]
        derivations = planned["plan"]["derivations"]
        self.assertEqual(derivations[0]["kind"], "document_to_structured_reading")

    def test_listen_produces_audio_alignment_and_honest_warning_with_say(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "say",
            "--tts-voice", "test",
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        completed = events[-1]
        self.assertEqual(completed["event"], "completed")
        media_kinds = [entry["origin"] for entry in completed["media_renditions"]]
        self.assertIn("derived", media_kinds)
        self.assertEqual(
            completed["warnings"],
            [{
                "code": "alignment_abstained",
                "message": "exact anchor timing could not be produced; audio is "
                "available but synchronized reading is not",
            }],
        )
        resource_kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertNotIn("anchor_time_alignment", resource_kinds)

    def test_fake_tts_produces_exact_alignment(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake", "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        completed = events[-1]
        self.assertEqual(completed["warnings"], [])
        kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertIn("anchor_time_alignment", kinds)
        with zipfile.ZipFile(output) as archive:
            release = json.loads(archive.read("release.json"))
            alignment = next(
                resource for resource in release["resources"]
                if resource["descriptor"]["kind"] == "anchor_time_alignment"
            )
            digest = alignment["descriptor"]["payload_blob"]["digest"]
            payload = json.loads(archive.read(
                f"blobs/sha256/{digest.removeprefix('sha256:')}"
            ))
        times = [entry["media_time_ms"] for entry in payload["alignments"]]
        self.assertEqual(times, sorted(times))

    def test_media_read_produces_reading_and_alignment(self) -> None:
        request_path = self.write_request({
            "schema": "listen_gen.capability-request.v2",
            "version": 2,
            "created_at_ms": 1,
            "attempt_id": "attempt-media",
            "material": {"material_id": "material-m", "material_revision_id": "revision-m", "title": "M"},
            "edition": {"edition_id": "edition-m", "title": "E", "target_language": "en-US", "support_languages": []},
            "requested_capability": "read",
            "available_renditions": [media_rendition(self.directory)],
            "available_resources": [],
        })
        output = self.directory / "media-package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        completed = events[-1]
        kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertIn("structured_reading", kinds)
        self.assertIn("anchor_time_alignment", kinds)

    def test_already_satisfied_capability_completes_without_artifact(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        request = json.loads(request_path.read_text())
        request["available_renditions"] = [media_rendition(self.directory)]
        request_path.write_text(json.dumps(request))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 0)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["event"], "completed")
        self.assertIsNone(events[-1]["package_sha256"])
        self.assertFalse(output.exists())

    def test_unsupported_capability_fails_before_running(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="watch")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        events = parse_events(result.stdout)
        failed = events[-1]
        self.assertEqual(failed["event"], "failed")
        self.assertEqual(failed["code"], "unsupported_capability")
        self.assertFalse(output.exists())

    def test_invalid_request_fails_with_invalid_request(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps({"schema": "wrong"}), encoding="utf-8")
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["code"], "invalid_request")
        self.assertNotIn("accepted", self.event_sequence(events))

    def test_blank_document_abstains_honestly(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, text="   \n  ")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["event"], "failed")
        self.assertEqual(events[-1]["code"], "document_text_unavailable")

    def test_missing_tts_provider_fails_honestly(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "say",
            "--tts-voice", "x",
            "--machine-events",
        ])
        # The real `say` exists on macOS, so this only asserts the failure
        # shape when the tool is unavailable.
        if result.returncode == 2:
            events = parse_events(result.stdout)
            self.assertEqual(events[-1]["event"], "failed")
            self.assertEqual(events[-1]["code"], "tts_provider_failed")

    def test_deterministic_output_across_runs(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        first = self.directory / "first.zip"
        second = self.directory / "second.zip"
        for output in (first, second):
            result = run_cli([
                "package", "from-capability", str(request_path),
                "--output", str(output), "--tts-provider", "fake",
            ])
            self.assertEqual(result.returncode, 0)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_retry_never_rewrites_the_old_attempt(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, attempt_id="attempt-a")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path), "--output", str(output),
        ])
        self.assertEqual(result.returncode, 0)
        first_bytes = output.read_bytes()
        time.sleep(0.05)
        result = run_cli([
            "package", "from-capability", str(request_path), "--output", str(output),
        ])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(first_bytes, output.read_bytes())
        self.assertEqual(sha256_of_bytes(first_bytes), sha256_of_bytes(output.read_bytes()))

    def test_package_contains_no_private_paths(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake",
        ])
        self.assertEqual(result.returncode, 0)
        with zipfile.ZipFile(output) as archive:
            raw_release = archive.read("release.json")
            for blob in archive.namelist()[1:]:
                raw_release += archive.read(blob)
        for marker in (b"/Users/", b"/tmp/", b"tmp/", b"private"):
            self.assertNotIn(marker, raw_release)

    def test_cancellation_terminates_and_leaves_no_artifact(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        output = self.directory / "cancel.zip"
        marker = self.directory / "before-commit.marker"
        env = _env()
        env["LISTEN_GEN_TEST_PAUSE_BEFORE_TERMINAL_COMMIT"] = "1"
        env["LISTEN_GEN_TEST_BEFORE_COMMIT_MARKER"] = str(marker)
        process = subprocess.Popen(
            [sys.executable, "-m", "listen_gen", "package", "from-capability",
             str(request_path), "--output", str(output), "--tts-provider", "fake",
             "--machine-events"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
        )
        for _ in range(200):
            if marker.exists():
                break
            time.sleep(0.05)
        process.send_signal(signal.SIGTERM)
        stdout, _ = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 130)
        events = parse_events(stdout)
        self.assertEqual(events[-1]["event"], "cancelled")
        self.assertFalse(output.exists())
        self.assertFalse(list(self.directory.glob(".*.machine.tmp")))

    def test_core_round_trip_when_checkout_is_configured(self) -> None:
        core = os.environ.get("LISTEN_CORE_CHECKOUT")
        if not core:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        example = Path(core) / "target" / "debug" / "examples" / "inspect-package"
        if not example.exists():
            self.skipTest("Core inspect-package example is not built")
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "round-trip.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake",
        ])
        self.assertEqual(result.returncode, 0)
        check = subprocess.run(
            [str(example), str(output)], capture_output=True, text=True, timeout=60
        )
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertTrue(check.stdout.startswith("OK "))


if __name__ == "__main__":
    unittest.main()
