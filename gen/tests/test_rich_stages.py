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
from listen_gen.asr import AsrSegment, AsrTranscript, AsrWord, _tokens  # noqa: E402
from listen_gen.produce import ProduceConfig, _tts_rich_stages  # noqa: E402
from listen_gen.rich_stages import RichStages  # noqa: E402
from listen_gen.tts import AnchorAlignment  # noqa: E402


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


def assert_complete_rich_package(testcase: unittest.TestCase, output: Path) -> dict[str, dict]:
    """Assert the complete rich graph is present and closed over one track."""
    resources = package_resources(output)
    by_kind = {resource["descriptor"]["kind"]: resource for resource in resources}
    expected = {
        "structured_reading",
        "anchor_time_alignment",
        "subtitle_text_track",
        "word_timeline",
        "sense_group_analysis",
        "word_acoustics",
        "prosody_analysis",
        "phone_timeline",
    }
    testcase.assertTrue(expected <= set(by_kind), sorted(set(expected) - set(by_kind)))
    resource_ids = {resource["resource_id"] for resource in resources}
    for resource in resources:
        for dependency in resource["descriptor"]["dependencies"]:
            testcase.assertIn(dependency["resource_id"], resource_ids)

    subtitle = resource_payload(output, by_kind["subtitle_text_track"])
    subtitle_sentences = subtitle["sentences"]
    testcase.assertTrue(subtitle_sentences)
    sentences_by_id = {sentence["id"]: sentence for sentence in subtitle_sentences}
    token_by_ref = {
        (sentence_id, token["index"]): token
        for sentence_id, sentence in sentences_by_id.items()
        for token in sentence["tokens"]
    }

    timeline = resource_payload(output, by_kind["word_timeline"])
    timeline_words = timeline["words"]
    testcase.assertTrue(timeline_words)
    timeline_refs: set[tuple[str, int]] = set()
    word_windows: dict[tuple[str, int], tuple[int, int]] = {}
    for word in timeline_words:
        ref = (word["sentence_id"], word["token_index"])
        testcase.assertIn(ref[0], sentences_by_id)
        testcase.assertIn(ref, token_by_ref)
        testcase.assertEqual(token_by_ref[ref]["kind"], "word")
        sentence = sentences_by_id[ref[0]]
        testcase.assertIsInstance(word["start_ms"], int)
        testcase.assertIsInstance(word["end_ms"], int)
        testcase.assertLess(word["start_ms"], word["end_ms"])
        testcase.assertGreaterEqual(word["start_ms"], sentence["start_ms"])
        testcase.assertLessEqual(word["end_ms"], sentence["end_ms"])
        timeline_refs.add(ref)
        word_windows[ref] = (word["start_ms"], word["end_ms"])

    groups = resource_payload(output, by_kind["sense_group_analysis"])["groups"]
    testcase.assertTrue(groups)
    for group in groups:
        sentence = sentences_by_id[group["sentence_id"]]
        token_count = len(sentence["tokens"])
        testcase.assertGreaterEqual(group["start_token_index"], 0)
        testcase.assertLess(group["start_token_index"], group["end_token_index_exclusive"])
        testcase.assertLessEqual(group["end_token_index_exclusive"], token_count)

    measurements = resource_payload(output, by_kind["word_acoustics"])["measurements"]
    testcase.assertTrue(measurements)
    for measurement in measurements:
        ref = (
            measurement["word_ref"]["sentence_id"],
            measurement["word_ref"]["token_index"],
        )
        testcase.assertIn(ref, timeline_refs)

    prosody = resource_payload(output, by_kind["prosody_analysis"])
    testcase.assertTrue(prosody["anchors"])
    testcase.assertTrue(prosody["chunks"])
    for anchor in prosody["anchors"]:
        ref = (anchor["word_ref"]["sentence_id"], anchor["word_ref"]["token_index"])
        testcase.assertIn(ref, timeline_refs)
    for chunk in prosody["chunks"]:
        sentence = sentences_by_id[chunk["sentence_id"]]
        testcase.assertGreaterEqual(chunk["start_token_index"], 0)
        testcase.assertLess(chunk["start_token_index"], chunk["end_token_index_exclusive"])
        testcase.assertLessEqual(chunk["end_token_index_exclusive"], len(sentence["tokens"]))

    phones = resource_payload(output, by_kind["phone_timeline"])["phones"]
    testcase.assertTrue(phones)
    for phone in phones:
        # Observed phones keep their real audio time as primary identity; the
        # word_ref annotation is optional (nullable). When it is present the
        # phone lies wholly inside that word's window.
        testcase.assertLess(phone["start_ms"], phone["end_ms"])
        ref_obj = phone["word_ref"]
        if ref_obj is not None:
            ref = (ref_obj["sentence_id"], ref_obj["token_index"])
            testcase.assertIn(ref, timeline_refs)
            testcase.assertGreaterEqual(phone["start_ms"], word_windows[ref][0])
            testcase.assertLessEqual(phone["end_ms"], word_windows[ref][1])
    return by_kind


def _write_assembled_screenshot_fixtures(directory: Path) -> tuple[Path, list[tuple[int, int]]]:
    """Write deterministic ASR/rich fixtures for the screenshot regression."""
    fragments = (
        (558940, 561340, "Send us their name, photo, and a couple lines"),
        (561340, 565660, "about what they mean to you, CNN10@cnn.com."),
    )
    asr_segments: list[dict[str, object]] = []
    expected_word_times: list[tuple[int, int]] = []
    for start_ms, end_ms, text in fragments:
        word_tokens = [token for token in _tokens(text) if token["kind"] == "word"]
        slot = max(20, (end_ms - start_ms - 100) // max(1, len(word_tokens)))
        words: list[dict[str, object]] = []
        for index, token in enumerate(word_tokens):
            word_start = start_ms + 50 + index * slot
            word_end = min(end_ms, word_start + max(10, slot // 2))
            words.append(
                {
                    "start_char": token["start_char"],
                    "end_char": token["end_char"],
                    "start_ms": word_start,
                    "end_ms": word_end,
                    "confidence": 0.95,
                    "timing_source": "asr_reported",
                }
            )
            expected_word_times.append((word_start, word_end))
        asr_segments.append(
            {
                "start_ms": start_ms,
                "end_ms": end_ms,
                "text": text,
                "display_text": text,
                "words": words,
            }
        )
    asr_path = directory / "screenshot.asr.json"
    asr_path.write_text(
        json.dumps(
            {
                "schema": "listen_gen.asr-result.v1",
                "language": "en-US",
                "provider": {"id": "fixture-screenshot", "version": "1"},
                "model": {"id": "fixture-words", "version": "1"},
                "config_sha256": "sha256:" + "1" * 64,
                "segments": asr_segments,
            }
        ),
        encoding="utf-8",
    )

    full_text = "Send us their name, photo, and a couple lines about what they mean to you, CNN10@cnn.com."
    token_count = len(_tokens(full_text))
    word_tokens = [token for token in _tokens(full_text) if token["kind"] == "word"]
    sense_path = directory / "screenshot.sense.json"
    sense_path.write_text(
        json.dumps(
            {
                "schema": "listen_gen.sense-group-result.v1",
                "provider": {"id": "fixture-sense", "version": "1"},
                "config_sha256": "sha256:" + "2" * 64,
                "groups": [
                    {
                        "sentence_index": 0,
                        "group_index": 0,
                        "start_token_index": 0,
                        "end_token_index_exclusive": token_count,
                        "confidence": 0.9,
                        "label": "whole assembled sentence",
                        "head_token_index": word_tokens[0]["index"],
                        "sources": ["rule"],
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    measurements = []
    for token in word_tokens:
        measurements.append(
            {
                "sentence_index": 0,
                "token_index": token["index"],
                "energy": {"rms_dbfs": -22.0, "local_baseline_dbfs": -25.0, "delta_db": 3.0, "prominence": 0.7},
                "pitch": {"median_f0_hz": 180.0, "local_baseline_f0_hz": 170.0, "delta_semitones": 1.0, "range_semitones": 2.0, "prominence": 0.7, "reset_after": 0.1},
                "duration": {"duration_ms": 1, "local_ratio": 1.0},
                "voiced_frame_ratio": 0.8,
            }
        )
    acoustics_path = directory / "screenshot.acoustics.json"
    acoustics_path.write_text(
        json.dumps(
            {
                "schema": "listen_gen.acoustics-result.v1",
                "provider": {"id": "fixture-acoustics", "version": "1"},
                "config_sha256": "sha256:" + "3" * 64,
                "sample_rate_hz": 16000,
                "measurements": measurements,
            }
        ),
        encoding="utf-8",
    )

    prosody_path = directory / "screenshot.prosody.json"
    prosody_path.write_text(
        json.dumps(
            {
                "schema": "listen_gen.prosody-result.v1",
                "provider": {"id": "fixture-prosody", "version": "1"},
                "config_sha256": "sha256:" + "4" * 64,
                "uses_sense_groups": True,
                "anchors": [
                    {
                        "sentence_index": 0,
                        "token_index": word_tokens[0]["index"],
                        "lexical_stress": "primary",
                        "realized_prominence": 0.8,
                        "utterance_role": "nucleus",
                        "evidence": ["energy"],
                        "confidence": 0.8,
                    }
                ],
                "chunks": [
                    {
                        "sentence_index": 0,
                        "chunk_index": 0,
                        "start_token_index": 0,
                        "end_token_index_exclusive": token_count,
                        "nucleus_token_index": word_tokens[0]["index"],
                        "confidence": 0.8,
                    }
                ],
            }
        ),
        encoding="utf-8",
    )

    first_start, first_end = expected_word_times[0]
    phone_path = directory / "screenshot.phone.json"
    phone_path.write_text(
        json.dumps(
            {
                "schema": "listen_gen.phone-result.v1",
                "provider": {"id": "fixture-phone", "version": "1"},
                "config_sha256": "sha256:" + "5" * 64,
                "phone_set": "ipa",
                "phones": [{"symbol": "s", "start_ms": first_start, "end_ms": first_end, "confidence": 0.9}],
            }
        ),
        encoding="utf-8",
    )
    return asr_path, expected_word_times


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
            "subtitle_text_track",
            "word_timeline",
            "sense_group_analysis",
            "word_acoustics",
            "prosody_analysis",
        ):
            self.assertIn(expected, kinds, f"missing {expected} in {kinds}")
        resources = package_resources(output)
        word_timeline = next(r for r in resources if r["descriptor"]["kind"] == "word_timeline")
        subtitle = next(r for r in resources if r["descriptor"]["kind"] == "subtitle_text_track")
        self.assertIn(
            subtitle["resource_id"],
            [d["resource_id"] for d in word_timeline["descriptor"]["dependencies"]],
            "word_timeline must anchor the embedded subtitle track",
        )
        subtitle_payload = resource_payload(output, subtitle)
        self.assertEqual(
            [s["id"] for s in subtitle_payload["sentences"]],
            ["sentence-0", "sentence-1"],
        )
        tokens = subtitle_payload["sentences"][0]["tokens"]
        word_tokens = [t for t in tokens if t["kind"] == "word"]
        self.assertEqual(
            [t["index"] for t in word_tokens],
            [0, 3],
            "subtitle word tokens carry the timeline token coordinates",
        )
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

    def test_acoustic_track_and_speech_activity_are_audio_only_evidence(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--acoustic-track", "fixture",
            "--acoustic-track-fixture", str(FIXTURES / "acoustic-track-result.json"),
            "--speech-activity", "fixture",
            "--speech-activity-fixture", str(FIXTURES / "speech-activity-result.json"),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = package_resources(output)
        by_kind = {r["descriptor"]["kind"]: r for r in resources}
        self.assertIn("acoustic_track", by_kind)
        self.assertIn("speech_activity", by_kind)

        track = by_kind["acoustic_track"]
        # Audio-only: the frame track never depends on the word timeline or the
        # subtitle track, and it references the audio rendition through
        # provenance rather than a text resource dependency.
        self.assertEqual(track["descriptor"]["dependencies"], [])
        self.assertEqual(
            track["descriptor"]["provenance"]["input_resource_ids"], []
        )
        self.assertTrue(track["descriptor"]["provenance"]["input_rendition_ids"])
        # The subject names only the audio rendition, never the reading anchor.
        self.assertEqual(track["descriptor"]["subject"]["anchor_resource_ids"], [])
        self.assertTrue(track["descriptor"]["subject"]["rendition_ids"])
        self.assertFalse(track["required"])
        track_payload = resource_payload(output, track)
        self.assertEqual(track_payload["frame_step_ms"], 10)
        self.assertTrue(track_payload["frames"])
        allowed_frame_keys = {
            "time_ms", "energy_dbfs", "energy_rel_db", "f0_hz", "f0_rel_st", "voiced",
        }
        previous_time = -1
        for frame in track_payload["frames"]:
            # No English-specific / interpretation field ever leaks into the
            # measurement layer.
            self.assertEqual(set(frame), allowed_frame_keys)
            self.assertGreater(frame["time_ms"], previous_time)
            previous_time = frame["time_ms"]
            if frame["f0_hz"] is None:
                self.assertIsNone(frame["f0_rel_st"])

        activity = by_kind["speech_activity"]
        self.assertEqual(activity["descriptor"]["dependencies"], [])
        self.assertFalse(activity["required"])
        spans = resource_payload(output, activity)["spans"]
        self.assertTrue(spans)
        previous_end = 0
        for span in spans:
            self.assertIn(span["activity"], ("speech", "silence"))
            self.assertLess(span["start_ms"], span["end_ms"])
            self.assertGreaterEqual(span["start_ms"], previous_end)
            previous_end = span["end_ms"]

    def test_screenshot_fragments_produce_one_closed_rich_sentence(self) -> None:
        asr_path, expected_word_times = _write_assembled_screenshot_fixtures(self.directory)
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(asr_path),
            "--sense-groups", "fixture", "--sense-groups-fixture", str(self.directory / "screenshot.sense.json"),
            "--acoustics", "fixture", "--acoustics-fixture", str(self.directory / "screenshot.acoustics.json"),
            "--prosody", "fixture", "--prosody-fixture", str(self.directory / "screenshot.prosody.json"),
            "--phones", "fixture", "--phones-fixture", str(self.directory / "screenshot.phone.json"),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        by_kind = assert_complete_rich_package(self, output)
        reading = resource_payload(output, by_kind["structured_reading"])
        expected_text = "Send us their name, photo, and a couple lines about what they mean to you, CNN10@cnn.com."
        self.assertEqual(reading["text"], expected_text)
        sentence_anchors = [
            anchor for anchor in reading["anchors"] if anchor["kind"] == "sentence"
        ]
        self.assertEqual([anchor["anchor_id"] for anchor in sentence_anchors], ["sentence-0"])

        subtitle = resource_payload(output, by_kind["subtitle_text_track"])
        self.assertEqual([sentence["id"] for sentence in subtitle["sentences"]], ["sentence-0"])
        subtitle_tokens = subtitle["sentences"][0]["tokens"]
        word_token_indexes = [token["index"] for token in subtitle_tokens if token["kind"] == "word"]

        word_timeline = resource_payload(output, by_kind["word_timeline"])
        self.assertEqual(
            [(entry["sentence_id"], entry["token_index"]) for entry in word_timeline["words"]],
            [("sentence-0", index) for index in word_token_indexes],
        )
        self.assertEqual(
            [(entry["start_ms"], entry["end_ms"]) for entry in word_timeline["words"]],
            expected_word_times,
        )
        self.assertNotIn("sentence-1", json.dumps(word_timeline))

        groups = resource_payload(output, by_kind["sense_group_analysis"])["groups"]
        self.assertTrue(groups)
        self.assertTrue(all(group["sentence_id"] == "sentence-0" for group in groups))
        measurements = resource_payload(output, by_kind["word_acoustics"])["measurements"]
        self.assertTrue(measurements)
        self.assertTrue(all(item["word_ref"]["sentence_id"] == "sentence-0" for item in measurements))
        prosody = resource_payload(output, by_kind["prosody_analysis"])
        self.assertTrue(all(item["word_ref"]["sentence_id"] == "sentence-0" for item in prosody["anchors"]))
        self.assertTrue(all(item["sentence_id"] == "sentence-0" for item in prosody["chunks"]))
        phones = resource_payload(output, by_kind["phone_timeline"])["phones"]
        self.assertTrue(phones)
        self.assertTrue(all(item["word_ref"]["sentence_id"] == "sentence-0" for item in phones))

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

    def _tts_probe(self, transcript: AsrTranscript):
        class StubAsr:
            def transcribe(self, media_path: Path) -> AsrTranscript:
                return transcript

        reading_payload = {
            "text": "Hello world.",
            "anchors": [
                {
                    "anchor_id": "sentence-0",
                    "kind": "sentence",
                    "start_offset": 0,
                    "end_offset": 12,
                }
            ],
        }
        resources, _, warnings = _tts_rich_stages(
            request=None,
            config=ProduceConfig(rich=RichStages(tts_aligner=StubAsr())),
            audio_bytes=b"fixture-audio",
            audio_duration_ms=300,
            reading_payload=reading_payload,
            alignments=(AnchorAlignment("sentence-0", 0),),
            producer={},
            anchor_resource_id="sha256:anchor",
            language="en",
            subject={},
            rendition_id="sha256:rendition",
            created_at_ms=1,
            progress=None,
        )
        return [resource.kind for resource in resources], warnings

    def test_tts_fragmented_matching_transcript_is_assembled_before_word_fallback(self) -> None:
        transcript = AsrTranscript(
            language="en",
            segments=(
                AsrSegment(
                    0,
                    100,
                    "Hello",
                    "Hello",
                    (AsrWord(0, 5, 10, 50, None, "asr_reported"),),
                ),
                AsrSegment(
                    100,
                    200,
                    "world.",
                    "world.",
                    (AsrWord(0, 6, 110, 180, None, "asr_reported"),),
                ),
            ),
            provider_id="fixture",
            provider_version="1",
        )
        kinds, warnings = self._tts_probe(transcript)
        self.assertIn("word_timeline", kinds)
        self.assertNotIn("word_timeline_abstained", [warning["code"] for warning in warnings])

    def test_tts_mismatched_or_extra_sentences_abstain_whole_word_chain(self) -> None:
        mismatched = AsrTranscript(
            language="en",
            segments=(
                AsrSegment(
                    0,
                    200,
                    "Hello earth.",
                    "Hello earth.",
                    (
                        AsrWord(0, 5, 10, 50, None, "asr_reported"),
                        AsrWord(6, 11, 60, 120, None, "asr_reported"),
                    ),
                ),
            ),
            provider_id="fixture",
            provider_version="1",
        )
        extra = AsrTranscript(
            language="en",
            segments=(
                AsrSegment(0, 100, "Hello world.", "Hello world.", ()),
                AsrSegment(100, 200, "Extra.", "Extra.", ()),
            ),
            provider_id="fixture",
            provider_version="1",
        )
        for transcript in (mismatched, extra):
            with self.subTest(transcript=transcript.segments):
                kinds, warnings = self._tts_probe(transcript)
                self.assertNotIn("word_timeline", kinds)
                self.assertIn("word_timeline_abstained", [warning["code"] for warning in warnings])

    def test_tts_text_mismatch_abstains_word_level_chain(self) -> None:
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
        for expected in ("structured_reading", "anchor_time_alignment"):
            self.assertIn(expected, kinds, f"missing {expected} in {kinds}")
        self.assertNotIn("word_timeline", kinds)
        self.assertNotIn("sense_group_analysis", kinds)
        self.assertNotIn("word_acoustics", kinds)
        self.assertNotIn("prosody_analysis", kinds)
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        codes = [event["code"] for event in warnings]
        self.assertIn("word_timeline_abstained", codes)


class RichAlignedMediaTests(unittest.TestCase):
    """Media -> reading, word timeline derived by forced alignment."""

    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())

    def _run(self, output: Path, request_path: Path, extra: list[str]) -> subprocess.CompletedProcess:
        return run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            *extra,
        ])

    def test_media_aligner_produces_forced_aligned_timeline(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = self._run(output, request_path, [
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--aligner", "fixture", "--aligner-fixture", str(FIXTURES / "sample.alignment.json"),
            "--sense-groups", "baseline",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = package_resources(output)
        word_timeline = next(r for r in resources if r["descriptor"]["kind"] == "word_timeline")
        payload = resource_payload(output, word_timeline)
        self.assertEqual(
            [(entry["sentence_id"], entry["token_index"]) for entry in payload["words"]],
            [("sentence-0", 0), ("sentence-0", 3), ("sentence-1", 0), ("sentence-1", 2)],
        )
        self.assertTrue(
            all(entry["timing_source"] == "forced_aligned" for entry in payload["words"])
        )
        provenance = word_timeline["descriptor"]["provenance"]
        self.assertEqual(provenance["provider"], {"id": "fixture-aligner", "version": "1"})

    def test_media_aligner_failure_falls_back_to_asr_words(self) -> None:
        bad = self.directory / "bad-alignment.json"
        bad.write_text("[1, 2]")
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = self._run(output, request_path, [
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--aligner", "fixture", "--aligner-fixture", str(bad),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = package_resources(output)
        word_timeline = next(r for r in resources if r["descriptor"]["kind"] == "word_timeline")
        payload = resource_payload(output, word_timeline)
        self.assertTrue(
            all(entry["timing_source"] == "asr_reported" for entry in payload["words"])
        )
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        codes = [event["code"] for event in warnings]
        self.assertTrue(any("aligner_degraded" in code for code in codes), codes)

    def test_subtitle_path_skips_asr_and_aligns(self) -> None:
        srt = self.directory / "track.srt"
        srt.write_text(
            "1\n00:00:00,100 --> 00:00:01,200\nListen, carefully!\n\n"
            "2\n00:00:01,300 --> 00:00:02,100\nWords matter.\n",
            encoding="utf-8",
        )
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = self._run(output, request_path, [
            "--subtitle", str(srt),
            "--aligner", "fixture", "--aligner-fixture", str(FIXTURES / "sample.alignment.json"),
            "--sense-groups", "baseline",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        self.assertIn("structured_reading", kinds)
        self.assertIn("anchor_time_alignment", kinds)
        self.assertIn("word_timeline", kinds)
        self.assertIn("sense_group_analysis", kinds)
        resources = package_resources(output)
        alignment = next(
            r for r in resources
            if r["descriptor"]["kind"] == "anchor_time_alignment"
        )
        self.assertIsNone(alignment["descriptor"]["producer"])
        reading = next(r for r in resources if r["descriptor"]["kind"] == "structured_reading")
        payload = resource_payload(output, reading)
        self.assertEqual(payload["text"], "Listen, carefully!\nWords matter.")
        word_timeline = next(r for r in resources if r["descriptor"]["kind"] == "word_timeline")
        words = resource_payload(output, word_timeline)["words"]
        self.assertTrue(
            all(entry["timing_source"] == "forced_aligned" for entry in words)
        )
        self.assertEqual(words[0]["start_ms"], 100)

    def test_subtitle_fragments_merge_before_forced_alignment(self) -> None:
        first = "Send us their name, photo, and a couple lines"
        second = "about what they mean to you, CNN10@cnn.com."
        full_text = f"{first} {second}"
        srt = self.directory / "fragmented-track.srt"
        srt.write_text(
            f"1\n00:00:01,000 --> 00:00:03,000\n{first}\n\n"
            f"2\n00:00:03,000 --> 00:00:05,000\n{second}\n",
            encoding="utf-8",
        )
        lexical_words = [token["text"] for token in _tokens(full_text) if token["kind"] == "word"]
        alignment_path = self.directory / "fragmented.alignment.json"
        alignment_path.write_text(
            json.dumps(
                {
                    "schema": "listen_gen.alignment-result.v1",
                    "provider": {"id": "fixture-aligner", "version": "1"},
                    "config_sha256": "sha256:" + "6" * 64,
                    "words": [
                        {
                            "segment_index": 0,
                            "word_index": index,
                            "text": word,
                            "start_ms": 1100 + index * 180,
                            "end_ms": 1200 + index * 180,
                        }
                        for index, word in enumerate(lexical_words)
                    ],
                }
            ),
            encoding="utf-8",
        )
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = self._run(output, request_path, [
            "--subtitle", str(srt),
            "--aligner", "fixture", "--aligner-fixture", str(alignment_path),
            "--sense-groups", "baseline",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        resources = package_resources(output)
        by_kind = {resource["descriptor"]["kind"]: resource for resource in resources}
        reading = resource_payload(output, by_kind["structured_reading"])
        self.assertEqual(reading["text"], full_text)
        self.assertEqual(
            [anchor["anchor_id"] for anchor in reading["anchors"] if anchor["kind"] == "sentence"],
            ["sentence-0"],
        )
        subtitle = resource_payload(output, by_kind["subtitle_text_track"])
        self.assertEqual([sentence["id"] for sentence in subtitle["sentences"]], ["sentence-0"])
        timeline = resource_payload(output, by_kind["word_timeline"])
        self.assertTrue(timeline["words"])
        self.assertTrue(all(entry["sentence_id"] == "sentence-0" for entry in timeline["words"]))
        self.assertEqual(timeline["words"][0]["start_ms"], 1100)

    def test_subtitle_assembled_complete_rich_chain_is_closed(self) -> None:
        """All rich projections consume the one assembled subtitle sentence."""
        _write_assembled_screenshot_fixtures(self.directory)
        first = "Send us their name, photo, and a couple lines"
        second = "about what they mean to you, CNN10@cnn.com."
        full_text = f"{first} {second}"
        srt = self.directory / "complete-fragmented-track.srt"
        srt.write_text(
            f"1\n00:00:01,000 --> 00:00:03,000\n{first}\n\n"
            f"2\n00:00:03,000 --> 00:00:05,000\n{second}\n",
            encoding="utf-8",
        )
        lexical_words = [token["text"] for token in _tokens(full_text) if token["kind"] == "word"]
        alignment_path = self.directory / "complete-fragmented.alignment.json"
        aligned_words = []
        for index, word in enumerate(lexical_words):
            start_ms = 1100 + index * 120
            aligned_words.append(
                {
                    "segment_index": 0,
                    "word_index": index,
                    "text": word,
                    "start_ms": start_ms,
                    "end_ms": start_ms + 50,
                }
            )
        alignment_path.write_text(
            json.dumps(
                {
                    "schema": "listen_gen.alignment-result.v1",
                    "provider": {"id": "fixture-complete-aligner", "version": "1"},
                    "config_sha256": "sha256:" + "7" * 64,
                    "words": aligned_words,
                }
            ),
            encoding="utf-8",
        )
        # The helper's phone fixture is for the ASR clock; use the forced
        # alignment clock for this subtitle path so phone references close.
        (self.directory / "screenshot.phone.json").write_text(
            json.dumps(
                {
                    "schema": "listen_gen.phone-result.v1",
                    "provider": {"id": "fixture-phone", "version": "1"},
                    "config_sha256": "sha256:" + "8" * 64,
                    "phone_set": "ipa",
                    "phones": [{"symbol": "s", "start_ms": 1100, "end_ms": 1150}],
                }
            ),
            encoding="utf-8",
        )
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = self._run(output, request_path, [
            "--subtitle", str(srt),
            "--aligner", "fixture", "--aligner-fixture", str(alignment_path),
            "--sense-groups", "fixture", "--sense-groups-fixture", str(self.directory / "screenshot.sense.json"),
            "--acoustics", "fixture", "--acoustics-fixture", str(self.directory / "screenshot.acoustics.json"),
            "--prosody", "fixture", "--prosody-fixture", str(self.directory / "screenshot.prosody.json"),
            "--phones", "fixture", "--phones-fixture", str(self.directory / "screenshot.phone.json"),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        by_kind = assert_complete_rich_package(self, output)
        reading = resource_payload(output, by_kind["structured_reading"])
        self.assertEqual(reading["text"], full_text)
        self.assertEqual(
            [anchor["anchor_id"] for anchor in reading["anchors"] if anchor["kind"] == "sentence"],
            ["sentence-0"],
        )

    def test_subtitle_without_aligner_abstains_word_timeline(self) -> None:
        srt = self.directory / "track.srt"
        srt.write_text(
            "1\n00:00:00,100 --> 00:00:01,200\nListen, carefully!\n\n"
            "2\n00:00:01,300 --> 00:00:02,100\nWords matter.\n",
            encoding="utf-8",
        )
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_media(directory=self.directory)))
        output = self.directory / "package.zip"
        result = self._run(output, request_path, [
            "--subtitle", str(srt),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        self.assertIn("structured_reading", kinds)
        self.assertNotIn("word_timeline", kinds)
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        codes = [event["code"] for event in warnings]
        self.assertIn("word_timeline_abstained", codes, codes)


class RichTtsAlignedTests(unittest.TestCase):
    """Document -> listen derives the word timeline by forced alignment."""

    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp())

    def test_tts_forced_alignment_produces_word_timeline_and_rich_chain(self) -> None:
        from test_produce import request_document

        # The committed alignment fixture uses relative windows.  The TTS
        # anchor clock is cumulative per source sentence, so shift each
        # segment into the absolute clock before exercising closure checks.
        alignment = json.loads(
            (FIXTURES / "sample-document.alignment.json").read_text(encoding="utf-8")
        )
        offsets = {0: 0, 1: 1140, 2: 3270}
        sentence_ends = {0: 1140, 1: 3270, 2: 6300}
        for word in alignment["words"]:
            offset = offsets[word["segment_index"]]
            word["start_ms"] += offset
            word["end_ms"] = min(
                word["end_ms"] + offset, sentence_ends[word["segment_index"]]
            )
        alignment_path = self.directory / "tts.alignment.json"
        alignment_path.write_text(json.dumps(alignment), encoding="utf-8")
        phone_path = self.directory / "tts.phone.json"
        phone_path.write_text(
            json.dumps(
                {
                    "schema": "listen_gen.phone-result.v1",
                    "provider": {"id": "fixture-phone", "version": "1"},
                    "config_sha256": "sha256:" + "9" * 64,
                    "phone_set": "ipa",
                    "phones": [
                        {
                            "symbol": "s",
                            "start_ms": 20 + index * 20,
                            "end_ms": 30 + index * 20,
                        }
                        for index in range(6)
                    ],
                }
            ),
            encoding="utf-8",
        )
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_document(self.directory, capability="listen")))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "fake",
            "--aligner", "fixture", "--aligner-fixture", str(alignment_path),
            "--sense-groups", "baseline",
            "--acoustics", "baseline",
            "--prosody", "baseline",
            "--phones", "fixture", "--phones-fixture", str(phone_path),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        by_kind = assert_complete_rich_package(self, output)
        kinds = resource_kinds(output)
        for expected in (
            "structured_reading",
            "anchor_time_alignment",
            "word_timeline",
            "sense_group_analysis",
            "word_acoustics",
            "prosody_analysis",
            "phone_timeline",
        ):
            self.assertIn(expected, kinds, f"missing {expected} in {kinds}")
        resources = package_resources(output)
        word_timeline = next(r for r in resources if r["descriptor"]["kind"] == "word_timeline")
        payload = resource_payload(output, word_timeline)
        self.assertTrue(
            all(entry["timing_source"] == "forced_aligned" for entry in payload["words"])
        )
        self.assertEqual(payload["words"][0]["start_ms"], 0)
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        self.assertEqual(warnings, [], [event["message"] for event in warnings])

    def test_tts_aligner_failure_does_not_bind_mismatched_retranscription(self) -> None:
        from test_produce import request_document

        bad = self.directory / "bad-alignment.json"
        bad.write_text("[1, 2]")
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps(request_document(self.directory, capability="listen")))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "fake",
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--aligner", "fixture", "--aligner-fixture", str(bad),
            "--tts-aligner", "fixture",
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        kinds = resource_kinds(output)
        self.assertNotIn("word_timeline", kinds)
        events = [json.loads(line) for line in result.stdout.splitlines() if line]
        warnings = [event for event in events if event.get("event") == "warning"]
        self.assertIn("word_timeline_abstained", [event["code"] for event in warnings])


if __name__ == "__main__":
    unittest.main()
