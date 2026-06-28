#!/usr/bin/env python3
"""Lightweight verifier for sound-line real-media QA pack.

Validates manifest.jsonl structure, checks file existence, and inspects
.lltimeline.json schema/shape when available.

Usage:
    python scripts/verify-sound-line-real-media.py \
        --manifest testdata/sound-line-real-media/manifest.jsonl

    python scripts/verify-sound-line-real-media.py \
        --manifest testdata/sound-line-real-media/manifest.jsonl --strict-local

    python scripts/verify-sound-line-real-media.py \
        --manifest testdata/sound-line-real-media/manifest.jsonl --json

    python scripts/verify-sound-line-real-media.py \
        --manifest testdata/sound-line-real-media/manifest.jsonl --require-ready
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

VALID_LAYERS = {"phone_gold", "natural_connected_speech", "product_media", "supplemental"}
VALID_STATUSES = {"possible_by_rule", "supported_by_audio", "detected_in_audio"}
CASE_ID_RE = re.compile(r"^[a-z][a-z0-9-]*$")
REQUIRED_MANIFEST_FIELDS = [
    "case_id", "title", "dataset", "layer", "language", "license",
    "source", "media", "lltimeline", "targets", "qa_notes",
]


def expand_path(raw: str) -> Path:
    if raw.startswith("~/"):
        return Path.home() / raw[2:]
    return Path(raw)


def red(text: str) -> str:
    return f"\033[31m{text}\033[0m"


def yellow(text: str) -> str:
    return f"\033[33m{text}\033[0m"


def green(text: str) -> str:
    return f"\033[32m{text}\033[0m"


def log_error(msg: str) -> None:
    print(f"  {red('ERROR')}: {msg}")


def log_warning(msg: str) -> None:
    print(f"  {yellow('WARNING')}: {msg}")


def log_ok(msg: str) -> None:
    print(f"  {green('OK')}: {msg}")


def validate_manifest_line(line: str, lineno: int) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    try:
        case = json.loads(line)
    except json.JSONDecodeError as e:
        return None, [f"line {lineno}: invalid JSON: {e}"]
    if not isinstance(case, dict):
        return None, [f"line {lineno}: not a JSON object"]

    case_id = case.get("case_id", "")
    prefix = f"[{case_id}]" if case_id else f"line {lineno}"

    for field in REQUIRED_MANIFEST_FIELDS:
        if field not in case:
            errors.append(f"{prefix}: missing required field '{field}'")

    if case_id:
        if not CASE_ID_RE.match(str(case_id)):
            errors.append(f"{prefix}: case_id must be lowercase ASCII, digits, hyphens only")
    else:
        errors.append(f"{prefix}: case_id is empty")

    layer = case.get("layer", "")
    if layer and layer not in VALID_LAYERS:
        errors.append(f"{prefix}: invalid layer '{layer}', allowed: {sorted(VALID_LAYERS)}")

    if not isinstance(case.get("targets"), dict):
        errors.append(f"{prefix}: targets must be an object")
    else:
        targets = case["targets"]
        if not isinstance(targets.get("phenomena"), list):
            errors.append(f"{prefix}: targets.phenomena must be a list")
        if not isinstance(targets.get("expected_connected_speech_families"), list):
            errors.append(f"{prefix}: targets.expected_connected_speech_families must be a list")
        if not isinstance(targets.get("min_manual_observations"), int):
            errors.append(f"{prefix}: targets.min_manual_observations must be an integer")

    if not isinstance(case.get("license"), dict):
        errors.append(f"{prefix}: license must be an object")
    if not isinstance(case.get("source"), dict):
        errors.append(f"{prefix}: source must be an object")
    if not isinstance(case.get("media"), dict):
        errors.append(f"{prefix}: media must be an object")
    if not isinstance(case.get("lltimeline"), dict):
        errors.append(f"{prefix}: lltimeline must be an object")

    return case, errors


def check_file_existence(case: dict[str, Any], repo_root: Path, strict_local: bool) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    case_id = case["case_id"]

    # Check QA notes file
    qa_notes_path = repo_root / case["qa_notes"]
    if not qa_notes_path.is_file():
        errors.append(f"[{case_id}]: qa_notes file not found: {case['qa_notes']}")

    # Check lltimeline file
    llt = case["lltimeline"]
    timeline_rel = llt.get("path", "")
    if timeline_rel:
        timeline_path = repo_root / timeline_rel
        if timeline_path.is_file():
            pass  # exists, will validate later
        elif llt.get("local_only"):
            msg = f"[{case_id}]: lltimeline not found (local_only): {timeline_rel}"
            if strict_local:
                errors.append(msg)
            else:
                warnings.append(msg)
        else:
            errors.append(f"[{case_id}]: lltimeline not found (not local_only): {timeline_rel}")

    # Check media file
    media = case.get("media", {})
    media_path_str = media.get("local_path", "")
    if media_path_str:
        media_path = expand_path(media_path_str)
        if not media_path.exists() and not media_path.is_dir():
            warnings.append(f"[{case_id}]: media file not found: {media_path_str}")
        elif media.get("sha256") and media_path.is_file():
            # Verify sha256 if provided
            pass  # skip full hash verification for speed; can add later

    # Check subtitle file if present
    subtitle = case.get("subtitle")
    if isinstance(subtitle, dict):
        sub_path_str = subtitle.get("local_path", "")
        if sub_path_str:
            sub_path = expand_path(sub_path_str)
            if not sub_path.is_file():
                warnings.append(f"[{case_id}]: subtitle file not found: {sub_path_str}")

    return errors, warnings


def validate_timeline(timeline_path: Path, case_id: str) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []

    try:
        doc = json.loads(timeline_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        return [f"[{case_id}]: cannot parse timeline: {e}"], []

    schema = doc.get("schema", "")
    if schema != "llplayer.timeline.v1":
        errors.append(f"[{case_id}]: timeline schema is '{schema}', expected 'llplayer.timeline.v1'")

    # Check top-level fields
    for field in ("segments", "word_timelines", "phone_timelines"):
        if field not in doc or not isinstance(doc[field], list):
            warnings.append(f"[{case_id}]: timeline missing or empty '{field}'")

    # Check phone_timelines
    phone_timelines = doc.get("phone_timelines") or []
    has_learning_phones = False
    has_connected_speech = False

    for pt_idx, pt in enumerate(phone_timelines):
        if not isinstance(pt, dict):
            continue
        pt_status = pt.get("status", "unknown")
        if pt_status not in ("active", "candidate", "archived"):
            continue

        sa = pt.get("sound_analysis")
        if not isinstance(sa, dict):
            continue

        # Check learning_phones
        lp_list = sa.get("learning_phones")
        if isinstance(lp_list, list) and lp_list:
            has_learning_phones = True
            for lp_idx, lp in enumerate(lp_list):
                if not isinstance(lp, dict):
                    continue
                start_ms = lp.get("start_ms")
                end_ms = lp.get("end_ms")
                if isinstance(start_ms, (int, float)) and isinstance(end_ms, (int, float)):
                    if end_ms <= start_ms:
                        errors.append(
                            f"[{case_id}]: phone_timelines[{pt_idx}].learning_phones[{lp_idx}] "
                            f"end_ms({end_ms}) <= start_ms({start_ms})"
                        )
                conf = lp.get("confidence")
                if isinstance(conf, (int, float)) and (conf < 0 or conf > 1):
                    errors.append(
                        f"[{case_id}]: phone_timelines[{pt_idx}].learning_phones[{lp_idx}] "
                        f"confidence {conf} outside [0,1]"
                    )

        # Check connected_speech
        cs_list = sa.get("connected_speech")
        if isinstance(cs_list, list) and cs_list:
            has_connected_speech = True
            for cs_idx, cs in enumerate(cs_list):
                if not isinstance(cs, dict):
                    continue
                # Check phone range bounds
                phone_start = cs.get("phone_start")
                phone_end = cs.get("phone_end")
                if isinstance(phone_start, int) and isinstance(phone_end, int):
                    if phone_end < phone_start:
                        errors.append(
                            f"[{case_id}]: phone_timelines[{pt_idx}].connected_speech[{cs_idx}] "
                            f"phone_end({phone_end}) < phone_start({phone_start})"
                        )
                    # Check doesn't exceed learning_phones bounds
                    if isinstance(lp_list, list) and phone_start >= len(lp_list):
                        errors.append(
                            f"[{case_id}]: phone_timelines[{pt_idx}].connected_speech[{cs_idx}] "
                            f"phone_start({phone_start}) >= learning_phones length({len(lp_list)})"
                        )
                    if isinstance(lp_list, list) and phone_end >= len(lp_list):
                        errors.append(
                            f"[{case_id}]: phone_timelines[{pt_idx}].connected_speech[{cs_idx}] "
                            f"phone_end({phone_end}) >= learning_phones length({len(lp_list)})"
                        )
                    if (
                        isinstance(lp_list, list)
                        and 0 <= phone_start <= phone_end < len(lp_list)
                    ):
                        window = playback_window_from_learning_phones(
                            lp_list[phone_start:phone_end + 1]
                        )
                        if window is None:
                            errors.append(
                                f"[{case_id}]: phone_timelines[{pt_idx}].connected_speech[{cs_idx}] "
                                "cannot derive playback window from learning_phones"
                            )
                        elif window < 40 or window > 1500:
                            errors.append(
                                f"[{case_id}]: phone_timelines[{pt_idx}].connected_speech[{cs_idx}] "
                                f"derived playback window ({window}ms) outside [40, 1500]"
                            )

                # Check status
                status = cs.get("status")
                if status and status not in VALID_STATUSES:
                    errors.append(
                        f"[{case_id}]: phone_timelines[{pt_idx}].connected_speech[{cs_idx}] "
                        f"invalid status '{status}'"
                    )

                conf = cs.get("confidence")
                if isinstance(conf, (int, float)) and (conf < 0 or conf > 1):
                    errors.append(
                        f"[{case_id}]: phone_timelines[{pt_idx}].connected_speech[{cs_idx}] "
                        f"confidence {conf} outside [0,1]"
                    )

    if not has_learning_phones:
        warnings.append(f"[{case_id}]: no active/candidate PhoneTimeline with learning_phones")
    if not has_connected_speech:
        warnings.append(f"[{case_id}]: no active/candidate PhoneTimeline with connected_speech")

    return errors, warnings


def playback_window_from_learning_phones(phones: list[Any]) -> int | None:
    starts: list[int] = []
    ends: list[int] = []
    for phone in phones:
        if not isinstance(phone, dict):
            return None
        start_ms = phone.get("start_ms")
        end_ms = phone.get("end_ms")
        if not isinstance(start_ms, int) or not isinstance(end_ms, int):
            return None
        starts.append(start_ms)
        ends.append(end_ms)
    if not starts or not ends:
        return None
    return max(ends) - min(starts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, help="path to manifest.jsonl")
    parser.add_argument("--strict-local", action="store_true",
                        help="treat missing local-only resources as errors")
    parser.add_argument("--json", action="store_true",
                        help="output summary as JSON")
    parser.add_argument("--require-ready", action="store_true",
                        help="require at least one timeline with learning_phones and connected_speech")
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    if not manifest_path.is_file():
        print(f"ERROR: manifest not found: {args.manifest}", file=sys.stderr)
        return 1

    repo_root = Path(__file__).resolve().parents[1]
    manifest_dir = manifest_path.parent

    all_errors: list[str] = []
    all_warnings: list[str] = []

    # Phase 1: Parse manifest
    lines = [l.strip() for l in manifest_path.read_text(encoding="utf-8").splitlines() if l.strip()]
    if not lines:
        all_errors.append("manifest is empty")
        return 1

    cases: list[dict[str, Any]] = []
    seen_ids: set[str] = set()

    for idx, line in enumerate(lines, start=1):
        case, parse_errors = validate_manifest_line(line, idx)
        if case is None:
            all_errors.extend(parse_errors)
            continue
        all_errors.extend(parse_errors)
        case_id = case["case_id"]
        if case_id in seen_ids:
            all_errors.append(f"duplicate case_id: {case_id}")
        seen_ids.add(case_id)
        cases.append(case)

    if not args.json:
        print(f"Parsed {len(cases)} cases from manifest")

    # Phase 2: Check file existence
    for case in cases:
        errs, warns = check_file_existence(case, repo_root, args.strict_local)
        all_errors.extend(errs)
        all_warnings.extend(warns)

    # Phase 3: Validate timelines
    timeline_cases = 0
    connected_speech_cases = 0
    learning_phone_cases = 0
    for case in cases:
        llt_rel = case["lltimeline"].get("path", "")
        if not llt_rel:
            continue
        llt_path = repo_root / llt_rel
        if not llt_path.is_file():
            continue
        timeline_cases += 1
        errs, warns = validate_timeline(llt_path, case["case_id"])
        all_errors.extend(errs)
        all_warnings.extend(warns)

        # Quick check for connected_speech presence (without full parse overhead)
        try:
            doc = json.loads(llt_path.read_text(encoding="utf-8"))
            for pt in doc.get("phone_timelines") or []:
                if not isinstance(pt, dict):
                    continue
                sa = pt.get("sound_analysis")
                if isinstance(sa, dict):
                    cs = sa.get("connected_speech")
                    if isinstance(cs, list) and cs:
                        connected_speech_cases += 1
                        break
                if isinstance(sa, dict):
                    lp = sa.get("learning_phones")
                    if isinstance(lp, list) and lp:
                        learning_phone_cases += 1
                        break
        except Exception:
            pass

    # Phase 4: Global checks
    if args.require_ready:
        if learning_phone_cases == 0:
            all_errors.append("readiness check failed: no timeline case has sound_analysis.learning_phones")
        if connected_speech_cases == 0:
            all_errors.append("readiness check failed: no timeline case has sound_analysis.connected_speech")

    if not args.json:
        print(f"File checks: {sum(1 for e in all_errors if 'timeline not found' not in e and 'media file not found' not in e)} hard errors, {len(all_warnings)} warnings")
        if all_errors:
            print(f"\nErrors ({len(all_errors)}):")
            for err in all_errors:
                print(f"  {red('E')} {err}")
        if all_warnings:
            print(f"\nWarnings ({len(all_warnings)}):")
            for warn in all_warnings:
                print(f"  {yellow('W')} {warn}")

    has_hard_errors = bool(all_errors)

    if args.json:
        summary = {
            "case_count": len(cases),
            "timeline_case_count": timeline_cases,
            "connected_speech_case_count": connected_speech_cases,
            "learning_phone_case_count": learning_phone_cases,
            "error_count": len(all_errors),
            "warning_count": len(all_warnings),
            "ready": learning_phone_cases > 0 and connected_speech_cases > 0,
            "require_ready": args.require_ready,
            "errors": all_errors[:50],
            "warnings": all_warnings[:50],
            "valid": not has_hard_errors,
        }
        print(json.dumps(summary, indent=2, sort_keys=True))

    return 1 if has_hard_errors else 0


if __name__ == "__main__":
    sys.exit(main())
