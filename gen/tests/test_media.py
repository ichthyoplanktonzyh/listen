from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.media import FfmpegAudioPreprocessor
from listen_gen.package import ConversionError


class FfmpegAudioPreprocessorTests(unittest.TestCase):
    ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
    ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"
    single = ROOT / "tests" / "fixtures" / "single-audio-media.json"
    multi = ROOT / "tests" / "fixtures" / "multi-audio-media.json"

    def preprocessor(self, timeout: float = 1) -> FfmpegAudioPreprocessor:
        return FfmpegAudioPreprocessor(
            ffprobe_executable=str(self.ffprobe),
            ffmpeg_executable=str(self.ffmpeg),
            timeout_seconds=timeout,
        )

    def test_single_audio_stream_is_selected_and_normalized(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            observation = Path(directory) / "ffmpeg.json"
            with mock.patch.dict(
                os.environ,
                {"LISTEN_GEN_TEST_FFMPEG_OBSERVATION": str(observation)},
            ):
                with self.preprocessor().prepare(
                    self.single, audio_stream_index=None
                ) as prepared:
                    self.assertEqual(
                        prepared.path.read_bytes(), b"RIFFfake-16khz-mono-pcm"
                    )
                    self.assertEqual(prepared.stream_index, 1)
                    temporary_path = prepared.path
            arguments = json.loads(observation.read_text(encoding="utf-8"))
            self.assertEqual(arguments[arguments.index("-map") + 1], "0:1")
            self.assertEqual(arguments[arguments.index("-ac") + 1], "1")
            self.assertEqual(arguments[arguments.index("-ar") + 1], "16000")
            self.assertEqual(arguments[arguments.index("-c:a") + 1], "pcm_s16le")
            self.assertFalse(temporary_path.exists())

    def test_multiple_audio_streams_require_explicit_selection(self) -> None:
        with self.assertRaisesRegex(ConversionError, "multiple audio streams"):
            with self.preprocessor().prepare(self.multi, audio_stream_index=None):
                pass

        with self.preprocessor().prepare(self.multi, audio_stream_index=3) as prepared:
            self.assertTrue(prepared.path.is_file())
            self.assertEqual(prepared.stream_index, 3)

    def test_missing_stream_selection_is_rejected(self) -> None:
        with self.assertRaisesRegex(ConversionError, "does not exist"):
            with self.preprocessor().prepare(self.multi, audio_stream_index=2):
                pass

    def test_failure_and_timeout_clean_temporary_output_and_redact_details(self) -> None:
        for mode, expected in (("fail", "exit status 29"), ("sleep", "timed out")):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                media = Path(directory) / "media.json"
                value = json.loads(self.single.read_text(encoding="utf-8"))
                value["ffmpeg_mode"] = mode
                media.write_text(json.dumps(value), encoding="utf-8")
                observation = Path(directory) / "ffmpeg.json"
                with mock.patch.dict(
                    os.environ,
                    {"LISTEN_GEN_TEST_FFMPEG_OBSERVATION": str(observation)},
                ):
                    with self.assertRaisesRegex(ConversionError, expected) as raised:
                        with self.preprocessor(timeout=0.3).prepare(
                            media, audio_stream_index=None
                        ):
                            pass
                arguments = json.loads(observation.read_text(encoding="utf-8"))
                temporary_output = Path(arguments[-1])
                self.assertFalse(temporary_output.exists())
                self.assertNotIn(str(media), str(raised.exception))
                self.assertNotIn("transcode-secret", str(raised.exception))


if __name__ == "__main__":
    unittest.main()
