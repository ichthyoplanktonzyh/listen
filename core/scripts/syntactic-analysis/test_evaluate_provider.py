#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("evaluate_provider.py")
SPEC = importlib.util.spec_from_file_location("evaluate_provider", SCRIPT)
assert SPEC and SPEC.loader
EVALUATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EVALUATOR)


def tokens(words: list[tuple[str, str, str, int | None]]) -> list[dict]:
    return [
        {
            "surface": surface,
            "lemma": lemma,
            "upos": upos,
            "dependency_relation": relation,
            "head_parser_token_index": head,
            "features": {},
        }
        for surface, lemma, upos, head, relation in (
            (*item, "dep") if len(item) == 4 else item for item in words
        )
    ]


class EvaluatorTests(unittest.TestCase):
    def test_tokenizer_uses_scalar_offsets_and_preserves_contraction(self) -> None:
        actual = EVALUATOR.tokenize_english("😀 I've re-entered.")
        words = [token for token in actual if token["kind"] == "word"]
        self.assertEqual([token["text"] for token in words], ["I've", "re-entered"])
        self.assertEqual(words[0]["start_char"], 2)

    def test_future_and_motion_pair(self) -> None:
        future = tokens([
            ("going", "go", "VERB", None),
            ("to", "to", "PART", 2),
            ("leave", "leave", "VERB", 0),
        ])
        motion = tokens([
            ("going", "go", "VERB", None),
            ("to", "to", "ADP", 2),
            ("London", "London", "PROPN", 0),
        ])
        self.assertEqual(EVALUATOR.query_future_going_to(future), "allow")
        self.assertEqual(EVALUATOR.query_future_going_to(motion), "block")

    def test_habitual_and_state_pair(self) -> None:
        habitual = tokens([
            ("used", "use", "VERB", None),
            ("to", "to", "PART", 2),
            ("work", "work", "VERB", 0),
        ])
        state = tokens([
            ("is", "be", "AUX", 1),
            ("used", "use", "ADJ", None),
            ("to", "to", "ADP", 3),
            ("working", "work", "VERB", 1),
        ])
        self.assertEqual(EVALUATOR.query_habitual_used_to(habitual), "allow")
        self.assertEqual(EVALUATOR.query_habitual_used_to(state), "block")

    def test_have_to_do_with_is_blocked(self) -> None:
        parsed = tokens([
            ("has", "have", "VERB", None),
            ("to", "to", "PART", 2),
            ("do", "do", "VERB", 0),
            ("with", "with", "ADP", 2),
        ])
        self.assertEqual(EVALUATOR.query_have_to(parsed), "block")

    def test_want_wh_subject_is_blocked(self) -> None:
        parsed = tokens([
            ("Who", "who", "PRON", 5, "nsubj"),
            ("do", "do", "AUX", 2),
            ("you", "you", "PRON", 3),
            ("want", "want", "VERB", None),
            ("to", "to", "PART", 5),
            ("win", "win", "VERB", 3),
        ])
        self.assertEqual(EVALUATOR.query_want_to(parsed), "block")

    def test_want_wh_object_is_also_conservatively_blocked(self) -> None:
        parsed = tokens([
            ("Who", "who", "PRON", 5, "obj"),
            ("do", "do", "AUX", 3),
            ("you", "you", "PRON", 3),
            ("want", "want", "VERB", None),
            ("to", "to", "PART", 5),
            ("invite", "invite", "VERB", 3),
        ])
        self.assertEqual(EVALUATOR.query_want_to(parsed), "block")


if __name__ == "__main__":
    unittest.main()
