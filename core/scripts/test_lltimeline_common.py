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


class CJKTokenizeTest(unittest.TestCase):
    def test_chinese_segmented_as_words(self) -> None:
        tokens = tokenize("你好世界")
        words = [t for t in tokens if t["kind"] == "word"]
        self.assertEqual([w["text"] for w in words], ["你好", "世界"])

    def test_chinese_with_punctuation(self) -> None:
        tokens = tokenize("你好，世界！")
        words = [t for t in tokens if t["kind"] == "word"]
        self.assertEqual([w["text"] for w in words], ["你好", "世界"])
        puncts = [t for t in tokens if t["kind"] == "punctuation"]
        self.assertGreaterEqual(len(puncts), 2)

    def test_chinese_normalized_preserves_surface(self) -> None:
        tokens = tokenize("学习")
        words = [t for t in tokens if t["kind"] == "word"]
        self.assertEqual(len(words), 1)
        self.assertEqual(words[0]["text"], "学习")
        self.assertEqual(words[0]["normalized"], "学习")

    def test_mixed_chinese_english(self) -> None:
        tokens = tokenize("Hello你好World")
        words = [t for t in tokens if t["kind"] == "word"]
        self.assertEqual([w["text"] for w in words], ["Hello", "你好", "World"])

    def test_japanese_hiragana(self) -> None:
        tokens = tokenize("たべる")
        words = [t for t in tokens if t["kind"] == "word"]
        self.assertEqual([w["text"] for w in words], ["た", "べ", "る"])

    def test_japanese_katakana(self) -> None:
        tokens = tokenize("カタカナ")
        words = [t for t in tokens if t["kind"] == "word"]
        self.assertEqual([w["text"] for w in words], ["カ", "タ", "カ", "ナ"])

    def test_char_positions_contiguous(self) -> None:
        text = "你好世界"
        tokens = tokenize(text)
        for t in tokens:
            self.assertEqual(text[t["start_char"]:t["end_char"]], t["text"])

    def test_mixed_positions_contiguous(self) -> None:
        text = "Hello，世界"
        tokens = tokenize(text)
        for t in tokens:
            self.assertEqual(text[t["start_char"]:t["end_char"]], t["text"])

    def test_normalize_word_cjk_no_lowercase(self) -> None:
        self.assertEqual(normalize_word("学习"), "学习")

    def test_empty_string(self) -> None:
        self.assertEqual(tokenize(""), [])

    def test_whitespace_only(self) -> None:
        tokens = tokenize("  ")
        self.assertEqual(len(tokens), 1)
        self.assertEqual(tokens[0]["kind"], "whitespace")


if __name__ == "__main__":
    unittest.main()
