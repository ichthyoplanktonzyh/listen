from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.structured_reading import build_reading_structure, text_from_segments


class StructuredReadingTests(unittest.TestCase):
    def test_media_segments_keep_sentence_identity_and_time_anchor_shape(self) -> None:
        text = text_from_segments(("Listen carefully!", "Words matter."))
        self.assertEqual(text.text, "Listen carefully!\nWords matter.")
        self.assertEqual(
            [sentence.id for sentence in text.sentences],
            ["sentence-0", "sentence-1"],
        )
        self.assertEqual(text.sentences[0].text, "Listen carefully!\n")
        self.assertEqual(text.paragraphs[0].end_char, len("Listen carefully!"))
        self.assertEqual(text.blocks[0].kind, "root")

    def test_structured_reading_uses_utf8_offsets_and_no_document_mappings(self) -> None:
        reading = build_reading_structure(
            text_from_segments(("你好。", "Next!")),
            language="zh-Hans",
        ).structured_reading
        self.assertEqual(reading["text"], "你好。\nNext!")
        anchors = reading["anchors"]
        self.assertIsInstance(anchors, list)
        sentence_anchors = [entry for entry in anchors if entry["kind"] == "sentence"]
        self.assertEqual(
            [(entry["start_offset"], entry["end_offset"]) for entry in sentence_anchors],
            [(0, 10), (10, 15)],
        )
        self.assertEqual(reading["document_mappings"], [])
        self.assertEqual(reading["language"], "zh-Hans")

    def test_empty_text_has_empty_anchors_for_upstream_abstention(self) -> None:
        reading = build_reading_structure(
            text_from_segments(()),
            language="en-US",
        ).structured_reading
        self.assertEqual(reading["text"], "")
        self.assertEqual(reading["anchors"], [])
        self.assertEqual(reading["blocks"][0]["kind"], "root")


if __name__ == "__main__":
    unittest.main()
