#!/usr/bin/env python3
"""Tests for production-side RhythmFrame acoustic cue artifacts."""

from __future__ import annotations

import array
import importlib.util
import json
import math
import tempfile
import unittest
import wave
from pathlib import Path


def load_subject():
    path = Path(__file__).with_name("production_pipeline.py")
    spec = importlib.util.spec_from_file_location("production_pipeline_subject", path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


production_pipeline = load_subject()


def write_fixture_wav(path: Path) -> None:
    sample_rate = 16000
    samples = array.array("h")
    for index in range(sample_rate):
        amplitude = 0.05 if index < sample_rate // 2 else 0.55
        value = int(amplitude * 32767 * math.sin(2 * math.pi * 440 * index / sample_rate))
        samples.append(value)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(samples.tobytes())


def fixture_document() -> dict:
    return {
        "schema": "llplayer.timeline.v1",
        "segments": [
            {
                "id": "s1",
                "index": 0,
                "start_ms": 0,
                "end_ms": 1000,
                "text": "quiet loud",
                "display_text": "quiet loud",
                "tokens": [],
            }
        ],
        "word_timelines": [
            {
                "id": "wt1",
                "status": "active",
                "words": [
                    {
                        "sentence_id": "s1",
                        "token_index": 0,
                        "text": "quiet",
                        "start_ms": 0,
                        "end_ms": 500,
                        "timing_source": "forced_aligned",
                    },
                    {
                        "sentence_id": "s1",
                        "token_index": 1,
                        "text": "loud",
                        "start_ms": 500,
                        "end_ms": 1000,
                        "timing_source": "forced_aligned",
                    },
                ],
            }
        ],
        "active_word_timeline_id": "wt1",
        "artifacts": [],
    }


class ProductionPipelineAcousticCueTest(unittest.TestCase):
    def test_appends_rhythm_word_acoustic_cues(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            audio = root / "audio.wav"
            document_path = root / "timeline.lltimeline.json"
            write_fixture_wav(audio)
            document_path.write_text(json.dumps(fixture_document()), encoding="utf-8")

            payload = production_pipeline.append_rhythm_word_acoustic_cues(document_path, audio)

            self.assertEqual(payload["status"], "scored")
            self.assertEqual(payload["timeline_id"], "wt1")
            self.assertEqual(payload["cue_count"], 2)
            cues = {cue["text"]: cue for cue in payload["cues"]}
            self.assertGreater(cues["loud"]["energy_prominence"], cues["quiet"]["energy_prominence"])

            saved = json.loads(document_path.read_text(encoding="utf-8"))
            artifact = saved["artifacts"][0]
            self.assertEqual(artifact["kind"], "rhythm_word_acoustic_cues")
            self.assertEqual(artifact["provider_id"], "rms-word-energy-prominence")
            self.assertEqual(artifact["payload"]["positive_cue_count"], 1)


if __name__ == "__main__":
    unittest.main()
