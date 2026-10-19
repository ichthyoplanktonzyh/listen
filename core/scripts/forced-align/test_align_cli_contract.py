#!/usr/bin/env python3
"""Contract tests for align-cli.py helpers without loading torch/torchaudio."""

from __future__ import annotations

import importlib.util
import sys
import types
import unittest
from pathlib import Path


class FakeTokenizer:
    dictionary = list("abcdefghijklmnopqrstuvwxyz'*-")

    def __call__(self, words: list[str]) -> list[list[int]]:
        return [[self.dictionary.index(char) for char in word] for word in words]


class FakeBundle:
    sample_rate = 16000

    @staticmethod
    def get_tokenizer() -> FakeTokenizer:
        return FakeTokenizer()


def load_align_cli():
    sys.modules.setdefault("soundfile", types.SimpleNamespace(read=lambda *args, **kwargs: None))
    sys.modules.setdefault("torch", types.SimpleNamespace())
    sys.modules.setdefault(
        "torchaudio",
        types.SimpleNamespace(
            pipelines=types.SimpleNamespace(MMS_FA=FakeBundle()),
            functional=types.SimpleNamespace(),
        ),
    )
    sys.modules.setdefault("torchaudio.functional", types.SimpleNamespace())

    path = Path(__file__).with_name("align-cli.py")
    spec = importlib.util.spec_from_file_location("align_cli_contract_subject", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AlignCliContractTest(unittest.TestCase):
    def test_tokenize_words_preserves_original_indexes_for_skipped_words(self) -> None:
        align_cli = load_align_cli()

        alignable, token_groups, skipped = align_cli._tokenize_words(
            ["hello", "東京", "world", "---", "o'clock"]
        )

        self.assertEqual(alignable, [(0, "hello"), (2, "world"), (4, "o'clock")])
        self.assertEqual(skipped, [1, 3])
        self.assertEqual(len(token_groups), 3)


if __name__ == "__main__":
    unittest.main()
