#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("evaluate_provider_v2.py")
SPEC = importlib.util.spec_from_file_location("evaluate_provider_v2", SCRIPT)
assert SPEC and SPEC.loader
EVALUATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVALUATOR)


def tokens(values: list[tuple[str, str, str, int | None, str]]) -> list[dict]:
    return [
        {
            "surface": surface,
            "lemma": lemma,
            "upos": upos,
            "head_parser_token_index": head,
            "dependency_relation": relation,
            "features": {},
        }
        for surface, lemma, upos, head, relation in values
    ]


class CorrectedEvaluatorTests(unittest.TestCase):
    def test_clear_subject_with_visible_infinitive_object_blocks(self) -> None:
        parsed = tokens([
            ("Which", "which", "DET", 1, "det"),
            ("candidate", "candidate", "NOUN", 4, "obl:npmod"),
            ("do", "do", "AUX", 4, "aux"),
            ("you", "you", "PRON", 4, "nsubj"),
            ("want", "want", "VERB", None, "root"),
            ("to", "to", "PART", 6, "aux"),
            ("win", "win", "VERB", 4, "xcomp"),
            ("the", "the", "DET", 8, "det"),
            ("election", "election", "NOUN", 6, "obj"),
        ])
        self.assertEqual(EVALUATOR.want_to_query(parsed), "block")

    def test_explicit_infinitive_object_allows(self) -> None:
        parsed = tokens([
            ("Who", "who", "PRON", 5, "obj"),
            ("do", "do", "AUX", 3, "aux"),
            ("you", "you", "PRON", 3, "nsubj"),
            ("want", "want", "VERB", None, "root"),
            ("to", "to", "PART", 5, "aux"),
            ("invite", "invite", "VERB", 3, "xcomp"),
        ])
        self.assertEqual(EVALUATOR.want_to_query(parsed), "allow")

    def test_collapsed_basic_dependency_abstains(self) -> None:
        parsed = tokens([
            ("Which", "which", "DET", 1, "det"),
            ("game", "game", "NOUN", 4, "obl:npmod"),
            ("do", "do", "AUX", 4, "aux"),
            ("you", "you", "PRON", 4, "nsubj"),
            ("want", "want", "VERB", None, "root"),
            ("to", "to", "PART", 6, "aux"),
            ("win", "win", "VERB", 4, "xcomp"),
        ])
        self.assertEqual(EVALUATOR.want_to_query(parsed), "abstain")

    def test_policy_abstain_is_separate_from_attachment_accuracy(self) -> None:
        target = {
            "target": "b.want_to",
            "expected": "abstain",
            "product_expected": "block",
            "evaluation_role": "product_policy",
        }
        parsed = tokens([
            ("Which", "which", "DET", 1, "det"),
            ("team", "team", "NOUN", 4, "dep"),
            ("do", "do", "AUX", 4, "aux"),
            ("you", "you", "PRON", 4, "nsubj"),
            ("want", "want", "VERB", None, "root"),
            ("to", "to", "PART", 6, "aux"),
            ("win", "win", "VERB", 4, "xcomp"),
        ])
        decision = EVALUATOR.score_target(target, parsed)
        self.assertIsNone(decision["raw_correct"])
        self.assertTrue(decision["policy_correct"])
        self.assertEqual(decision["product_actual"], "block")


if __name__ == "__main__":
    unittest.main()
