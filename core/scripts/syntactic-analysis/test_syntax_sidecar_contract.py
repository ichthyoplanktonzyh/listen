#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


def load_subject():
    path = Path(__file__).with_name("syntax-sidecar.py")
    spec = importlib.util.spec_from_file_location("syntax_sidecar_contract_subject", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


subject = load_subject()


def subtitle_tokens(text: str) -> list[dict]:
    tokens = []
    chars = list(text)
    start = 0
    while start < len(chars):
        if chars[start].isalnum():
            kind = "word"
            predicate = str.isalnum
        elif chars[start].isspace():
            kind = "whitespace"
            predicate = str.isspace
        else:
            kind = "punctuation"
            predicate = lambda value: not value.isalnum() and not value.isspace()
        end = start + 1
        while end < len(chars) and predicate(chars[end]):
            end += 1
        tokens.append(
            {
                "index": len(tokens),
                "kind": kind,
                "text": "".join(chars[start:end]),
                "start_char": start,
                "end_char": end,
            }
        )
        start = end
    return tokens


class FakeAdapter(subject.ProviderAdapter):
    def _load(self, language: str) -> None:
        if language != "en":
            raise subject.ProviderFailure("unsupported_language", language)
        self._pipeline = True
        self._descriptor = {
            "provider_id": self.config.provider,
            "provider_version": "jsonl-v1",
            "runtime_id": "fake",
            "runtime_version": "1",
            "model_id": self.config.model,
            "model_version": "1",
            "model_checksum_sha256": "a" * 64,
        }

    def analyze(self, language: str, sentence: dict) -> dict:
        self._load(language)
        text = sentence["text"]
        raw = []
        for token in sentence["subtitle_tokens"]:
            if token["kind"] == "whitespace":
                continue
            raw.append(
                {
                    "surface": token["text"],
                    "lemma": token["text"].casefold(),
                    "upos": "PUNCT" if token["kind"] == "punctuation" else "X",
                    "xpos": None,
                    "features": {},
                    "head_parser_token_index": None if not raw else 0,
                    "dependency_relation": "root" if not raw else "dep",
                    "start_char": token["start_char"],
                    "end_char": token["end_char"],
                    "confidence": None,
                }
            )
        aligned, unaligned, coverage = subject.align_tokens(
            text, raw, sentence["subtitle_tokens"]
        )
        return subject._sentence_response(sentence, aligned, unaligned, coverage)


class SidecarContractTest(unittest.TestCase):
    def test_model_checksum_ignores_python_bytecode_cache(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "model.bin").write_bytes(b"qualified-model")
            before = subject._directory_sha256(root)
            cache = root / "__pycache__"
            cache.mkdir()
            (cache / "model.cpython-311.pyc").write_bytes(b"runtime-specific")
            (root / "another.pyc").write_bytes(b"runtime-specific")
            self.assertEqual(subject._directory_sha256(root), before)

    def test_contraction_split_maps_two_parser_tokens_to_one_subtitle_token(self) -> None:
        text = "I'm ready."
        raw = [
            {"surface": "I", "start_char": 0, "end_char": 1},
            {"surface": "'m", "start_char": 1, "end_char": 3},
            {"surface": "ready", "start_char": 4, "end_char": 9},
            {"surface": ".", "start_char": 9, "end_char": 10},
        ]
        source_tokens = [
            {"index": 0, "kind": "word", "text": "I'm", "start_char": 0, "end_char": 3},
            {"index": 1, "kind": "whitespace", "text": " ", "start_char": 3, "end_char": 4},
            {"index": 2, "kind": "word", "text": "ready", "start_char": 4, "end_char": 9},
            {"index": 3, "kind": "punctuation", "text": ".", "start_char": 9, "end_char": 10},
        ]
        aligned, unaligned, coverage = subject.align_tokens(text, raw, source_tokens)
        self.assertEqual(aligned[0]["subtitle_token_indices"], [0])
        self.assertEqual(aligned[1]["subtitle_token_indices"], [0])
        self.assertEqual(aligned[0]["alignment_status"], "split")
        self.assertEqual(unaligned, [])
        self.assertEqual(coverage, 1.0)

    def test_abbreviation_merge_maps_all_non_whitespace_tokens(self) -> None:
        text = "U. S. policy"
        raw = [
            {"surface": "U.S.", "start_char": 0, "end_char": 5},
            {"surface": "policy", "start_char": 6, "end_char": 12},
        ]
        aligned, _, coverage = subject.align_tokens(text, raw, subtitle_tokens(text))
        self.assertEqual(aligned[0]["subtitle_token_indices"], [0, 1, 3, 4])
        self.assertEqual(aligned[0]["alignment_status"], "merged")
        self.assertEqual(coverage, 1.0)

    def test_unicode_offsets_are_python_scalar_offsets_not_utf8_bytes(self) -> None:
        text = "café works"
        raw = [
            {"surface": "café", "start_char": 0, "end_char": 4},
            {"surface": "works", "start_char": 5, "end_char": 10},
        ]
        aligned, _, coverage = subject.align_tokens(text, raw, subtitle_tokens(text))
        self.assertEqual(aligned[0]["end_char"], 4)
        self.assertEqual(coverage, 1.0)

    def test_leading_subtitle_whitespace_is_not_a_parser_token(self) -> None:
        text = " hello"
        raw = [{"surface": "hello", "start_char": 1, "end_char": 6}]
        aligned, unaligned, coverage = subject.align_tokens(
            text, raw, subtitle_tokens(text)
        )
        self.assertEqual(aligned[0]["subtitle_token_indices"], [1])
        self.assertEqual(unaligned, [])
        self.assertEqual(coverage, 1.0)

    def test_unmapped_word_is_explicit(self) -> None:
        text = "hello 2026"
        raw = [{"surface": "hello", "start_char": 0, "end_char": 5}]
        _, unaligned, coverage = subject.align_tokens(text, raw, subtitle_tokens(text))
        self.assertEqual(unaligned, [2])
        self.assertEqual(coverage, 0.5)

    def test_invalid_parser_span_is_closed_invalid_output(self) -> None:
        with self.assertRaises(subject.ProviderFailure) as raised:
            subject.align_tokens(
                "hello", [{"surface": "hello", "start_char": 0, "end_char": 99}], subtitle_tokens("hello")
            )
        self.assertEqual(raised.exception.kind, "invalid_output")

    def test_jsonl_stdout_contains_only_one_response_per_request(self) -> None:
        adapter = FakeAdapter(subject.ProviderConfig("fake", "fake-model", None))
        requests = [
            json.dumps(
                {
                    "protocol_version": 1,
                    "request_id": "probe-1",
                    "operation": "probe",
                    "provider": "fake",
                    "language": "en",
                }
            ),
            "not json",
            json.dumps(
                {
                    "protocol_version": 1,
                    "request_id": "analyze-1",
                    "operation": "analyze",
                    "provider": "fake",
                    "language": "en",
                    "sentences": [
                        {
                            "sentence_id": "s1",
                            "text": "New York works.",
                            "subtitle_tokens": subtitle_tokens("New York works."),
                        }
                    ],
                }
            ),
        ]
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            result = subject.run_jsonl(adapter, requests)
        self.assertEqual(result, 0)
        responses = [json.loads(line) for line in stdout.getvalue().splitlines()]
        self.assertEqual(len(responses), 3)
        self.assertTrue(responses[0]["ok"])
        self.assertFalse(responses[1]["ok"])
        self.assertEqual(responses[1]["error"]["kind"], "protocol")
        self.assertTrue(responses[2]["ok"])
        self.assertNotIn("syntax-sidecar", stdout.getvalue())
        self.assertIn("syntax-sidecar", stderr.getvalue())

    def test_missing_stanza_runtime_is_probeable_without_import_crash(self) -> None:
        adapter = subject.StanzaAdapter(subject.ProviderConfig("stanza", "ewt", None))
        with mock.patch.object(subject.importlib.util, "find_spec", return_value=None):
            with self.assertRaises(subject.ProviderFailure) as raised:
                adapter.descriptor("en")
        self.assertEqual(raised.exception.kind, "runtime_missing")

    def test_unknown_language_is_closed_error(self) -> None:
        adapter = FakeAdapter(subject.ProviderConfig("fake", "fake-model", None))
        request = {
            "protocol_version": 1,
            "request_id": "probe-zh",
            "operation": "probe",
            "provider": "fake",
            "language": "zh",
        }
        with self.assertRaises(subject.ProviderFailure) as raised:
            subject.handle_request(adapter, request)
        self.assertEqual(raised.exception.kind, "unsupported_language")


if __name__ == "__main__":
    unittest.main()
