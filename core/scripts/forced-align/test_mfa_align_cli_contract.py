#!/usr/bin/env python3
"""Contract tests for mfa-align-cli.py helper functions."""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


def load_mfa_cli():
    path = Path(__file__).with_name("mfa-align-cli.py")
    spec = importlib.util.spec_from_file_location("mfa_align_cli_contract_subject", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class MFAAlignCliContractTest(unittest.TestCase):
    def test_textgrid_words_convert_to_global_timings(self) -> None:
        mfa_cli = load_mfa_cli()
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp)
            (output_dir / "seg_000007.TextGrid").write_text(
                """File type = "ooTextFile"
Object class = "TextGrid"

xmin = 0
xmax = 1
tiers? <exists>
size = 1
item []:
    item [1]:
        class = "IntervalTier"
        name = "words"
        xmin = 0
        xmax = 1
        intervals: size = 3
        intervals [1]:
            xmin = 0
            xmax = 0.1
            text = ""
        intervals [2]:
            xmin = 0.1
            xmax = 0.4
            text = "hello"
        intervals [3]:
            xmin = 0.4
            xmax = 0.9
            text = "world"
""",
                encoding="utf-8",
            )
            result = mfa_cli.timings_from_textgrids(
                [
                    {
                        "segment_index": 7,
                        "start_ms": 1000,
                        "end_ms": 2000,
                        "words": ["hello", "world"],
                        "basename": "seg_000007",
                    }
                ],
                output_dir,
            )

        self.assertEqual(len(result["timings"]), 2)
        self.assertEqual(result["timings"][0]["segment_index"], 7)
        self.assertEqual(result["timings"][0]["word_index"], 0)
        self.assertEqual(result["timings"][0]["start_ms"], 1100)
        self.assertEqual(result["timings"][0]["end_ms"], 1400)
        self.assertEqual(result["timings"][1]["start_ms"], 1400)
        self.assertEqual(result["timings"][1]["end_ms"], 1900)

    def test_align_one_records_single_segment_failure_without_raising(self) -> None:
        mfa_cli = load_mfa_cli()
        args = argparse.Namespace(
            acoustic_model="english_us_arpa",
            dictionary="english_us_arpa",
            jobs=2,
            mfa_bin="/tmp/fake-mfa",
            mfa_root_dir="/tmp/fake-mfa-root",
            quiet=True,
        )
        prepared = [
            {
                "segment_index": 24,
                "start_ms": 0,
                "end_ms": 1000,
                "words": ["hello"],
                "basename": "seg_000024",
            },
            {
                "segment_index": 25,
                "start_ms": 1000,
                "end_ms": 2000,
                "words": ["world"],
                "basename": "seg_000025",
            },
        ]

        def fake_run(command, check, env):  # noqa: ANN001 - mirrors subprocess.run for the contract.
            if "seg_000025.wav" in command[2]:
                raise subprocess.CalledProcessError(1, command)
            return subprocess.CompletedProcess(command, 0)

        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(mfa_cli.subprocess, "run", side_effect=fake_run):
            failures = mfa_cli.run_mfa_align_one(
                args,
                prepared,
                Path(tmp) / "corpus",
                Path(tmp) / "mfa-output",
                Path(tmp) / "mfa-temp",
            )
            result = mfa_cli.timings_from_textgrids(
                prepared,
                Path(tmp) / "mfa-output",
                align_one_failures=failures,
            )

        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0]["segment_index"], 25)
        self.assertEqual(failures[0]["reason"], "mfa_align_one_failed")
        self.assertEqual(result["diagnostics"]["skipped"][0]["reason"], "textgrid_missing")
        self.assertEqual(result["diagnostics"]["skipped"][1]["reason"], "mfa_align_one_failed")
        self.assertIn("align_one_failures", result["diagnostics"])


if __name__ == "__main__":
    unittest.main()
