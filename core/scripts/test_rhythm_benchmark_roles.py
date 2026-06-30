#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
ROLES_PATH = REPO_ROOT / "testdata/rhythm-prosody-benchmarks/benchmark-roles.json"


class RhythmBenchmarkRolesTest(unittest.TestCase):
    def test_required_roles_and_evidence_classes_are_declared(self) -> None:
        document = json.loads(ROLES_PATH.read_text(encoding="utf-8"))
        roles = {row["role"]: row for row in document["roles"]}
        evidence_classes = set(document["evidence_classes"])

        self.assertEqual(document["schema"], "llplayer.rhythm_benchmark_roles.v1")
        self.assertEqual(
            set(roles),
            {
                "evidence_quality",
                "weak_prosody_regression",
                "human_prosody_gold",
                "product_listening_qa",
                "robustness_probe",
            },
        )
        self.assertEqual(
            evidence_classes,
            {"gold", "silver_label", "heuristic_proxy", "manual_product_qa", "coverage"},
        )
        for role in roles.values():
            self.assertIn(
                role["closeout_use"],
                {
                    "supporting_context",
                    "regression_signal",
                    "optional_calibration",
                    "release_gate",
                    "future_probe",
                },
            )
            self.assertTrue(role["datasets"])
            for evidence_class in role["default_evidence_classes"]:
                self.assertIn(evidence_class, evidence_classes)

    def test_product_gate_is_manual_and_helsinki_is_silver_regression(self) -> None:
        document = json.loads(ROLES_PATH.read_text(encoding="utf-8"))
        roles = {row["role"]: row for row in document["roles"]}

        self.assertEqual(roles["product_listening_qa"]["closeout_use"], "release_gate")
        self.assertEqual(roles["product_listening_qa"]["default_evidence_classes"], ["manual_product_qa"])
        self.assertEqual(roles["weak_prosody_regression"]["default_evidence_classes"], ["silver_label"])
        dataset_names = {row["name"] for row in roles["weak_prosody_regression"]["datasets"]}
        self.assertIn("Helsinki Prosody / LibriTTS", dataset_names)


if __name__ == "__main__":
    unittest.main()
