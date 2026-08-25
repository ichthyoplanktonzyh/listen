"""Unit tests for the Qwen3 forced-alignment adapter.

The 0.6B model is never downloaded here: the model and audio decoder are
injected so the tests exercise chunking, sentence-window padding, absolute
time offsetting, and provider-vs-reading token mapping deterministically.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from listen_gen.align import (  # noqa: E402
    AlignSegment,
    AlignmentRequest,
    Qwen3ForcedAlignAdapter,
    _anchor_items,
    _chunk_segments,
    _map_qwen_language,
    _normalize_token,
    build_word_timeline_from_alignment,
)
from listen_gen.package import ConversionError  # noqa: E402

SAMPLE_RATE = 16000


class _Item:
    """A stand-in for a Qwen ``ForcedAlignItem`` (times in seconds)."""

    def __init__(self, text: str, start_time: float, end_time: float):
        self.text = text
        self.start_time = start_time
        self.end_time = end_time


class _Result:
    """A stand-in for a Qwen ``ForcedAlignResult``."""

    def __init__(self, items: list[_Item]):
        self.items = items


class _FakeModel:
    """Replays canned per-call responses and records what it was asked."""

    def __init__(self, responses: list[list[tuple[str, float, float]]]):
        self._responses = list(responses)
        self.calls: list[tuple[object, str, str]] = []

    def align(self, audio, text, language):  # noqa: ANN001
        self.calls.append((audio, text, language))
        spec = self._responses.pop(0)
        return [_Result([_Item(t, s, e) for (t, s, e) in spec])]


def _audio_loader_for(duration_ms: int):
    samples = [0.0] * int(SAMPLE_RATE * duration_ms / 1000)

    def _loader(path: Path, sample_rate: int):
        return samples, sample_rate

    return _loader


def _adapter(model: _FakeModel, duration_ms: int, **kwargs) -> Qwen3ForcedAlignAdapter:
    return Qwen3ForcedAlignAdapter(
        model_loader=lambda: model,
        audio_loader=_audio_loader_for(duration_ms),
        **kwargs,
    )


class NormalizationTests(unittest.TestCase):
    def test_case_punctuation_and_apostrophes_fold_together(self) -> None:
        self.assertEqual(_normalize_token("Don't"), _normalize_token("dont"))
        self.assertEqual(_normalize_token("it’s"), _normalize_token("its"))
        self.assertEqual(_normalize_token("“hello”"), "hello")
        self.assertEqual(_normalize_token("Words,"), "words")
        self.assertEqual(_normalize_token("  spaced  "), "spaced")

    def test_language_maps_to_qwen_name(self) -> None:
        self.assertEqual(_map_qwen_language("en-US"), "English")
        self.assertEqual(_map_qwen_language("zh"), "Chinese")
        self.assertEqual(_map_qwen_language("auto"), "English")
        self.assertEqual(_map_qwen_language(None), "English")
        self.assertEqual(_map_qwen_language("xx"), "English")


class TokenMappingTests(unittest.TestCase):
    def test_clean_one_to_one_mapping(self) -> None:
        expected = [(0, 0, "Listen"), (0, 1, "carefully")]
        items = [_Item("Listen", 0.1, 0.3), _Item("carefully", 0.35, 0.6)]
        aligned = _anchor_items(expected, items, 0, 5000)
        self.assertEqual([w.text for w in aligned], ["Listen", "carefully"])
        self.assertEqual((aligned[0].start_ms, aligned[0].end_ms), (100, 300))
        self.assertFalse(any(w.skipped for w in aligned))

    def test_provider_split_contractions_reconstruct_reading_tokens(self) -> None:
        # Qwen may split contractions differently than the reading tokenizer.
        expected = [(0, 0, "don't"), (0, 1, "it's"), (0, 2, "didn't")]
        items = [
            _Item("do", 0.0, 0.1),
            _Item("n't", 0.1, 0.2),
            _Item("it", 0.3, 0.4),
            _Item("'s", 0.4, 0.5),
            _Item("didn't", 0.6, 0.9),
        ]
        aligned = _anchor_items(expected, items, 0, 5000)
        self.assertFalse(any(w.skipped for w in aligned))
        self.assertEqual([w.text for w in aligned], ["don't", "it's", "didn't"])
        # first token spans both of its provider pieces
        self.assertEqual((aligned[0].start_ms, aligned[0].end_ms), (0, 200))
        self.assertEqual((aligned[1].start_ms, aligned[1].end_ms), (300, 500))

    def test_curly_quotes_and_case_do_not_break_matching(self) -> None:
        expected = [(0, 0, "hello")]
        items = [_Item("“Hello”", 0.2, 0.5)]
        aligned = _anchor_items(expected, items, 0, 5000)
        self.assertFalse(aligned[0].skipped)
        self.assertEqual(aligned[0].text, "hello")

    def test_unmatched_token_is_skipped_not_fabricated(self) -> None:
        expected = [(0, 0, "Listen"), (0, 1, "carefully")]
        items = [_Item("Listen", 0.1, 0.3)]  # provider dropped a word
        aligned = _anchor_items(expected, items, 0, 5000)
        self.assertFalse(aligned[0].skipped)
        self.assertTrue(aligned[1].skipped)
        self.assertEqual((aligned[1].start_ms, aligned[1].end_ms), (0, 0))


class ChunkingTests(unittest.TestCase):
    def _segments(self, windows):
        return tuple(
            AlignSegment(index=i, words=("w",), word_indexes=(0,), start_ms=s, end_ms=e)
            for i, (s, e) in enumerate(windows)
        )

    def test_adjacent_sentences_merge_into_one_chunk(self) -> None:
        segments = self._segments([(0, 1000), (1000, 2000), (2000, 3000)])
        chunks = _chunk_segments(segments, 3000, target_ms=30000, max_ms=45000)
        self.assertEqual(len(chunks), 1)
        self.assertEqual((chunks[0].start_ms, chunks[0].end_ms), (0, 3000))

    def test_long_reading_splits_at_max_window(self) -> None:
        segments = self._segments([(0, 20000), (20000, 40000), (40000, 60000)])
        chunks = _chunk_segments(segments, 60000, target_ms=30000, max_ms=45000)
        self.assertGreater(len(chunks), 1)
        for chunk in chunks:
            self.assertLessEqual(chunk.end_ms - chunk.start_ms, 45000)

    def test_degenerate_timing_becomes_one_full_audio_chunk(self) -> None:
        segments = self._segments([(0, 0), (0, 0)])
        chunks = _chunk_segments(segments, 4000, target_ms=30000, max_ms=45000)
        self.assertEqual(len(chunks), 1)
        self.assertEqual((chunks[0].start_ms, chunks[0].end_ms), (0, 4000))


class AdapterAlignTests(unittest.TestCase):
    def _segments(self):
        return (
            AlignSegment(index=0, words=("Listen", "carefully"), word_indexes=(0, 3), start_ms=0, end_ms=0),
            AlignSegment(index=1, words=("Words", "matter"), word_indexes=(0, 2), start_ms=0, end_ms=0),
        )

    def test_converts_qwen_output_to_aligned_words(self) -> None:
        model = _FakeModel([
            [
                ("Listen", 0.10, 0.30),
                ("carefully", 0.35, 0.60),
                ("Words", 0.65, 0.75),
                ("matter", 0.80, 0.95),
            ]
        ])
        adapter = _adapter(model, duration_ms=1000)
        result = adapter.align(AlignmentRequest(Path("/tmp/a.wav"), self._segments(), language="en"))
        self.assertEqual(result.provider_id, "qwen3-forced-aligner")
        self.assertEqual(result.model_id, "Qwen/Qwen3-ForcedAligner-0.6B")
        self.assertTrue(result.config_sha256.startswith("sha256:"))
        self.assertEqual(len(result.words), 4)
        # local word_index (position within the segment) is preserved
        self.assertEqual(
            [(w.segment_index, w.word_index, w.text) for w in result.words],
            [(0, 0, "Listen"), (0, 1, "carefully"), (1, 0, "Words"), (1, 1, "matter")],
        )
        self.assertEqual((result.words[0].start_ms, result.words[0].end_ms), (100, 300))
        self.assertIsNone(result.words[0].score)
        # a single degenerate-timing chunk was aligned, and the language mapped
        self.assertEqual(len(model.calls), 1)
        self.assertEqual(model.calls[0][2], "English")

    def test_language_is_forwarded_and_mapped(self) -> None:
        model = _FakeModel([[("Listen", 0.1, 0.2), ("carefully", 0.3, 0.4),
                             ("Words", 0.5, 0.6), ("matter", 0.7, 0.8)]])
        adapter = _adapter(model, duration_ms=1000)
        adapter.align(AlignmentRequest(Path("/tmp/a.wav"), self._segments(), language="zh"))
        self.assertEqual(model.calls[0][2], "Chinese")

    def test_all_skipped_alignment_fails_qualification(self) -> None:
        model = _FakeModel([[("totally", 0.1, 0.2), ("different", 0.3, 0.4)]])
        adapter = _adapter(model, duration_ms=1000)
        with self.assertRaises(ConversionError):
            adapter.align(AlignmentRequest(Path("/tmp/a.wav"), self._segments(), language="en"))

    def test_model_is_loaded_once_and_reused(self) -> None:
        loads = {"count": 0}

        def loader():
            loads["count"] += 1
            return _FakeModel([
                [("Listen", 0.1, 0.2), ("carefully", 0.3, 0.4), ("Words", 0.5, 0.6), ("matter", 0.7, 0.8)],
                [("Listen", 0.1, 0.2), ("carefully", 0.3, 0.4), ("Words", 0.5, 0.6), ("matter", 0.7, 0.8)],
            ])

        adapter = Qwen3ForcedAlignAdapter(
            model_loader=loader, audio_loader=_audio_loader_for(1000)
        )
        request = AlignmentRequest(Path("/tmp/a.wav"), self._segments(), language="en")
        adapter.align(request)
        adapter.align(request)
        self.assertEqual(loads["count"], 1)


class PaddingAndOffsetTests(unittest.TestCase):
    def _two_sentences(self, s0, e0, s1, e1):
        return (
            AlignSegment(index=0, words=("Listen",), word_indexes=(0,), start_ms=s0, end_ms=e0),
            AlignSegment(index=1, words=("Words",), word_indexes=(0,), start_ms=s1, end_ms=e1),
        )

    def test_chunk_start_padding_offsets_to_global_time(self) -> None:
        # One chunk over [5000, 7000]; padding 400 -> slice starts at 4600.
        model = _FakeModel([[("Listen", 0.10, 0.40), ("Words", 1.40, 1.80)]])
        adapter = _adapter(model, duration_ms=10000, padding_ms=400)
        result = adapter.align(
            AlignmentRequest(Path("/tmp/a.wav"), self._two_sentences(5000, 6000, 6000, 7000), language="en")
        )
        # 4600 + 100 = 4700 .. 4600 + 400 = 5000
        self.assertEqual((result.words[0].start_ms, result.words[0].end_ms), (4700, 5000))
        # 4600 + 1400 = 6000 .. 4600 + 1800 = 6400
        self.assertEqual((result.words[1].start_ms, result.words[1].end_ms), (6000, 6400))

    def test_padding_never_produces_negative_start(self) -> None:
        # Sentence starts at 200ms (< padding); slice must clamp to 0.
        model = _FakeModel([[("Listen", 0.05, 0.20), ("Words", 0.40, 0.70)]])
        adapter = _adapter(model, duration_ms=5000, padding_ms=400)
        result = adapter.align(
            AlignmentRequest(Path("/tmp/a.wav"), self._two_sentences(200, 1000, 1000, 2000), language="en")
        )
        self.assertGreaterEqual(result.words[0].start_ms, 0)
        # offset is 0 (clamped), so times equal the raw provider times
        self.assertEqual((result.words[0].start_ms, result.words[0].end_ms), (50, 200))

    def test_times_are_clamped_to_audio_duration(self) -> None:
        # Provider reports past the end of the audio; must clamp to duration.
        model = _FakeModel([[("Listen", 0.10, 9.50)]])
        adapter = _adapter(model, duration_ms=3000, padding_ms=400)
        result = adapter.align(
            AlignmentRequest(
                Path("/tmp/a.wav"),
                (AlignSegment(index=0, words=("Listen",), word_indexes=(0,), start_ms=0, end_ms=3000),),
                language="en",
            )
        )
        self.assertLessEqual(result.words[0].end_ms, 3000)
        self.assertGreater(result.words[0].end_ms, result.words[0].start_ms)


class CliWiringTests(unittest.TestCase):
    """`--aligner qwen` builds the Qwen adapter (no model touched)."""

    def _build(self, argv: list[str]):
        from listen_gen.cli import _build_rich, parser

        args = parser().parse_args(
            ["package", "from-capability", "req.json", "--output", "out.zip", *argv]
        )
        return _build_rich(args)

    def test_qwen_selector_builds_qwen_adapter(self) -> None:
        stages = self._build(
            ["--aligner", "qwen", "--aligner-device", "cpu", "--aligner-padding-ms", "250"]
        )
        self.assertIsNotNone(stages)
        aligner = stages.aligner
        self.assertIsInstance(aligner, Qwen3ForcedAlignAdapter)
        self.assertEqual(aligner.device, "cpu")
        self.assertEqual(aligner.padding_ms, 250)
        self.assertEqual(aligner.model_id, "Qwen/Qwen3-ForcedAligner-0.6B")

    def test_none_selector_leaves_aligner_unset(self) -> None:
        stages = self._build(["--aligner", "none"])
        self.assertTrue(stages is None or stages.aligner is None)


class PipelineTests(unittest.TestCase):
    """reading + audio + sentence windows -> qualified word timeline payload."""

    def _context(self):
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

    def test_alignment_result_builds_word_timeline(self) -> None:
        segments = (
            AlignSegment(index=0, words=("Listen", "carefully"), word_indexes=(0, 3), start_ms=0, end_ms=1500),
            AlignSegment(index=1, words=("Words", "matter"), word_indexes=(0, 2), start_ms=1500, end_ms=3000),
        )
        model = _FakeModel([
            [
                ("Listen", 0.10, 0.40),
                ("carefully", 0.45, 0.90),
                ("Words", 1.60, 1.80),
                ("matter", 1.85, 2.10),
            ]
        ])
        adapter = _adapter(model, duration_ms=3000, padding_ms=400)
        result = adapter.align(AlignmentRequest(Path("/tmp/a.wav"), segments, language="en"))
        resource, payload_bytes = build_word_timeline_from_alignment(
            result=result,
            segments=segments,
            sentence_ids=("sentence-0", "sentence-1"),
            subtitle_resource_id="sha256:subtitle-track",
            context=self._context(),
        )
        payload = json.loads(payload_bytes)
        self.assertEqual(
            [(w["sentence_id"], w["token_index"]) for w in payload["words"]],
            [("sentence-0", 0), ("sentence-0", 3), ("sentence-1", 0), ("sentence-1", 2)],
        )
        self.assertTrue(all(w["timing_source"] == "forced_aligned" for w in payload["words"]))
        for word in payload["words"]:
            self.assertLess(word["start_ms"], word["end_ms"])
            self.assertLessEqual(word["end_ms"], 3000)
        self.assertEqual(resource.provenance["provider"], {"id": "qwen3-forced-aligner", "version": "v1"})


if __name__ == "__main__":
    unittest.main()
