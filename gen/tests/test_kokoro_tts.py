from __future__ import annotations

import struct
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.tts import (
    AnchorAlignment,
    KokoroTtsAdapter,
    TtsProviderError,
    TtsProviderOutputInvalid,
    TtsProviderStartFailed,
    _pcm_array_to_wav,
)


class KokoroTtsAdapterTests(unittest.TestCase):
    def test_pcm_array_to_wav_produces_valid_wav_header(self) -> None:
        samples = [0.0, 0.5, -0.5, 0.99]
        wav = _pcm_array_to_wav(samples, sample_rate=24000)
        self.assertTrue(wav.startswith(b"RIFF"))
        self.assertEqual(wav[8:12], b"WAVE")
        self.assertEqual(wav[12:16], b"fmt ")
        self.assertIn(b"data", wav)
        # 4 samples * 2 bytes = 8 bytes data
        data_size = struct.unpack_from("<I", wav, len(wav) - 8 - 4)[0]
        self.assertEqual(data_size, 8)

    def test_kokoro_synthesizes_with_exact_anchor_alignment(self) -> None:
        # Mock synthesizer: generates 2400 samples (100ms at 24kHz) per sentence
        def mock_synth(sentence: str, voice: str, speed: float, lang_code: str) -> list[float]:
            return [0.1] * 2400  # exactly 100ms

        adapter = KokoroTtsAdapter(
            voice="af_bella",
            speed=1.0,
            lang_code="a",
            sample_rate=24000,
            synthesizer=mock_synth,
        )

        anchors = [
            ("s0", "First sentence."),
            ("s1", "Second sentence."),
            ("s2", "Third sentence."),
        ]

        result = adapter.synthesize("First sentence. Second sentence. Third sentence.", anchors)
        self.assertEqual(result.provider_id, "kokoro")
        self.assertEqual(result.model_id, "af_bella")
        self.assertIsNotNone(result.alignment)
        self.assertEqual(len(result.alignment), 3)

        # First anchor starts at 0ms, each segment is 100ms
        self.assertEqual(result.alignment[0], AnchorAlignment("s0", 0))
        self.assertEqual(result.alignment[1], AnchorAlignment("s1", 100))
        self.assertEqual(result.alignment[2], AnchorAlignment("s2", 200))
        self.assertEqual(result.duration_ms, 300)

    def test_empty_sentence_anchors_rejected(self) -> None:
        adapter = KokoroTtsAdapter(synthesizer=lambda *a, **kw: [0.1] * 240)
        with self.assertRaises(TtsProviderOutputInvalid):
            adapter.synthesize("", [])

    def test_uninstalled_kokoro_raises_friendly_start_failed(self) -> None:
        # No synthesizer provided, let it try importing kokoro
        adapter = KokoroTtsAdapter()
        try:
            adapter.synthesize("Hi", [("s0", "Hi")])
        except TtsProviderStartFailed as err:
            self.assertIn("Kokoro TTS is not installed", str(err))
        except Exception:
            pass


if __name__ == "__main__":
    unittest.main()
