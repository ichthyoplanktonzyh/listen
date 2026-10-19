#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("prepare-rhythm-acoustic-qa.py")
SPEC = importlib.util.spec_from_file_location("prepare_rhythm_acoustic_qa", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
prepare_rhythm_acoustic_qa = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = prepare_rhythm_acoustic_qa
SPEC.loader.exec_module(prepare_rhythm_acoustic_qa)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in rows),
        encoding="utf-8",
    )


def write_fixture_wav(path: Path) -> None:
    sample_rate = 16000
    duration_ms = 900
    frames = []
    for index in range(int(sample_rate * duration_ms / 1000)):
        ms = index * 1000 / sample_rate
        if 120 <= ms < 570:
            amplitude = 0.70
        elif 610 <= ms < 790:
            amplitude = 0.14
        else:
            amplitude = 0.05
        sample = int(32767 * amplitude * math.sin(2 * math.pi * 220 * index / sample_rate))
        frames.append(struct.pack("<h", sample))
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(sample_rate)
        wav.writeframes(b"".join(frames))


def fixture_document(audio_path: Path) -> dict[str, object]:
    return {
        "schema": "llplayer.timeline.v1",
        "metadata": {
            "media": {
                "id": "media-1",
                "path": str(audio_path),
                "duration_ms": 900,
            },
            "language": "en",
        },
        "segments": [
            {
                "id": "s1",
                "index": 0,
                "start_ms": 0,
                "end_ms": 850,
                "text": "The market opened.",
                "display_text": "The market opened.",
            }
        ],
        "word_timelines": [
            {
                "id": "wt1",
                "algorithm_id": "fixture-forced-aligner",
                "algorithm_version": "v1",
                "status": "active",
                "words": [
                    {
                        "sentence_id": "s1",
                        "token_index": 0,
                        "text": "The",
                        "start_ms": 0,
                        "end_ms": 120,
                        "timing_source": "forced_aligned",
                        "provider_id": "fixture-aligner",
                    },
                    {
                        "sentence_id": "s1",
                        "token_index": 2,
                        "text": "market",
                        "start_ms": 120,
                        "end_ms": 570,
                        "timing_source": "forced_aligned",
                        "provider_id": "fixture-aligner",
                    },
                    {
                        "sentence_id": "s1",
                        "token_index": 4,
                        "text": "opened",
                        "start_ms": 610,
                        "end_ms": 790,
                        "timing_source": "forced_aligned",
                        "provider_id": "fixture-aligner",
                    },
                ],
            }
        ],
        "active_word_timeline_id": "wt1",
        "phone_timelines": [
            {
                "id": "pt1",
                "sentence_id": "s1",
                "sound_analysis": {
                    "rhythm_frame": {
                        "generated_from": "fixture-current-ctc",
                        "stress_anchors": [
                            {
                                "token_index": 2,
                                "start_ms": 120,
                                "end_ms": 570,
                                "label": "market",
                                "confidence": 0.9,
                                "evidence": ["text_predicted"],
                            }
                        ],
                        "weak_groups": [],
                        "compression_spans": [],
                        "phrase_boundaries": [],
                        "listening_hotspots": [],
                        "quality": {
                            "timing_source": "phone_timeline",
                            "phone_evidence_coverage": 0.8,
                            "rhythm_confidence": 0.7,
                        },
                    }
                },
            }
        ],
    }


class PrepareRhythmAcousticQaTest(unittest.TestCase):
    def test_builds_duration_and_rms_comparison_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            audio = root / "fixture.wav"
            timeline = root / "case.lltimeline.json"
            manifest = root / "manifest.jsonl"
            write_fixture_wav(audio)
            write_json(timeline, fixture_document(audio))
            write_jsonl(
                manifest,
                [
                    {
                        "case_id": "case-1",
                        "title": "Fixture",
                        "dataset": "fixture",
                        "media": {"local_path": str(audio)},
                        "lltimeline": {"local_path": str(timeline)},
                    }
                ],
            )

            report = prepare_rhythm_acoustic_qa.build_report(
                argparse.Namespace(
                    manifest=str(manifest),
                    case_id=None,
                    sentence_id=None,
                    limit=10,
                    audio_padding_ms=0,
                ),
                root,
            )

            self.assertEqual(report["summary"]["selected_sentence_count"], 1)
            self.assertEqual(report["summary"]["scored_sentence_count"], 1)
            self.assertEqual(report["summary"]["current_rhythm_frame_count"], 1)
            row = report["results"][0]["sentences"][0]
            self.assertEqual(row["status"], "scored")
            self.assertEqual(row["word_timeline"]["timing_source_mix"], {"forced_aligned": 3})
            self.assertEqual(
                row["current_rhythm_frame"]["stress_anchors"][0]["evidence"],
                ["text_predicted"],
            )
            duration_anchor_labels = {
                item["label"] for item in row["duration_rate"]["duration_anchor_candidates"]
            }
            self.assertIn("market", duration_anchor_labels)
            compression_labels = {
                item["label"] for item in row["duration_rate"]["compression_candidates"]
            }
            self.assertIn("opened", compression_labels)
            energy_labels = {
                item["label"] for item in row["rms_energy"]["prominence_candidates"]
            }
            self.assertIn("market", energy_labels)
            self.assertEqual(row["rms_energy"]["audio_source"], "wave")

    def test_reports_missing_word_timing_without_failing_audio_template(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            audio = root / "fixture.wav"
            timeline = root / "case.lltimeline.json"
            manifest = root / "manifest.jsonl"
            write_fixture_wav(audio)
            document = fixture_document(audio)
            document["word_timelines"] = []
            document["active_word_timeline_id"] = None
            write_json(timeline, document)
            write_jsonl(
                manifest,
                [
                    {
                        "case_id": "case-1",
                        "media": {"local_path": str(audio)},
                        "lltimeline": {"local_path": str(timeline)},
                    }
                ],
            )

            report = prepare_rhythm_acoustic_qa.build_report(
                argparse.Namespace(
                    manifest=str(manifest),
                    case_id=None,
                    sentence_id=None,
                    limit=10,
                    audio_padding_ms=0,
                ),
                root,
            )

            row = report["results"][0]["sentences"][0]
            self.assertEqual(row["status"], "missing_word_timing")
            template = prepare_rhythm_acoustic_qa.manual_template_row(row)
            self.assertEqual(template["system_compare"]["status"], "missing_word_timing")
            self.assertEqual(template["stress_anchors"], [])
            self.assertIn("overall", template)

    def test_cli_emit_template_outputs_schema_compatible_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            audio = root / "fixture.wav"
            timeline = root / "case.lltimeline.json"
            manifest = root / "manifest.jsonl"
            write_fixture_wav(audio)
            write_json(timeline, fixture_document(audio))
            write_jsonl(
                manifest,
                [
                    {
                        "case_id": "case-1",
                        "media": {"local_path": str(audio)},
                        "lltimeline": {"local_path": str(timeline)},
                    }
                ],
            )

            completed = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT_PATH),
                    "--manifest",
                    str(manifest),
                    "--emit-template",
                ],
                check=True,
                capture_output=True,
                text=True,
            )

            rows = [json.loads(line) for line in completed.stdout.splitlines() if line.strip()]
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["case_id"], "case-1")
            self.assertEqual(rows[0]["sentence_id"], "s1")
            self.assertIn("system_compare", rows[0])
            for required in (
                "stress_anchors",
                "weak_groups",
                "compression_spans",
                "phrase_boundaries",
                "listening_hotspots",
            ):
                self.assertIsInstance(rows[0][required], list)


if __name__ == "__main__":
    unittest.main()
