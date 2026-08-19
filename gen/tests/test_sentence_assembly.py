from __future__ import annotations

import sys
import unittest

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.asr import AsrSegment, AsrTranscript, AsrWord  # noqa: E402
from listen_gen.package import ConversionError  # noqa: E402
from listen_gen.rich_stages import (  # noqa: E402
    _words_from_transcript,
    build_word_timeline_resource,
)
from listen_gen.produce import _transcript_matches_reading  # noqa: E402
from listen_gen.sentence_assembly import (  # noqa: E402
    ASSEMBLY_CONFIG_SHA256,
    MAX_ASSEMBLED_CHARS,
    MAX_ASSEMBLED_DURATION_MS,
    MAX_SOURCE_FRAGMENTS,
    assemble_asr_segments,
    assemble_asr_transcript,
    assemble_subtitle_blocks,
    assembly_config_sha256,
)
from listen_gen.subtitle import SubtitleBlock  # noqa: E402


class SentenceAssemblyRegressionTests(unittest.TestCase):
    def test_screenshot_fragments_are_one_sentence(self) -> None:
        segments = (
            AsrSegment(
                start_ms=558940,
                end_ms=561340,
                text="Send us their name, photo, and a couple lines",
                display_text="Send us their name, photo, and a couple lines",
                words=(),
            ),
            AsrSegment(
                start_ms=561340,
                end_ms=565660,
                text="about what they mean to you, CNN10@cnn.com.",
                display_text="about what they mean to you, CNN10@cnn.com.",
                words=(),
            ),
        )

        assembled = assemble_asr_segments(segments)

        self.assertEqual(len(assembled), 1)
        self.assertEqual(
            assembled[0].text,
            "Send us their name, photo, and a couple lines about what they mean to you, CNN10@cnn.com.",
        )

    def test_merge_remaps_word_char_spans_without_changing_absolute_times(self) -> None:
        first_text = "Send us their name, photo, and a couple lines"
        second_text = "about what they mean to you, CNN10@cnn.com."
        first_words = (
            AsrWord(0, 4, 559040, 559200, 0.9, "asr_reported"),
            AsrWord(5, 7, 559220, 559300, 0.9, "asr_reported"),
            AsrWord(8, 13, 559320, 559400, 0.9, "asr_reported"),
            AsrWord(14, 18, 559420, 559500, 0.9, "asr_reported"),
            AsrWord(20, 25, 559520, 559600, 0.9, "asr_reported"),
            AsrWord(27, 30, 559620, 559700, 0.9, "asr_reported"),
            AsrWord(35, 41, 559720, 559800, 0.9, "asr_reported"),
            AsrWord(42, 47, 559820, 559900, 0.9, "asr_reported"),
        )
        second_words = (
            AsrWord(0, 5, 561440, 561600, 0.9, "asr_reported"),
            AsrWord(6, 10, 561620, 561700, 0.9, "asr_reported"),
            AsrWord(11, 15, 561720, 561800, 0.9, "asr_reported"),
            AsrWord(16, 20, 561820, 561900, 0.9, "asr_reported"),
            AsrWord(21, 23, 561920, 562000, 0.9, "asr_reported"),
            AsrWord(24, 28, 562020, 562100, 0.9, "asr_reported"),
        )
        segments = (
            AsrSegment(558940, 561340, first_text, first_text, first_words),
            AsrSegment(561340, 565660, second_text, second_text, second_words),
        )

        sentence = assemble_asr_segments(segments)[0]

        self.assertEqual(sentence.start_ms, 558940)
        self.assertEqual(sentence.end_ms, 565660)
        self.assertEqual(
            [(word.start_ms, word.end_ms) for word in sentence.words],
            [(word.start_ms, word.end_ms) for word in first_words + second_words],
        )
        second_offset = len(first_text) + 1
        self.assertEqual(sentence.words[len(first_words)].start_char, second_offset)
        self.assertEqual(
            sentence.text[sentence.words[len(first_words)].start_char : sentence.words[len(first_words)].end_char],
            "about",
        )

    def test_single_segment_splits_only_with_exact_word_timings(self) -> None:
        text = "Hello world. Bye now."
        words = (
            AsrWord(0, 5, 100, 200, None, "asr_reported"),
            AsrWord(6, 11, 210, 300, None, "asr_reported"),
            AsrWord(13, 16, 400, 500, None, "asr_reported"),
            AsrWord(17, 20, 510, 600, None, "asr_reported"),
        )
        assembled = assemble_asr_segments((AsrSegment(0, 1000, text, text, words),))

        self.assertEqual([sentence.text for sentence in assembled], ["Hello world.", "Bye now."])
        self.assertEqual(
            [(sentence.start_ms, sentence.end_ms) for sentence in assembled],
            [(0, 300), (400, 1000)],
        )
        self.assertEqual(
            [(word.start_char, word.end_char) for word in assembled[1].words],
            [(0, 3), (4, 7)],
        )

    def test_single_segment_without_word_timings_is_not_split(self) -> None:
        text = "Hello world. Bye now."
        assembled = assemble_asr_segments((AsrSegment(0, 1000, text, text, ()),))
        self.assertEqual(len(assembled), 1)
        self.assertEqual(assembled[0].text, text)

    def test_unprovable_cross_boundary_word_keeps_original_fragment(self) -> None:
        text = "Hello. world."
        crossing = AsrWord(0, 7, 100, 200, None, "asr_reported")
        assembled = assemble_asr_segments((AsrSegment(0, 1000, text, text, (crossing,)),))
        self.assertEqual(len(assembled), 1)
        self.assertEqual(assembled[0].text, text)

    def test_mixed_display_mapping_abstains_atomically_without_partial_words(self) -> None:
        source = "Hello world"
        segment = AsrSegment(
            0,
            1000,
            source,
            "Hello planet",
            (
                AsrWord(0, 5, 100, 200, None, "asr_reported"),
                AsrWord(6, 11, 300, 400, None, "asr_reported"),
            ),
        )
        transcript = AsrTranscript(
            language="en",
            segments=(segment,),
            provider_id="fixture",
            provider_version="1",
        )

        assembled = assemble_asr_transcript(transcript)

        self.assertEqual(assembled.segments[0].text, "Hello planet")
        self.assertEqual(assembled.segments[0].display_text, "Hello planet")
        self.assertEqual(assembled.segments[0].words, ())
        self.assertEqual(_words_from_transcript(assembled, ("sentence-0",)), [])
        self.assertIsNone(
            build_word_timeline_resource(
                transcript=assembled,
                sentence_ids=("sentence-0",),
                subtitle_resource_id="sha256:subtitle",
                context=type(
                    "Context",
                    (),
                    {
                        "language": "en",
                        "subject": {},
                        "anchor_resource_id": "sha256:anchor",
                        "rendition_id": "sha256:rendition",
                        "created_at_ms": 1,
                    },
                )(),
                producer={},
            )
        )

    def test_internal_split_requires_timed_boundary_neighbor_tokens(self) -> None:
        text = "Hello world. Bye now."
        missing_second_sentence_first_word = (
            AsrWord(0, 5, 100, 200, None, "asr_reported"),
            AsrWord(6, 11, 210, 300, None, "asr_reported"),
            # ``now`` is timed, but ``Bye``—the first lexical token after the
            # proposed boundary—is not present in the provider result.
            AsrWord(17, 20, 510, 600, None, "asr_reported"),
        )
        assembled = assemble_asr_segments(
            (AsrSegment(0, 1000, text, text, missing_second_sentence_first_word),)
        )
        self.assertEqual(len(assembled), 1)
        self.assertEqual(assembled[0].text, text)

    def test_rich_word_projection_rejects_extra_transcript_sentences(self) -> None:
        transcript = AsrTranscript(
            language="en",
            segments=(
                AsrSegment(0, 100, "One", "One", ()),
                AsrSegment(100, 200, "Two", "Two", ()),
            ),
            provider_id="fixture",
            provider_version="1",
        )
        with self.assertRaises(ConversionError):
            _words_from_transcript(transcript, ("sentence-0",))

    def test_tts_retranscription_must_match_assembled_source_sentence_identity(self) -> None:
        reading_payload = {
            "text": "Hello world.\nSecond line!",
            "anchors": [
                {"anchor_id": "sentence-0", "kind": "sentence", "start_offset": 0, "end_offset": 13},
                {"anchor_id": "sentence-1", "kind": "sentence", "start_offset": 13, "end_offset": 25},
            ],
        }
        fragmented_match = AsrTranscript(
            language="en",
            segments=(
                AsrSegment(0, 100, "Hello", "Hello", ()),
                AsrSegment(100, 200, "world.", "world.", ()),
                AsrSegment(200, 300, "Second line!", "Second line!", ()),
            ),
            provider_id="fixture",
            provider_version="1",
        )
        mismatch = AsrTranscript(
            language="en",
            segments=(
                AsrSegment(0, 100, "Hello", "Hello", ()),
                AsrSegment(100, 200, "earth.", "earth.", ()),
                AsrSegment(200, 300, "Second line!", "Second line!", ()),
            ),
            provider_id="fixture",
            provider_version="1",
        )
        count_mismatch = AsrTranscript(
            language="en",
            segments=(
                AsrSegment(0, 100, "Hello world.", "Hello world.", ()),
            ),
            provider_id="fixture",
            provider_version="1",
        )

        self.assertTrue(
            _transcript_matches_reading(
                assemble_asr_transcript(fragmented_match), reading_payload
            )
        )
        self.assertFalse(
            _transcript_matches_reading(
                assemble_asr_transcript(mismatch), reading_payload
            )
        )
        self.assertFalse(
            _transcript_matches_reading(
                assemble_asr_transcript(count_mismatch), reading_payload
            )
        )

    def test_subtitle_blocks_use_same_merge_policy_without_internal_split(self) -> None:
        blocks = (
            SubtitleBlock("Send us their name, photo, and a couple lines", 100, 300),
            SubtitleBlock("about what they mean to you, CNN10@cnn.com.", 300, 600),
        )
        assembled = assemble_subtitle_blocks(blocks)
        self.assertEqual(len(assembled), 1)
        self.assertEqual(assembled[0].start_ms, 100)
        self.assertEqual(assembled[0].end_ms, 600)
        internal = assemble_subtitle_blocks((SubtitleBlock("One. Two.", 0, 500),))
        self.assertEqual(len(internal), 1)

    def test_email_url_decimal_and_abbreviation_are_not_false_boundaries(self) -> None:
        cases = (
            ("Visit example.com", "today."),
            ("The value is 3.14", "today."),
            ("We met Dr.", "Smith today."),
            ("This is e.g.", "an example."),
        )
        for first, second in cases:
            with self.subTest(first=first):
                assembled = assemble_asr_segments(
                    (
                        AsrSegment(0, 100, first, first, ()),
                        AsrSegment(100, 200, second, second, ()),
                    )
                )
                self.assertEqual(len(assembled), 1)
                self.assertEqual(assembled[0].text, f"{first} {second}")

    def test_cross_fragment_domain_continuations_are_one_sentence(self) -> None:
        cases = (
            (
                "or find much more at BBCLearningEnglish.",
                "com.",
                "or find much more at BBCLearningEnglish.com.",
            ),
            ("Email us at CNN10@cnn.", "com.", "Email us at CNN10@cnn.com."),
            ("Visit example.", "com today.", "Visit example.com today."),
            ("Visit www.example.", "com today.", "Visit www.example.com today."),
        )
        for first, second, expected in cases:
            with self.subTest(first=first):
                assembled = assemble_subtitle_blocks(
                    (
                        SubtitleBlock(first, 0, 100),
                        SubtitleBlock(second, 100, 200),
                    )
                )
                self.assertEqual(len(assembled), 1)
                self.assertEqual(assembled[0].text, expected)

    def test_cross_fragment_true_sentence_is_not_merged_with_completely(self) -> None:
        assembled = assemble_subtitle_blocks(
            (
                SubtitleBlock("It ended.", 0, 100),
                SubtitleBlock("completely new.", 100, 200),
            )
        )
        self.assertEqual(
            [sentence.text for sentence in assembled],
            ["It ended.", "completely new."],
        )

    def test_true_and_unicode_terminators_stop_merging(self) -> None:
        assembled = assemble_subtitle_blocks(
            (
                SubtitleBlock("First.", 0, 100),
                SubtitleBlock("Second!", 100, 200),
                SubtitleBlock("第三句？", 200, 300),
            )
        )
        self.assertEqual([sentence.text for sentence in assembled], ["First.", "Second!", "第三句？"])
        cjk_text = "第一句。第二句！"
        cjk = assemble_asr_segments(
            (
                AsrSegment(
                    0,
                    300,
                    cjk_text,
                    cjk_text,
                    (
                        AsrWord(0, 3, 0, 100, None, "asr_reported"),
                        AsrWord(4, 7, 120, 220, None, "asr_reported"),
                    ),
                ),
            )
        )
        self.assertEqual([sentence.text for sentence in cjk], ["第一句。", "第二句！"])

    def test_safety_bounds_flush_on_prospective_limits(self) -> None:
        long_first = "a" * (MAX_ASSEMBLED_CHARS - 2)
        by_chars = assemble_subtitle_blocks(
            (SubtitleBlock(long_first, 0, 100), SubtitleBlock("tail", 100, 200))
        )
        self.assertEqual(len(by_chars), 2)

        by_duration = assemble_subtitle_blocks(
            (
                SubtitleBlock("first", 0, MAX_ASSEMBLED_DURATION_MS - 1),
                SubtitleBlock("tail", MAX_ASSEMBLED_DURATION_MS - 1, MAX_ASSEMBLED_DURATION_MS + 1),
            )
        )
        self.assertEqual(len(by_duration), 2)

        blocks = tuple(
            SubtitleBlock(f"part-{index}", index * 100, (index + 1) * 100)
            for index in range(MAX_SOURCE_FRAGMENTS + 1)
        )
        by_fragment_count = assemble_subtitle_blocks(blocks)
        self.assertEqual(len(by_fragment_count), 2)

    def test_transcript_provenance_identity_includes_assembly_and_is_deterministic(self) -> None:
        transcript = AsrTranscript(
            language="en",
            segments=(AsrSegment(0, 100, "Hello", "Hello", ()),),
            provider_id="fixture",
            provider_version="1",
            config_sha256="sha256:" + "a" * 64,
        )
        first = assemble_asr_transcript(transcript)
        second = assemble_asr_transcript(transcript)
        self.assertEqual(first, second)
        self.assertNotEqual(first.config_sha256, transcript.config_sha256)
        self.assertEqual(
            first.config_sha256,
            assembly_config_sha256(transcript.config_sha256),
        )
        self.assertTrue(ASSEMBLY_CONFIG_SHA256.startswith("sha256:"))


if __name__ == "__main__":
    unittest.main()
