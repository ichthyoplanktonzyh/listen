from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

from listen_gen.phone import (
    G2pPhoneAdapter,
    CommandPhoneAdapter,
    DetectedPhone,
    FixturePhoneAdapter,
    PhoneRequest,
    PhoneResult,
    Wav2Vec2CtcPhoneAdapter,
    _annotate_phones,
    _parse_result,
    run_phone,
)
from listen_gen.rich import RichStageFailure
from listen_gen.rich import RichWord

ROOT = Path(__file__).resolve().parents[1]


def assert_process_reaped(test: unittest.TestCase, pid: int) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    test.fail(f"phone provider process {pid} is still alive")


def _words() -> tuple[RichWord, ...]:
    return (
        RichWord(sentence_id="s0", sentence_index=0, token_index=0, start_ms=200, end_ms=400),
        RichWord(sentence_id="s0", sentence_index=0, token_index=1, start_ms=500, end_ms=700),
        RichWord(sentence_id="s0", sentence_index=0, token_index=2, start_ms=800, end_ms=1000),
    )


def _result(phones: list[DetectedPhone]) -> PhoneResult:
    return PhoneResult(
        phones=tuple(phones),
        phone_set="ipa",
        provider_id="test",
        provider_version="1",
    )


class ObservedPhoneAnnotationTests(unittest.TestCase):
    def test_detected_times_are_preserved_verbatim(self) -> None:
        # Observed phones keep their real audio-derived time; nothing is
        # clamped to a word window.
        phones = _annotate_phones(
            _result([
                DetectedPhone("t", 150, 450),
                DetectedPhone("u", 450, 720),
            ]),
            _words(),
        )
        self.assertEqual(
            [(phone["symbol"], phone["start_ms"], phone["end_ms"]) for phone in phones],
            [("t", 150, 450), ("u", 450, 720)],
        )

    def test_phone_wholly_inside_one_word_is_annotated(self) -> None:
        phones = _annotate_phones(
            _result([
                DetectedPhone("t", 200, 400),
                DetectedPhone("u", 520, 680),
            ]),
            _words(),
        )
        self.assertEqual(
            [phone["word_ref"] for phone in phones],
            [
                {"sentence_id": "s0", "token_index": 0},
                {"sentence_id": "s0", "token_index": 1},
            ],
        )

    def test_cross_boundary_phone_keeps_null_word_ref_and_is_retained(self) -> None:
        # A phone that spans the gap between two words (linking / assimilation)
        # is never forced onto the left or right word and is never dropped.
        phones = _annotate_phones(
            _result([
                DetectedPhone("t", 200, 400),
                DetectedPhone("dʒ", 380, 520),  # spans word 0 -> word 1
                DetectedPhone("u", 520, 680),
            ]),
            _words(),
        )
        self.assertEqual([phone["symbol"] for phone in phones], ["t", "dʒ", "u"])
        self.assertIsNone(phones[1]["word_ref"])
        self.assertEqual(phones[1]["start_ms"], 380)
        self.assertEqual(phones[1]["end_ms"], 520)

    def test_gap_phone_keeps_null_word_ref_and_is_retained(self) -> None:
        phones = _annotate_phones(
            _result([
                DetectedPhone("t", 200, 400),
                DetectedPhone("g", 410, 490),  # entirely in the inter-word gap
                DetectedPhone("u", 500, 700),
            ]),
            _words(),
        )
        self.assertEqual(len(phones), 3)
        self.assertIsNone(phones[1]["word_ref"])

    def test_no_words_keeps_every_phone_with_null_word_ref(self) -> None:
        # Phone identity is time, not word: with no word timeline every phone is
        # still emitted, only the optional annotation is null.
        phones = _annotate_phones(_result([DetectedPhone("t", 200, 400)]), ())
        self.assertEqual(len(phones), 1)
        self.assertIsNone(phones[0]["word_ref"])

    def test_empty_phones_abstains(self) -> None:
        with self.assertRaises(RichStageFailure) as caught:
            _annotate_phones(_result([]), _words())
        self.assertEqual(caught.exception.code, "phone_qualification_failed")


class G2pPhoneAdapterTests(unittest.TestCase):
    def test_g2p_no_longer_fabricates_observed_timing(self) -> None:
        # Canonical phonemes carry no audio-observed timing, so the adapter
        # abstains instead of spreading a word's duration across its phonemes.
        def mock_g2p(word: str) -> list[str]:
            return ["h", "e", "l", "o"]

        adapter = G2pPhoneAdapter(g2p_fn=mock_g2p)
        words = (
            RichWord(sentence_id="s0", sentence_index=0, token_index=0, start_ms=0, end_ms=400),
            RichWord(sentence_id="s0", sentence_index=0, token_index=1, start_ms=500, end_ms=900),
        )
        request = PhoneRequest(audio_path=Path("/fake/audio.wav"), words=words)
        with self.assertRaises(RichStageFailure) as caught:
            adapter.analyze(request)
        self.assertEqual(caught.exception.code, "phone_qualification_failed")


if __name__ == "__main__":
    unittest.main()
