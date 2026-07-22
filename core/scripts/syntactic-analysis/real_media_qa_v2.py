#!/usr/bin/env python3
"""Run real-media QA with the corrected v2 want-to abstention query."""

from __future__ import annotations

import importlib.util
from pathlib import Path


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
QA = load("syntactic_real_media_v1", HERE / "real_media_qa.py")
V2 = load("syntactic_evaluator_v2_for_real_media", HERE / "evaluate_provider_v2.py")

# The v1 runner already guarantees no caption text is redistributed. Only the
# neutral want-to query changes; all mapping/tree/determinism measurements stay
# identical and comparable to 3.9.1.
QA.EVALUATOR.query_want_to = V2.want_to_query


if __name__ == "__main__":
    raise SystemExit(QA.main())
