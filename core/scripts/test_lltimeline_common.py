#!/usr/bin/env python3
"""Tests for shared LLTimeline text/token helpers."""

from __future__ import annotations

import unittest

from lltimeline_common import normalize_word, tokenize, word_key, word_token_indexes


class LLTimelineCommonTest(unittest.TestCase):
    def test_tokenize_handles_multi_apostrophe_words(self) -> None:
        tokens = tokenize("don't've o'clock 'em")
        words = [token for token in tokens if token["kind"] == "word"]

        self.assertEqual([word["text"] for word in words], ["don't've", "o'clock", "'em"])
        self.assertEqual(word_token_indexes(tokens), [0, 2, 4])

    def test_normalize_word_matches_pipeline_expectations(self) -> None:
        self.assertEqual(normalize_word("’Hello!’"), "hello")
        self.assertEqual(normalize_word("O’Clock"), "o'clock")

    def test_word_key_casts_to_stable_types(self) -> None:
        self.assertEqual(word_key({"sentence_id": 7, "token_index": "3"}), ("7", 3))


if __name__ == "__main__":
    unittest.main()
