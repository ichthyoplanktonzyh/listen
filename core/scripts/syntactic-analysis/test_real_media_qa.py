#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("real_media_qa.py")
SPEC = importlib.util.spec_from_file_location("real_media_qa", SCRIPT)
assert SPEC and SPEC.loader
QA = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(QA)


class RealMediaQaTests(unittest.TestCase):
    def test_srt_parser_joins_multiline_cues_without_leaking_timestamps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.srt"
            path.write_text(
                "1\n00:00:00,000 --> 00:00:01,000\nFirst line\nsecond line\n\n"
                "2\n00:00:01,000 --> 00:00:02,000\nNext cue\n"
            )
            self.assertEqual(
                QA.parse_srt(path),
                [
                    {
                        "case_id": "real-cue-1",
                        "cue_index": 1,
                        "text": "First line second line",
                        "decision_targets": [],
                    },
                    {
                        "case_id": "real-cue-2",
                        "cue_index": 2,
                        "text": "Next cue",
                        "decision_targets": [],
                    },
                ],
            )


if __name__ == "__main__":
    unittest.main()
