"""End-to-end rich stage tests against the capability production engine.

Covers the v3 pipeline shape only: capability request -> word timeline and
the optional rich stages inside one deterministic Content Package v3.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT / "tests"))

from test_produce import media_rendition, run_cli  # noqa: E402


def request_media(capability: str = "read", directory=None) -> dict:
    rendition = media_rendition(directory)
    blob = dict(rendition["blob"])
    blob["path"] = str(blob["path"])
    rendition["blob"] = blob
    return {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "attempt_id": "attempt-rich-media",
        "material": {"material_id": "material-m", "material_revision_id": "revision-m", "title": "M"},
        "edition": {"edition_id": "edition-m", "title": "E", "target_language": "en-US", "support_languages": []},
        "requested_capability": capability,
        "available_renditions": [rendition],
        "available_resources": [],
    }


def package_resources(output: Path) -> list[dict]:
    with zipfile.ZipFile(output) as archive:
        release = json.loads(archive.read("release.json"))
    return release["resources"]


def resource_payload(output: Path, resource: dict) -> dict:
    with zipfile.ZipFile(output) as archive:
        digest = resource["descriptor"]["payload_blob"]["digest"]
        return json.loads(archive.read(f"blobs/sha256/{digest.removeprefix('sha256:')}"))


def resource_kinds(output: Path) -> list[str]:
    return [entry["descriptor"]["kind"] for entry in package_resources(output)]


class RichMediaPipelineTests(unittest.TestCase):
    """Media -> structured reading -> word timeline -> rich stages."""

    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())

    def test_baseline_stages_produce_word_timeline_sense_groups_acoustics_prosody(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--sense-groups", "baseline",
            "--acoustics", "fixture",
            "--acoustics-fixture", str(FIXTURES / "acoustics-result.json"),
            "--prosody", "baseline",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        for expected in (
            "structured_reading",
            "anchor_time_alignment",
            "word_timeline",
            "sense_group_analysis",
            "word_acoustics",
            "prosody_analysis",
        ):
            self.assertIn(expected, kinds, f"missing {expected} in {kinds}")
        resources = package_resources(output)
        word_timeline = next(r for r in resources if r["descriptor"]["kind"] == "word_timeline")
        payload = resource_payload(output, word_timeline)
        words = payload["words"]
        self.assertEqual(
            [entry["sentence_id"] for entry in words],
            ["sentence-0", "sentence-0", "sentence-1", "sentence-1"],
        )
        self.assertEqual(
            [entry["token_index"] for entry in words],
            [0, 3, 0, 2],
        )
        self.assertTrue(
            all(entry["start_ms"] >= 0 and entry["end_ms"] > entry["start_ms"] for entry in words)
        )
        self.assertTrue(
            all(entry["timing_source"] == "asr_reported" for entry in words)
        )

    def test_acoustics_baseline_degrades_on_unreadable_audio(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--acoustics", "baseline",
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        self.assertIn("word_timeline", kinds)
        self.assertNotIn("word_acoustics", kinds)
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        codes = [event["code"] for event in warnings]
        self.assertTrue(any("acoustics" in code for code in codes), codes)

    def test_fixture_stages_replay_committed_results(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--sense-groups", "fixture",
            "--sense-groups-fixture", str(FIXTURES / "sense-group-result.json"),
            "--acoustics", "fixture",
            "--acoustics-fixture", str(FIXTURES / "acoustics-result.json"),
            "--prosody", "fixture",
            "--prosody-fixture", str(FIXTURES / "prosody-result.json"),
            "--phones", "fixture",
            "--phones-fixture", str(FIXTURES / "phone-result.json"),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        for expected in ("word_timeline", "sense_group_analysis", "word_acoustics", "prosody_analysis", "phone_timeline"):
            self.assertIn(expected, kinds)
        resources = package_resources(output)
        prosody = next(r for r in resources if r["descriptor"]["kind"] == "prosody_analysis")
        dependencies = prosody["descriptor"]["dependencies"]
        dep_kinds = [entry["resource_id"] for entry in dependencies]
        by_id = {r["resource_id"]: r for r in resources}
        dep_ids = set(by_id.keys())
        self.assertTrue(all(dep in dep_ids for dep in dep_kinds))

    def test_sense_groups_only_stage_is_independent(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--sense-groups", "baseline",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        self.assertIn("word_timeline", kinds)
        self.assertIn("sense_group_analysis", kinds)
        self.assertNotIn("word_acoustics", kinds)
        self.assertNotIn("prosody_analysis", kinds)

    def test_failing_stage_degrades_and_preserves_upstream(self) -> None:
        bad_fixture = self.directory / "bad.json"
        bad_fixture.write_text("[1, 2, 3]")
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--sense-groups", "fixture", "--sense-groups-fixture", str(bad_fixture),
            "--acoustics", "fixture", "--acoustics-fixture", str(FIXTURES / "acoustics-result.json"),
            "--prosody", "fixture", "--prosody-fixture", str(FIXTURES / "prosody-result.json"),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        self.assertIn("word_timeline", kinds)
        self.assertIn("word_acoustics", kinds)
        self.assertNotIn("sense_group_analysis", kinds)
        # The prosody fixture declares uses_sense_groups=true, so it honestly
        # degrades with the missing sense-group evidence.
        self.assertNotIn("prosody_analysis", kinds)
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        codes = [event["code"] for event in warnings]
        self.assertTrue(any("sense_groups" in code for code in codes), codes)

    def test_media_without_word_timings_produces_no_word_resources(self) -> None:
        no_words = self.directory / "no-words.json"
        no_words.write_text(json.dumps({
            "schema": "listen_gen.asr-result.v1",
            "language": "en",
            "provider": {"id": "fixture-asr", "version": "1"},
            "config_sha256": "sha256:" + "b" * 64,
            "segments": [
                {"start_ms": 0, "end_ms": 500, "text": "Hello.", "display_text": "Hello.", "words": []},
            ],
        }))
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(no_words),
            "--sense-groups", "baseline",
            "--acoustics", "baseline",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        self.assertNotIn("word_timeline", kinds)
        self.assertNotIn("sense_group_analysis", kinds)
        self.assertNotIn("word_acoustics", kinds)


class RichTtsPipelineTests(unittest.TestCase):
    """Document -> listen joins the rich pipeline through a tts_aligner."""

    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())

    def test_tts_audio_is_transcribed_into_word_timeline(self) -> None:
        from test_produce import request_document

        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_document(self.directory, capability="listen")))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "fake",
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--tts-aligner", "fixture",
            "--sense-groups", "baseline",
            "--acoustics", "fixture",
            "--acoustics-fixture", str(FIXTURES / "acoustics-result.json"),
            "--prosody", "fixture",
            "--prosody-fixture", str(FIXTURES / "prosody-result.json"),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        for expected in (
            "structured_reading",
            "anchor_time_alignment",
            "word_timeline",
            "sense_group_analysis",
        ):
            self.assertIn(expected, kinds, f"missing {expected} in {kinds}")
        # The fixture aligner transcript (sample.asr.json) does not carry the
        # exact TTS sentence text, so the audio-backed stages honestly degrade
        # instead of fabricating measurements.
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        codes = [event["code"] for event in warnings]
        self.assertTrue(any("acoustics" in code for code in codes), codes)


if __name__ == "__main__":
    unittest.main()
