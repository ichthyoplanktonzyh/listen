"""Unit tests for the subtitle track parser."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from listen_gen.package import ConversionError  # noqa: E402
from listen_gen.subtitle import parse_subtitle  # noqa: E402

SRT = """1
00:00:01,000 --> 00:00:02,500
Hello world.

2
00:00:03,200 --> 00:00:05,000
This is a second line,
wrapped over two lines.

3
00:00:06,000 --> 00:00:07,000
<font color="#fff">Styled</font> plain text.
"""

VTT = """WEBVTT

00:00:01.000 --> 00:00:02.500
Hello world.

NOTE this is a comment

00:00:03.200 --> 00:00:05.000
Second block here.

STYLE
::cue { color: lime; }
"""


class ParseSubtitleTests(unittest.TestCase):
    def _parse(self, text: str, suffix: str) -> tuple:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / f"track{suffix}"
            path.write_text(text, encoding="utf-8")
            return parse_subtitle(path)

    def test_srt_blocks(self) -> None:
        blocks = self._parse(SRT, ".srt")
        self.assertEqual(len(blocks), 3)
        self.assertEqual(blocks[0].text, "Hello world.")
        self.assertEqual(blocks[0].start_ms, 1000)
        self.assertEqual(blocks[0].end_ms, 2500)
        self.assertEqual(blocks[1].text, "This is a second line, wrapped over two lines.")
        self.assertEqual(blocks[1].start_ms, 3200)
        self.assertEqual(blocks[2].text, "Styled plain text.")

    def test_vtt_blocks_skip_layout_notes(self) -> None:
        blocks = self._parse(VTT, ".vtt")
        self.assertEqual(len(blocks), 2)
        self.assertEqual(blocks[0].text, "Hello world.")
        self.assertEqual(blocks[1].text, "Second block here.")
        self.assertEqual(blocks[1].end_ms, 5000)

    def test_crlf_and_utf8_bom(self) -> None:
        blocks = self._parse(SRT.replace("\n", "\r\n"), ".srt")
        self.assertEqual(len(blocks), 3)

    def test_rejects_out_of_order_blocks(self) -> None:
        with self.assertRaises(ConversionError):
            self._parse(
                "1\n00:00:03,000 --> 00:00:04,000\nLate.\n\n"
                "2\n00:00:01,000 --> 00:00:02,000\nEarly.\n",
                ".srt",
            )

    def test_rejects_empty_track(self) -> None:
        with self.assertRaises(ConversionError):
            self._parse("", ".srt")
        with self.assertRaises(ConversionError):
            self._parse("WEBVTT\n\nNOTE nothing here\n", ".vtt")


if __name__ == "__main__":
    unittest.main()
