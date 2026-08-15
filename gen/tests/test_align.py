"""Unit tests for the forced alignment providers and timeline anchoring."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"

from listen_gen.align import (  # noqa: E402
    AlignedWord,
    AlignSegment,
    AlignmentRequest,
    AlignmentResult,
    FixtureAlignAdapter,
    _parse_result,
    build_word_timeline_from_alignment,
)
from listen_gen.package import ConversionError  # noqa: E402


def _segments() -> tuple[AlignSegment, ...]:
    return (
        AlignSegment(index=0, words=("Listen", "carefully"), word_indexes=(0, 3), start_ms=100, end_ms=1200),
        AlignSegment(index=1, words=("Words", "matter"), word_indexes=(0, 2), start_ms=1300, end_ms=2100),
    )


def _context() -> object:
    return type(
        "Context",
        (),
        {
            "language": "en",
            "subject": {"material_revision_id": "m1"},
            "anchor_resource_id": "sha256:anchor",
            "rendition_id": "sha256:rendition",
            "created_at_ms": 1,
        },
    )()


class ParseResultTests(unittest.TestCase):
    def test_valid_result_parses(self) -> None:
        raw = {
            "schema": "listen_gen.alignment-result.v1",
            "provider": {"id": "p", "version": "1"},
            "model": {"id": "m", "version": "2"},
            "words": [
                {"segment_index": 0, "word_index": 0, "text": "word", "start_ms": 10, "end_ms": 40, "score": 0.9},
                {"segment_index": 0, "word_index": 1, "text": "two", "skipped": True},
            ],
        }
        result = _parse_result(raw)
        self.assertEqual(result.provider_id, "p")
        self.assertEqual(result.words[0].score, 0.9)
        self.assertTrue(result.words[1].skipped)
        self.assertEqual(result.words[1].start_ms, 0)

    def test_malformed_result_is_rejected(self) -> None:
        for raw in (
            {"schema": "wrong", "provider": {"id": "p", "version": "1"}, "words": []},
            {"schema": "listen_gen.alignment-result.v1", "provider": {"id": "p", "version": "1"}, "words": "nope"},
            {"schema": "listen_gen.alignment-result.v1", "provider": {"id": "p", "version": "1"},
             "words": [{"segment_index": 0, "word_index": 0, "text": "w", "start_ms": 20, "end_ms": 10}]},
            {"schema": "listen_gen.alignment-result.v1", "provider": {"id": "p", "version": "1"},
             "words": [{"segment_index": 0, "word_index": 0, "text": "w", "start_ms": 10, "end_ms": 40},
                       {"segment_index": 0, "word_index": 0, "text": "x", "start_ms": 50, "end_ms": 60}]},
        ):
            with self.assertRaises(ConversionError):
                _parse_result(raw)

    def test_skipped_word_without_text_is_accepted(self) -> None:
        raw = {
            "schema": "listen_gen.alignment-result.v1",
            "provider": {"id": "p", "version": "1"},
            "words": [
                {"segment_index": 0, "word_index": 0, "text": "word", "start_ms": 10, "end_ms": 40},
                {"segment_index": 0, "word_index": 1, "skipped": True},
            ],
        }
        result = _parse_result(raw)
        self.assertTrue(result.words[1].skipped)
        self.assertEqual(result.words[1].text, "")

    def test_fixture_adapter_replays_committed_result(self) -> None:
        adapter = FixtureAlignAdapter(FIXTURES / "sample.alignment.json")
        request = AlignmentRequest(Path("/tmp/audio.wav"), _segments())
        result = adapter.align(request)
        self.assertEqual(len(result.words), 4)
        self.assertEqual(result.words[0].text, "Listen")


class AnchoringTests(unittest.TestCase):
    def _build(self, result: AlignmentResult):
        return build_word_timeline_from_alignment(
            result=result,
            segments=_segments(),
            sentence_ids=("sentence-0", "sentence-1"),
            context=_context(),
        )

    def test_aligned_words_anchor_to_reading_token_coordinates(self) -> None:
        result = AlignmentResult(
            words=(
                AlignedWord(0, 0, "Listen", 100, 480, 0.98),
                AlignedWord(0, 1, "carefully", 560, 1100, 0.96),
                AlignedWord(1, 0, "Words", 1300, 1600, 0.97),
                AlignedWord(1, 1, "matter", 1650, 2020, 0.95),
            ),
            provider_id="p", provider_version="1",
        )
        resource, payload_bytes = self._build(result)
        payload = json.loads(payload_bytes)
        self.assertEqual(
            [(entry["sentence_id"], entry["token_index"]) for entry in payload["words"]],
            [("sentence-0", 0), ("sentence-0", 3), ("sentence-1", 0), ("sentence-1", 2)],
        )
        self.assertTrue(
            all(entry["timing_source"] == "forced_aligned" for entry in payload["words"])
        )
        self.assertEqual(resource.kind, "word_timeline")
        provenance = resource.provenance
        self.assertEqual(provenance["provider"], {"id": "p", "version": "1"})

    def test_skipped_words_are_dropped(self) -> None:
        result = AlignmentResult(
            words=(
                AlignedWord(0, 0, "Listen", 0, 0, None, skipped=True),
                AlignedWord(1, 0, "Words", 1300, 1600, None),
            ),
            provider_id="p", provider_version="1",
        )
        _, payload_bytes = self._build(result)
        payload = json.loads(payload_bytes)
        self.assertEqual(len(payload["words"]), 1)

    def test_no_anchored_words_fails_qualification(self) -> None:
        result = AlignmentResult(
            words=(),
            provider_id="p", provider_version="1",
        )
        with self.assertRaises(ConversionError):
            self._build(result)

    def test_out_of_range_segment_fails_qualification(self) -> None:
        result = AlignmentResult(
            words=(
                AlignedWord(5, 0, "x", 100, 200, None),
            ),
            provider_id="p", provider_version="1",
        )
        with self.assertRaises(ConversionError):
            self._build(result)

    def test_out_of_range_word_index_fails_qualification(self) -> None:
        result = AlignmentResult(
            words=(
                AlignedWord(0, 9, "x", 100, 200, None),
            ),
            provider_id="p", provider_version="1",
        )
        with self.assertRaises(ConversionError):
            self._build(result)


if __name__ == "__main__":
    unittest.main()
