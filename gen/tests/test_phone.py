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
    CommandPhoneAdapter,
    DetectedPhone,
    FixturePhoneAdapter,
    PhoneRequest,
    PhoneResult,
    Wav2Vec2CtcPhoneAdapter,
    _anchor_phones,
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


class PhoneAnchoringTests(unittest.TestCase):
    def test_every_phone_anchored_is_retained(self) -> None:
        phones = _anchor_phones(
            _result([
                DetectedPhone("t", 200, 400),
                DetectedPhone("u", 500, 700),
                DetectedPhone("v", 800, 1000),
            ]),
            _words(),
        )
        self.assertEqual([phone["symbol"] for phone in phones], ["t", "u", "v"])
        self.assertEqual(phones[0]["word_ref"], {"sentence_id": "s0", "token_index": 0})

    def test_gap_phones_are_dropped_when_most_anchor(self) -> None:
        phones = _anchor_phones(
            _result([
                DetectedPhone("t", 200, 400),
                DetectedPhone("g", 400, 500),
                DetectedPhone("u", 500, 700),
                DetectedPhone("v", 800, 1000),
            ]),
            _words(),
        )
        self.assertEqual([phone["symbol"] for phone in phones], ["t", "u", "v"])

    def test_phone_time_is_clamped_into_its_anchored_word(self) -> None:
        phones = _anchor_phones(
            _result([
                DetectedPhone("t", 150, 450),
                DetectedPhone("u", 450, 750),
            ]),
            _words(),
        )
        self.assertEqual(
            [(phone["symbol"], phone["start_ms"], phone["end_ms"]) for phone in phones],
            [("t", 200, 400), ("u", 500, 700)],
        )
        self.assertEqual(
            [phone["word_ref"] for phone in phones],
            [
                {"sentence_id": "s0", "token_index": 0},
                {"sentence_id": "s0", "token_index": 1},
            ],
        )

    def test_low_anchoring_ratio_abstains(self) -> None:
        with self.assertRaises(RichStageFailure) as caught:
            _anchor_phones(
                _result([
                    DetectedPhone("t", 200, 400),
                    DetectedPhone("g", 400, 500),
                    DetectedPhone("g", 700, 800),
                    DetectedPhone("g", 1000, 1100),
                ]),
                _words(),
            )
        self.assertEqual(caught.exception.code, "phone_qualification_failed")

    def test_no_words_is_upstream_missing(self) -> None:
        with self.assertRaises(RichStageFailure) as caught:
            _anchor_phones(_result([DetectedPhone("t", 200, 400)]), ())
        self.assertEqual(caught.exception.code, "phone_upstream_missing")


if __name__ == "__main__":
    unittest.main()
