#!/usr/bin/env python3
"""Verify that one named Flutter machine-reporter test executed and passed."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


class ReportError(ValueError):
    pass


def verify_report(path: Path, expected_name: str) -> None:
    starts: dict[int, str] = {}
    completions: list[dict] = []
    runner_done: list[dict] = []
    try:
        lines = path.read_text().splitlines()
    except OSError as error:
        raise ReportError(f"cannot read Flutter report: {error}") from error
    if not lines:
        raise ReportError("Flutter report is empty")
    for line_number, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as error:
            raise ReportError(f"malformed JSON on line {line_number}: {error.msg}") from error
        if not isinstance(event, dict):
            raise ReportError(f"event on line {line_number} is not a JSON object")
        kind = event.get("type")
        if kind == "testStart":
            test = event.get("test")
            if not isinstance(test, dict) or not isinstance(test.get("id"), int):
                raise ReportError(f"invalid testStart event on line {line_number}")
            starts[test["id"]] = str(test.get("name", ""))
        elif kind == "testDone":
            completions.append(event)
        elif kind == "done":
            runner_done.append(event)
    target_ids = [test_id for test_id, name in starts.items() if name == expected_name]
    if len(target_ids) != 1:
        raise ReportError(
            f"expected exactly one execution of {expected_name!r}, found {len(target_ids)}"
        )
    target_done = [event for event in completions if event.get("testID") == target_ids[0]]
    if len(target_done) != 1:
        raise ReportError(f"target test has {len(target_done)} completion events")
    event = target_done[0]
    if event.get("skipped") is True or event.get("result") == "skipped":
        raise ReportError("target test was skipped")
    if event.get("result") != "success":
        raise ReportError(f"target test result is {event.get('result')!r}, not success")
    if len(runner_done) != 1 or runner_done[0].get("success") is not True:
        raise ReportError("Flutter runner did not finish successfully")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("expected_name")
    args = parser.parse_args(argv)
    try:
        verify_report(args.report, args.expected_name)
    except ReportError as error:
        print(f"verify-roundtrip: {error}", file=sys.stderr)
        return 1
    print(f"verify-roundtrip: structured report confirms {args.expected_name!r} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
