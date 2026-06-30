#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("evaluate-helsinki-prosody.py")
SPEC = importlib.util.spec_from_file_location("evaluate_helsinki_prosody", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
evaluate_helsinki_prosody = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evaluate_helsinki_prosody)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


def fixture_document(with_rhythm: bool = True) -> dict[str, object]:
    sound_analysis: dict[str, object] = {
        "learning_phones": [],
        "connected_speech": [],
    }
    if with_rhythm:
        sound_analysis["rhythm_frame"] = {
            "generated_from": "fixture",
            "stress_anchors": [
                {"token_index": 2, "label": "market", "confidence": 0.9},
                {"token_index": 4, "label": "opened", "confidence": 0.8},
            ],
            "weak_groups": [],
            "compression_spans": [],
            "phrase_boundaries": [
                {
                    "after_token_index": 4,
                    "before_token_index": 6,
                    "evidence": "pause",
                    "confidence": 0.9,
                }
            ],
            "listening_hotspots": [],
            "quality": {"rhythm_confidence": 0.88},
        }
    return {
        "schema": "llplayer.timeline.v1",
        "segments": [
            {
                "id": "s1",
                "start_ms": 0,
                "end_ms": 1500,
                "text": "The market opened early.",
            }
        ],
        "phone_timelines": [
            {
                "id": "phones-s1",
                "sentence_id": "s1",
                "sound_analysis": sound_analysis,
            }
        ],
    }


class HelsinkiProsodyEvaluationTest(unittest.TestCase):
    def test_parses_helsinki_label_file_and_counts_labels(self) -> None:
        labels_path = Path("testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt")

        labels = evaluate_helsinki_prosody.parse_helsinki_labels(labels_path)
        summary = evaluate_helsinki_prosody.label_summary(labels)

        self.assertEqual(len(labels), 1)
        self.assertEqual(labels[0]["source_file"], "fixture_000001_000001_000000_000000.txt")
        self.assertEqual(summary["sentence_count"], 1)
        self.assertEqual(summary["word_count"], 4)
        self.assertEqual(summary["prominence_counts"]["2"], 1)
        self.assertEqual(summary["boundary_counts"]["2"], 1)
        self.assertEqual(summary["prominence_counts"]["NA"], 1)

    def test_scores_rhythm_frame_against_prominence_and_boundary_labels(self) -> None:
        labels_path = Path("testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "fixture.lltimeline.json"
            manifest = root / "manifest.jsonl"
            write_json(timeline, fixture_document())
            manifest.write_text(
                json.dumps(
                    {
                        "source_file": "fixture_000001_000001_000000_000000.txt",
                        "sentence_id": "s1",
                        "lltimeline": {"local_path": str(timeline)},
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            labels = evaluate_helsinki_prosody.parse_helsinki_labels(labels_path)
            result = evaluate_helsinki_prosody.evaluate(
                labels,
                Path.cwd(),
                lltimeline_manifest=manifest,
                prominence_threshold=1,
                boundary_threshold=2,
            )

            summary = result["score_summary"]
            self.assertEqual(summary["scored_sentence_count"], 1)
            self.assertEqual(summary["stress_anchors"]["f1"], 1.0)
            self.assertEqual(summary["phrase_boundaries"]["f1"], 1.0)
            self.assertEqual(summary["predicted_boundary_evidence_counts"], {"pause": 1})
            self.assertEqual(result["sentences"][0]["text_matches_labels"], True)
            self.assertEqual(result["benchmark_context"]["evidence_class"], "silver_label")
            self.assertEqual(result["benchmark_context"]["reported_baselines"][0]["value"], 0.832)

    def test_reports_missing_rhythm_frame_separately_from_missing_timeline(self) -> None:
        labels_path = Path("testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "fixture.lltimeline.json"
            manifest = root / "manifest.jsonl"
            write_json(timeline, fixture_document(with_rhythm=False))
            manifest.write_text(
                json.dumps(
                    {
                        "source_file": "fixture_000001_000001_000000_000000.txt",
                        "sentence_id": "s1",
                        "lltimeline": {"local_path": str(timeline)},
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            labels = evaluate_helsinki_prosody.parse_helsinki_labels(labels_path)
            result = evaluate_helsinki_prosody.evaluate(
                labels,
                Path.cwd(),
                lltimeline_manifest=manifest,
            )

            self.assertEqual(result["score_summary"]["status_counts"]["missing_rhythm_frame"], 1)
            self.assertEqual(result["score_summary"]["scored_sentence_count"], 0)

    def test_baseline_without_phone_timeline_reports_missing_rhythm_frame(self) -> None:
        labels_path = Path("testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "fixture.lltimeline.json"
            manifest = root / "manifest.jsonl"
            document = fixture_document()
            document["phone_timelines"] = []
            write_json(timeline, document)
            manifest.write_text(
                json.dumps(
                    {
                        "source_file": "fixture_000001_000001_000000_000000.txt",
                        "sentence_id": "s1",
                        "lltimeline": {"local_path": str(timeline)},
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            labels = evaluate_helsinki_prosody.parse_helsinki_labels(labels_path)
            result = evaluate_helsinki_prosody.evaluate(
                labels,
                Path.cwd(),
                lltimeline_manifest=manifest,
            )

            self.assertEqual(result["score_summary"]["status_counts"]["missing_rhythm_frame"], 1)

    def test_falls_back_to_text_match_when_manifest_sentence_id_was_remapped(self) -> None:
        labels_path = Path("testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt")
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "fixture.lltimeline.json"
            manifest = root / "manifest.jsonl"
            document = fixture_document()
            document["segments"][0]["id"] = "remapped-s1"
            document["phone_timelines"][0]["sentence_id"] = "remapped-s1"
            write_json(timeline, document)
            manifest.write_text(
                json.dumps(
                    {
                        "source_file": "fixture_000001_000001_000000_000000.txt",
                        "sentence_id": "original-s1",
                        "lltimeline": {"local_path": str(timeline)},
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            labels = evaluate_helsinki_prosody.parse_helsinki_labels(labels_path)
            result = evaluate_helsinki_prosody.evaluate(
                labels,
                Path.cwd(),
                lltimeline_manifest=manifest,
            )

            self.assertEqual(result["score_summary"]["status_counts"]["scored"], 1)
            self.assertEqual(result["score_summary"]["stress_anchors"]["f1"], 1.0)

    def test_committed_fixture_passes_cli_quality_gate(self) -> None:
        repo_root = SCRIPT_PATH.parents[1]
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "--labels",
                "testdata/rhythm-prosody-benchmarks/fixture-helsinki.txt",
                "--lltimeline-manifest",
                "testdata/rhythm-prosody-benchmarks/fixture-manifest.jsonl",
                "--min-scored-sentences",
                "1",
                "--min-anchor-f1",
                "1.0",
                "--min-boundary-f1",
                "1.0",
                "--fail-on-quality-gate",
            ],
            cwd=repo_root,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        output = json.loads(result.stdout)
        self.assertTrue(output["quality_gates"]["passed"])

    def test_raw_lltimeline_token_indexes_map_to_word_indexes(self) -> None:
        words = ["the", "market", "opened", "early", "today"]

        self.assertEqual(evaluate_helsinki_prosody.map_raw_index(0, words), 0)
        self.assertEqual(evaluate_helsinki_prosody.map_raw_index(2, words), 1)
        self.assertEqual(evaluate_helsinki_prosody.map_raw_index(6, words), 3)
        self.assertEqual(evaluate_helsinki_prosody.map_raw_index(3, words), 3)


if __name__ == "__main__":
    unittest.main()
