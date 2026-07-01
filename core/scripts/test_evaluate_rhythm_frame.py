#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("evaluate-rhythm-frame.py")
SPEC = importlib.util.spec_from_file_location("evaluate_rhythm_frame", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
evaluate_rhythm_frame = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(evaluate_rhythm_frame)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")


def base_document(with_rhythm: bool) -> dict[str, object]:
    sound_analysis: dict[str, object] = {
        "learning_phones": [{"symbol": "DH"}],
        "connected_speech": [],
    }
    if with_rhythm:
        sound_analysis["rhythm_frame"] = {
            "generated_from": "wordtimeline_timing_acoustic_prominence_v1",
            "references": {
                "citation": {
                    "label": "citation_form",
                    "source": "dictionary_lexical_stress",
                    "evidence_class": "heuristic_proxy",
                },
                "default_connected": {
                    "label": "default_connected_variants",
                    "source": "english_connected_speech_rules_v1",
                    "evidence_class": "heuristic_proxy",
                },
                "actual": {
                    "label": "actual_delivery",
                    "source": "word_timeline_duration_energy",
                    "evidence_class": "heuristic_proxy",
                },
            },
            "stress_anchors": [
                {
                    "token_index": 2,
                    "start_ms": 120,
                    "end_ms": 280,
                    "label": "market",
                    "reason": "duration and energy prominence",
                    "importance": "primary",
                    "is_nucleus": True,
                    "prominence": 0.82,
                    "prominence_cues": ["timing", "energy"],
                    "signal_sources": ["timing", "energy"],
                    "evidence_class": "heuristic_proxy",
                    "claim_status": "audio_supported",
                    "confidence": 0.82,
                }
            ],
            "nuclei": [
                {
                    "phrase_index": 0,
                    "token_index": 2,
                    "start_ms": 120,
                    "end_ms": 280,
                    "label": "market",
                    "reason": "phrase-scoped nucleus candidate",
                    "cues": ["timing", "energy"],
                    "evidence_class": "heuristic_proxy",
                    "claim_status": "audio_supported",
                    "confidence": 0.82,
                }
            ],
            "weak_groups": [
                {
                    "token_start": 0,
                    "token_end": 1,
                    "start_ms": 0,
                    "end_ms": 110,
                    "label": "in the",
                    "reason": "short weak material before the anchor",
                    "reduction_refs": ["cs1"],
                    "signal_sources": ["timing"],
                    "evidence_class": "heuristic_proxy",
                    "claim_status": "audio_supported",
                    "confidence": 0.7,
                }
            ],
            "compression_spans": [
                {
                    "token_start": 0,
                    "token_end": 2,
                    "start_ms": 0,
                    "end_ms": 280,
                    "label": "in the market",
                    "reason": "rate-normalized duration is compact",
                    "signal_sources": ["timing"],
                    "evidence_class": "heuristic_proxy",
                    "claim_status": "audio_supported",
                    "confidence": 0.74,
                }
            ],
            "phrase_boundaries": [
                {
                    "at_ms": 300,
                    "after_token_index": 2,
                    "before_token_index": 4,
                    "reason": "pause after the anchor",
                    "cues": ["pause"],
                    "signal_sources": ["timing"],
                    "evidence_class": "heuristic_proxy",
                    "claim_status": "audio_supported",
                    "is_final": False,
                    "confidence": 0.8,
                }
            ],
            "connected_speech_refs": [
                {
                    "id": "cs1",
                    "token_start": 0,
                    "token_end": 1,
                    "label": "weak form",
                    "divergence": "clip_specific",
                    "signal_sources": ["phone_segmental"],
                    "evidence_class": "heuristic_proxy",
                    "confidence": 0.7,
                }
            ],
            "listening_hotspots": [
                {
                    "id": "hs1",
                    "kind": "weak_group",
                    "token_start": 0,
                    "token_end": 1,
                    "start_ms": 0,
                    "end_ms": 110,
                    "label": "weak group",
                    "hint": "backgrounded function words",
                    "signal_sources": ["timing"],
                    "evidence_class": "heuristic_proxy",
                    "claim_status": "audio_supported",
                    "confidence": 0.7,
                }
            ],
            "quality": {
                "timing_source": "word_timeline",
                "prominence_sources": ["timing", "energy"],
                "boundary_sources": ["timing"],
                "connected_speech_source": "phone_segmental",
                "phone_evidence_coverage": 0.9,
                "rhythm_confidence": 0.77,
            },
        }
    return {
        "schema": "llplayer.timeline.v1",
        "segments": [
            {
                "id": "s1",
                "start_ms": 1000,
                "end_ms": 1600,
                "text": "in the market",
            }
        ],
        "phone_timelines": [
            {
                "sentence_id": "s1",
                "sound_analysis": sound_analysis,
            }
        ],
    }


class RhythmFrameEvaluationTest(unittest.TestCase):
    def test_reports_missing_rhythm_frame_for_old_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "case.lltimeline.json"
            write_json(timeline, base_document(with_rhythm=False))
            case = {
                "case_id": "case-1",
                "title": "Case 1",
                "dataset": "fixture",
                "layer": "product_media",
                "lltimeline": {"local_path": str(timeline)},
            }

            result = evaluate_rhythm_frame.evaluate_case(case, root, {})

            self.assertEqual(result["status"], "missing_rhythm_frame")
            self.assertEqual(result["rhythm_frame_sentence_count"], 0)
            self.assertEqual(result["missing_rhythm_frame_count"], 1)

    def test_scores_manual_labels_against_rhythm_frame(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "case.lltimeline.json"
            write_json(timeline, base_document(with_rhythm=True))
            case = {
                "case_id": "case-1",
                "title": "Case 1",
                "dataset": "fixture",
                "layer": "product_media",
                "lltimeline": {"local_path": str(timeline)},
            }
            annotations = {
                ("case-1", "s1"): {
                    "case_id": "case-1",
                    "sentence_id": "s1",
                    "stress_anchors": [{"token_index": 2, "label": "market"}],
                    "nuclei": [{"token_index": 2, "label": "market"}],
                    "weak_groups": [{"token_start": 0, "token_end": 1}],
                    "compression_spans": [{"token_start": 0, "token_end": 2}],
                    "phrase_boundaries": [{"at_ms": 310}],
                    "connected_speech_refs": [{"token_start": 0, "token_end": 1}],
                    "listening_hotspots": [
                        {
                            "token_start": 0,
                            "token_end": 1,
                            "manual_score": "correct",
                        }
                    ],
                    "overall": {"manual_score": "correct"},
                }
            }

            result = evaluate_rhythm_frame.evaluate_case(case, root, annotations)
            sentence = result["sentences"][0]

            self.assertEqual(result["status"], "scored")
            self.assertEqual(result["rhythm_frame_sentence_count"], 1)
            self.assertEqual(sentence["quality"]["rhythm_confidence"], 0.77)
            self.assertEqual(sentence["manual"]["stress_anchors"]["f1"], 1.0)
            self.assertEqual(sentence["manual"]["nuclei"]["f1"], 1.0)
            self.assertEqual(sentence["manual"]["weak_groups"]["f1"], 1.0)
            self.assertEqual(sentence["manual"]["compression_spans"]["f1"], 1.0)
            self.assertEqual(sentence["manual"]["phrase_boundaries"]["f1"], 1.0)
            self.assertEqual(sentence["manual"]["connected_speech_refs"]["f1"], 1.0)
            self.assertEqual(
                sentence["manual"]["listening_hotspots"]["manual_score_counts"]["correct"],
                1,
            )

    def test_template_rows_include_document_level_rhythm_frames(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            document = base_document(with_rhythm=True)
            phone_timeline = document["phone_timelines"][0]  # type: ignore[index]
            sound_analysis = phone_timeline["sound_analysis"]  # type: ignore[index]
            document["phone_timelines"] = []
            document["rhythm_frames"] = [
                {
                    "id": "rf1",
                    "sentence_id": "s1",
                    "rhythm_frame": sound_analysis["rhythm_frame"],  # type: ignore[index]
                }
            ]
            timeline = root / "case.lltimeline.json"
            write_json(timeline, document)
            case = {
                "case_id": "case-1",
                "title": "Case 1",
                "dataset": "fixture",
                "layer": "product_media",
                "lltimeline": {"local_path": str(timeline)},
            }

            rows = evaluate_rhythm_frame.annotation_template_rows(
                case,
                root,
                require_rhythm_frame=True,
            )

            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["system"]["resource_kind"], "rhythm_frame")
            self.assertEqual(rows[0]["nuclei"], [])
            self.assertEqual(rows[0]["connected_speech_refs"], [])

    def test_validates_annotation_shape_and_scores(self) -> None:
        rows = [
            {
                "case_id": "case-1",
                "sentence_id": "s1",
                "transcript": "text",
                "stress_anchors": [{"manual_score": "great"}],
                "weak_groups": [],
                "compression_spans": [],
                "phrase_boundaries": [],
                "listening_hotspots": [{"label": "hotspot"}],
                "overall": {"manual_score": "wrong"},
            },
            {
                "case_id": "case-1",
                "sentence_id": "s1",
                "transcript": "duplicate",
                "stress_anchors": [],
                "weak_groups": [],
                "compression_spans": [],
                "phrase_boundaries": [],
                "listening_hotspots": [],
            },
        ]

        result = evaluate_rhythm_frame.validate_annotation_rows(rows)

        self.assertGreaterEqual(result["error_count"], 3)
        self.assertEqual(result["warning_count"], 1)
        self.assertTrue(
            any("duplicate annotation" in error for error in result["errors"])
        )
        self.assertTrue(
            any("listening hotspot has no manual_score" in warning for warning in result["warnings"])
        )

    def test_aggregates_manual_score_summary(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "case.lltimeline.json"
            write_json(timeline, base_document(with_rhythm=True))
            case = {
                "case_id": "case-1",
                "title": "Case 1",
                "dataset": "fixture",
                "layer": "product_media",
                "lltimeline": {"local_path": str(timeline)},
            }
            annotations = {
                ("case-1", "s1"): {
                    "case_id": "case-1",
                    "sentence_id": "s1",
                    "stress_anchors": [{"token_index": 2}],
                    "nuclei": [{"token_index": 2}],
                    "weak_groups": [{"token_start": 0, "token_end": 1}],
                    "compression_spans": [{"token_start": 0, "token_end": 2}],
                    "phrase_boundaries": [{"at_ms": 300}],
                    "connected_speech_refs": [{"token_start": 0, "token_end": 1}],
                    "listening_hotspots": [
                        {
                            "token_start": 0,
                            "token_end": 1,
                            "manual_score": "useful_but_incomplete",
                        }
                    ],
                    "overall": {"manual_score": "correct"},
                }
            }

            result = evaluate_rhythm_frame.evaluate_case(case, root, annotations)
            summary = evaluate_rhythm_frame.aggregate_results([result])
            manual = summary["manual_qa"]

            self.assertEqual(manual["annotated_sentence_count"], 1)
            self.assertEqual(manual["overall_manual_score_counts"]["correct"], 1)
            self.assertEqual(manual["overall_useful_or_correct_rate"], 1.0)
            self.assertEqual(
                manual["hotspot_manual_score_counts"]["useful_but_incomplete"],
                1,
            )
            self.assertEqual(manual["hotspot_useful_or_correct_rate"], 1.0)
            self.assertEqual(manual["hotspot_misleading_rate"], 0.0)
            self.assertEqual(manual["mean_f1"]["stress_anchors"], 1.0)
            self.assertEqual(manual["mean_f1"]["nuclei"], 1.0)
            self.assertEqual(manual["mean_f1"]["connected_speech_refs"], 1.0)
            self.assertEqual(manual["mean_f1"]["listening_hotspots"], 1.0)

    def test_empty_template_rows_do_not_count_as_manual_annotations(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            timeline = root / "case.lltimeline.json"
            write_json(timeline, base_document(with_rhythm=True))
            case = {
                "case_id": "case-1",
                "title": "Case 1",
                "dataset": "fixture",
                "layer": "product_media",
                "lltimeline": {"local_path": str(timeline)},
            }
            annotations = {
                ("case-1", "s1"): {
                    "case_id": "case-1",
                    "sentence_id": "s1",
                    "transcript": "in the market",
                    "stress_anchors": [],
                    "nuclei": [],
                    "weak_groups": [],
                    "compression_spans": [],
                    "phrase_boundaries": [],
                    "connected_speech_refs": [],
                    "listening_hotspots": [],
                    "overall": {"manual_score": None},
                }
            }

            result = evaluate_rhythm_frame.evaluate_case(case, root, annotations)
            summary = evaluate_rhythm_frame.aggregate_results([result])

            self.assertEqual(summary["manual_qa"]["annotated_sentence_count"], 0)
            self.assertIsNone(summary["manual_qa"]["overall_useful_or_correct_rate"])

    def test_quality_gates_report_pass_and_failure(self) -> None:
        summary = {
            "rhythm_frame_coverage": 0.75,
            "rhythm_frame_sentence_count": 4,
            "word_timeline_rhythm_sentence_count": 3,
            "energy_prominence_sentence_count": 2,
            "manual_qa": {
                "annotated_sentence_count": 4,
                "overall_useful_or_correct_rate": 0.8,
                "hotspot_misleading_rate": 0.1,
                "hotspot_unsupported_rate": 0.2,
            },
        }
        validation = {"error_count": 0}

        passing = evaluate_rhythm_frame.quality_gates(
            summary,
            validation,
            min_rhythm_coverage=0.5,
            min_rhythm_frame_sentences=3,
            min_word_timeline_rhythm_sentences=2,
            min_energy_prominence_sentences=1,
            min_annotated_sentences=3,
            min_overall_useful_rate=0.75,
            max_hotspot_misleading_rate=0.2,
            max_hotspot_unsupported_rate=0.25,
        )
        failing = evaluate_rhythm_frame.quality_gates(
            summary,
            {"error_count": 1},
            min_rhythm_coverage=0.9,
            min_rhythm_frame_sentences=5,
            min_word_timeline_rhythm_sentences=4,
            min_energy_prominence_sentences=3,
            min_annotated_sentences=5,
            min_overall_useful_rate=0.9,
            max_hotspot_misleading_rate=0.05,
            max_hotspot_unsupported_rate=0.1,
        )

        self.assertTrue(passing["passed"])
        self.assertFalse(failing["passed"])
        self.assertEqual(failing["gate_count"], 9)
        self.assertTrue(
            any(gate["name"] == "annotation_validation_errors" for gate in failing["gates"])
        )

    def test_committed_fixture_passes_strict_quality_gate(self) -> None:
        repo_root = SCRIPT_PATH.parents[1]
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "--manifest",
                "testdata/rhythm-frame-qa/fixture-manifest.jsonl",
                "--annotations",
                "testdata/rhythm-frame-qa/fixture-annotations.jsonl",
                "--strict-annotations",
                "--min-rhythm-coverage",
                "1.0",
                "--min-rhythm-frame-sentences",
                "3",
                "--min-word-timeline-rhythm-sentences",
                "3",
                "--min-energy-prominence-sentences",
                "2",
                "--min-annotated-sentences",
                "2",
                "--min-overall-useful-rate",
                "1.0",
                "--max-hotspot-misleading-rate",
                "0.0",
                "--max-hotspot-unsupported-rate",
                "0.0",
                "--fail-on-quality-gate",
            ],
            cwd=repo_root,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        output = json.loads(result.stdout)
        self.assertEqual(output["summary"]["rhythm_frame_coverage"], 1.0)
        self.assertEqual(output["summary"]["phone_timeline_sentence_count"], 3)
        self.assertEqual(output["summary"]["rhythm_frame_sentence_count"], 3)
        self.assertEqual(output["summary"]["word_timeline_rhythm_sentence_count"], 3)
        self.assertEqual(output["summary"]["energy_prominence_sentence_count"], 2)
        self.assertEqual(output["summary"]["manual_qa"]["annotated_sentence_count"], 2)
        self.assertTrue(output["quality_gates"]["passed"])
        no_phone = next(
            case
            for case in output["results"]
            if case["case_id"] == "p221-fixture-no-phone-rhythm-001"
        )
        sentence = no_phone["sentences"][0]
        self.assertEqual(sentence["resource_kind"], "rhythm_frame")
        self.assertEqual(sentence["quality"]["phone_evidence_coverage"], 0.0)
        self.assertEqual(sentence["quality"]["timing_source"], "word_timeline")
        self.assertGreaterEqual(sentence["counts"]["connected_speech_refs"], 1)
        self.assertEqual(sentence["quality"]["connected_speech_source"], "text_prior")
        self.assertGreater(sentence["counts"]["stress_anchors"], 0)
        self.assertGreater(sentence["counts"]["nuclei"], 0)
        self.assertIn("timing", sentence["quality"]["prominence_sources"])


if __name__ == "__main__":
    unittest.main()
