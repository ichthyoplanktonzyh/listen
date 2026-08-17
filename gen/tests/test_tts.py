from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.tts import (
    AnchorAlignment,
    FakeTtsAdapter,
    FixtureTtsAdapter,
    SayTtsAdapter,
    TtsProviderError,
    TtsProviderOutputInvalid,
)

FIXTURES = ROOT / "tests" / "fixtures"


class FakeTtsAdapterTests(unittest.TestCase):
    def test_is_deterministic(self) -> None:
        adapter = FakeTtsAdapter()
        anchors = [("sentence-0", "Hello world."), ("sentence-1", "Second!")]
        first = adapter.synthesize("Hello world. Second!", anchors)
        second = adapter.synthesize("Hello world. Second!", anchors)
        self.assertEqual(first.audio_bytes, second.audio_bytes)
        self.assertEqual(first.alignment, second.alignment)

    def test_produces_valid_wav(self) -> None:
        adapter = FakeTtsAdapter()
        result = adapter.synthesize("Hello.", [("sentence-0", "Hello.")])
        self.assertEqual(result.media_type, "audio/wav")
        self.assertTrue(result.audio_bytes.startswith(b"RIFF"))
        self.assertIn(b"WAVE", result.audio_bytes[:16])

    def test_alignment_is_exact_and_monotonic(self) -> None:
        adapter = FakeTtsAdapter()
        result = adapter.synthesize(
            "First sentence here.",
            [("sentence-0", "First sentence here."), ("sentence-1", "Second.")],
        )
        self.assertIsNotNone(result.alignment)
        times = [entry.media_time_ms for entry in result.alignment or ()]
        self.assertEqual(times, sorted(times))
        self.assertEqual((result.alignment or ())[0].anchor_id, "sentence-0")
        self.assertEqual((result.alignment or ())[0].media_time_ms, 0)

    def test_empty_text_produces_empty_alignment(self) -> None:
        adapter = FakeTtsAdapter()
        result = adapter.synthesize("", [])
        self.assertEqual(result.alignment, ())


class FixtureTtsAdapterTests(unittest.TestCase):
    def test_replays_audio(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "audio.wav"
            audio.write_bytes(b"FIXTURE-AUDIO")
            adapter = FixtureTtsAdapter(audio)
            result = adapter.synthesize("ignored", [])
            self.assertEqual(result.audio_bytes, b"FIXTURE-AUDIO")
            self.assertIsNone(result.alignment)

    def test_replays_alignment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "audio.wav"
            audio.write_bytes(b"FIXTURE-AUDIO")
            alignment = Path(directory) / "alignment.json"
            alignment.write_text(
                json.dumps([{"anchor_id": "sentence-0", "media_time_ms": 250}]),
                encoding="utf-8",
            )
            adapter = FixtureTtsAdapter(audio, alignment)
            result = adapter.synthesize("x", [])
            self.assertEqual(
                result.alignment, (AnchorAlignment("sentence-0", 250),)
            )

    def test_invalid_alignment_is_a_provider_output_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            audio = Path(directory) / "audio.wav"
            audio.write_bytes(b"FIXTURE-AUDIO")
            alignment = Path(directory) / "alignment.json"
            alignment.write_text("not json", encoding="utf-8")
            adapter = FixtureTtsAdapter(audio, alignment)
            with self.assertRaises(TtsProviderOutputInvalid):
                adapter.synthesize("x", [])

    def test_missing_audio_rejected_at_construction(self) -> None:
        with self.assertRaises(ValueError):
            FixtureTtsAdapter(Path("/does/not/exist.wav"))


class SayTtsAdapterTests(unittest.TestCase):
    def test_runs_say_per_sentence_and_reports_real_alignment(self) -> None:
        adapter = SayTtsAdapter(
            say_executable=str(FIXTURES / "fake_say.py"),
            afconvert_executable=str(FIXTURES / "fake_afconvert.py"),
        )
        result = adapter.synthesize(
            "Hello. Second sentence!",
            [("sentence-0", "Hello."), ("sentence-1", "Second sentence!")],
        )
        self.assertEqual(result.media_type, "audio/mp4")
        self.assertEqual(len(result.audio_bytes), 44 + 2 * 32000)
        self.assertIsNotNone(result.alignment)
        self.assertEqual(result.alignment, (
            AnchorAlignment("sentence-0", 0),
            AnchorAlignment("sentence-1", 1000),
        ))
        self.assertEqual(result.duration_ms, 2000)
        self.assertEqual(result.provider_id, "say")
        self.assertIsNotNone(result.config_sha256)

    def test_missing_executable_is_a_start_failure(self) -> None:
        adapter = SayTtsAdapter(
            say_executable=str(Path("/nonexistent/say-tool")),
            afconvert_executable=str(FIXTURES / "fake_afconvert.py"),
        )
        with self.assertRaises(TtsProviderError):
            adapter.synthesize("Hello.", [])


if __name__ == "__main__":
    unittest.main()
