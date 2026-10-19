#!/usr/bin/env python3
"""Prepare Phase 2.20 duration/RMS evidence for manual rhythm QA.

This is an experiment harness, not the production RhythmFrame generator. It
compares the current CTC-derived ``sound_analysis.rhythm_frame`` with an active
WordTimeline timing skeleton and per-word RMS energy measured from local audio.
The output is designed for a 5-10 sentence manual QA pass before promoting any
new acoustic evidence into product generation.
"""

from __future__ import annotations

import argparse
import array
import json
import math
import shutil
import statistics
import subprocess
import sys
import wave
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any


EXPERIMENT_ID = "phase_2_20_duration_rms_manual_qa_v1"
TARGET_SAMPLE_RATE = 16000
PROMINENCE_DELTA_DB = 3.0
DURATION_ANCHOR_RATIO = 1.35
COMPRESSION_RATIO = 0.72
BOUNDARY_GAP_MS = 150
BOUNDARY_LENGTHENING_RATIO = 1.5


@dataclass(frozen=True)
class AudioWindow:
    samples: list[float]
    sample_rate_hz: int
    start_ms: int
    end_ms: int
    source: str


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        value = json.loads(line)
        if not isinstance(value, dict):
            raise ValueError(f"{path}:{lineno}: expected JSON object")
        rows.append(value)
    return rows


def expand_path(raw: str | None, repo_root: Path) -> Path | None:
    if not isinstance(raw, str) or not raw:
        return None
    path = Path(raw).expanduser()
    return path if path.is_absolute() else repo_root / path


def as_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(round(value))
    return None


def as_float(value: Any) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


def round_float(value: float | None, digits: int = 6) -> float | None:
    return round(value, digits) if value is not None and math.isfinite(value) else None


def safe_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def median(values: list[float]) -> float | None:
    clean = [value for value in values if math.isfinite(value)]
    return statistics.median(clean) if clean else None


def normalize_token(value: Any) -> str:
    text = str(value or "").lower()
    return "".join(ch for ch in text if ch.isalnum() or ch == "'").strip("'")


def expected_units(text: Any) -> int:
    return max(1, len(normalize_token(text)))


def active_word_timeline(document: dict[str, Any]) -> dict[str, Any] | None:
    timelines = [value for value in safe_list(document.get("word_timelines")) if isinstance(value, dict)]
    active_id = document.get("active_word_timeline_id")
    if isinstance(active_id, str):
        for timeline in timelines:
            if timeline.get("id") == active_id:
                return timeline
    for timeline in timelines:
        if timeline.get("status") == "active":
            return timeline
    return timelines[0] if timelines else None


def segments_by_id(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values: dict[str, dict[str, Any]] = {}
    for segment in safe_list(document.get("segments")):
        if isinstance(segment, dict) and isinstance(segment.get("id"), str):
            values[segment["id"]] = segment
    return values


def ordered_segments(document: dict[str, Any]) -> list[dict[str, Any]]:
    return sorted(
        [segment for segment in safe_list(document.get("segments")) if isinstance(segment, dict)],
        key=lambda segment: (
            as_int(segment.get("start_ms")) is None,
            as_int(segment.get("start_ms")) or 0,
            as_int(segment.get("index")) or 0,
        ),
    )


def phone_timelines_by_sentence(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values: dict[str, dict[str, Any]] = {}
    for timeline in safe_list(document.get("phone_timelines")):
        if isinstance(timeline, dict) and isinstance(timeline.get("sentence_id"), str):
            values[timeline["sentence_id"]] = timeline
    return values


def compact_evidence(value: Any) -> Any:
    if isinstance(value, list):
        return [str(item) for item in value]
    if isinstance(value, str):
        return value
    return None


def compact_item(item: dict[str, Any], fields: tuple[str, ...]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for field in fields:
        if field in item:
            value[field] = item[field]
    if "confidence" in item:
        value["confidence"] = round_float(as_float(item.get("confidence")))
    evidence = compact_evidence(item.get("evidence"))
    if evidence is not None:
        value["evidence"] = evidence
    return value


def compact_rhythm_frame(phone_timeline: dict[str, Any] | None) -> dict[str, Any]:
    sound_analysis = phone_timeline.get("sound_analysis") if isinstance(phone_timeline, dict) else None
    frame = sound_analysis.get("rhythm_frame") if isinstance(sound_analysis, dict) else None
    if not isinstance(frame, dict):
        return {"status": "missing_rhythm_frame"}
    quality = frame.get("quality") if isinstance(frame.get("quality"), dict) else {}
    return {
        "status": "present",
        "generated_from": frame.get("generated_from"),
        "quality": {
            "timing_source": quality.get("timing_source"),
            "phone_evidence_coverage": round_float(as_float(quality.get("phone_evidence_coverage"))),
            "rhythm_confidence": round_float(as_float(quality.get("rhythm_confidence"))),
        },
        "stress_anchors": [
            compact_item(
                item,
                ("token_index", "start_ms", "end_ms", "label", "importance", "reason"),
            )
            for item in safe_list(frame.get("stress_anchors"))
            if isinstance(item, dict)
        ],
        "weak_groups": [
            compact_item(
                item,
                ("token_start", "token_end", "anchor_token_index", "start_ms", "end_ms", "label", "reason"),
            )
            for item in safe_list(frame.get("weak_groups"))
            if isinstance(item, dict)
        ],
        "compression_spans": [
            compact_item(
                item,
                (
                    "token_start",
                    "token_end",
                    "start_ms",
                    "end_ms",
                    "label",
                    "duration_ms",
                    "unit_rate_per_second",
                    "reason",
                ),
            )
            for item in safe_list(frame.get("compression_spans"))
            if isinstance(item, dict)
        ],
        "phrase_boundaries": [
            compact_item(
                item,
                ("after_token_index", "before_token_index", "at_ms", "label", "reason"),
            )
            for item in safe_list(frame.get("phrase_boundaries"))
            if isinstance(item, dict)
        ],
        "listening_hotspots": [
            compact_item(
                item,
                ("id", "kind", "token_start", "token_end", "start_ms", "end_ms", "label", "hint"),
            )
            for item in safe_list(frame.get("listening_hotspots"))
            if isinstance(item, dict)
        ],
    }


def words_for_sentence(timeline: dict[str, Any] | None, sentence_id: str) -> list[dict[str, Any]]:
    if not isinstance(timeline, dict):
        return []
    words = []
    for value in safe_list(timeline.get("words")):
        if not isinstance(value, dict) or value.get("sentence_id") != sentence_id:
            continue
        start_ms = as_int(value.get("start_ms"))
        end_ms = as_int(value.get("end_ms"))
        token_index = as_int(value.get("token_index"))
        if start_ms is None or end_ms is None or end_ms <= start_ms or token_index is None:
            continue
        words.append({**value, "start_ms": start_ms, "end_ms": end_ms, "token_index": token_index})
    words.sort(key=lambda word: (word["start_ms"], word["end_ms"], word["token_index"]))
    return words


def counter_dict(values: list[str]) -> dict[str, int]:
    return dict(sorted(Counter(values).items()))


def word_timeline_summary(timeline: dict[str, Any] | None, words: list[dict[str, Any]]) -> dict[str, Any]:
    if not isinstance(timeline, dict):
        return {"status": "missing_word_timeline"}
    return {
        "status": "present",
        "timeline_id": timeline.get("id"),
        "algorithm_id": timeline.get("algorithm_id"),
        "algorithm_version": timeline.get("algorithm_version"),
        "status_value": timeline.get("status"),
        "word_count": len(words),
        "provider_mix": counter_dict([str(word.get("provider_id", "unknown")) for word in words]),
        "timing_source_mix": counter_dict([str(word.get("timing_source", "unknown")) for word in words]),
    }


def pcm_bytes_to_floats(raw: bytes, sample_width: int, channels: int) -> list[float]:
    if not raw:
        return []
    if sample_width == 2:
        values = array.array("h")
        values.frombytes(raw)
        if sys.byteorder == "big":
            values.byteswap()
        scale = 32768.0
        mono = [float(value) / scale for value in values]
    elif sample_width == 1:
        mono = [(byte - 128) / 128.0 for byte in raw]
    elif sample_width == 4:
        values = array.array("i")
        values.frombytes(raw)
        if sys.byteorder == "big":
            values.byteswap()
        scale = 2147483648.0
        mono = [float(value) / scale for value in values]
    else:
        raise ValueError(f"unsupported PCM sample width: {sample_width}")

    if channels <= 1:
        return mono
    frames = []
    for index in range(0, len(mono), channels):
        chunk = mono[index:index + channels]
        if chunk:
            frames.append(sum(chunk) / len(chunk))
    return frames


def load_wav_window(path: Path, start_ms: int, end_ms: int) -> AudioWindow:
    with wave.open(str(path), "rb") as wav:
        sample_rate = wav.getframerate()
        channels = wav.getnchannels()
        sample_width = wav.getsampwidth()
        start_frame = max(0, int(start_ms * sample_rate / 1000))
        end_frame = max(start_frame + 1, int(end_ms * sample_rate / 1000))
        start_frame = min(start_frame, wav.getnframes())
        end_frame = min(end_frame, wav.getnframes())
        wav.setpos(start_frame)
        raw = wav.readframes(max(0, end_frame - start_frame))
    samples = pcm_bytes_to_floats(raw, sample_width, channels)
    actual_start_ms = int(round(start_frame * 1000 / sample_rate)) if sample_rate else start_ms
    actual_end_ms = actual_start_ms + int(round(len(samples) * 1000 / sample_rate)) if sample_rate else end_ms
    return AudioWindow(samples, sample_rate, actual_start_ms, actual_end_ms, "wave")


def load_ffmpeg_window(path: Path, start_ms: int, end_ms: int) -> AudioWindow:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("ffmpeg is required for non-wav audio")
    duration_ms = max(1, end_ms - start_ms)
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-ss",
        f"{start_ms / 1000:.3f}",
        "-t",
        f"{duration_ms / 1000:.3f}",
        "-i",
        str(path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(TARGET_SAMPLE_RATE),
        "-f",
        "s16le",
        "-",
    ]
    raw = subprocess.check_output(command)
    samples = pcm_bytes_to_floats(raw, 2, 1)
    actual_end_ms = start_ms + int(round(len(samples) * 1000 / TARGET_SAMPLE_RATE))
    return AudioWindow(samples, TARGET_SAMPLE_RATE, start_ms, actual_end_ms, "ffmpeg")


def load_audio_window(path: Path, start_ms: int, end_ms: int) -> AudioWindow:
    if path.suffix.lower() == ".wav":
        return load_wav_window(path, start_ms, end_ms)
    return load_ffmpeg_window(path, start_ms, end_ms)


def rms_dbfs(audio: AudioWindow, start_ms: int, end_ms: int) -> tuple[float | None, float | None]:
    start_index = max(0, int((start_ms - audio.start_ms) * audio.sample_rate_hz / 1000))
    end_index = min(len(audio.samples), int((end_ms - audio.start_ms) * audio.sample_rate_hz / 1000))
    if end_index <= start_index:
        return None, None
    samples = audio.samples[start_index:end_index]
    if not samples:
        return None, None
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
    dbfs = 20 * math.log10(max(rms, 1e-9))
    return rms, dbfs


def duration_word_features(words: list[dict[str, Any]]) -> list[dict[str, Any]]:
    base: list[dict[str, Any]] = []
    duration_per_unit_values = []
    for word in words:
        duration_ms = int(word["end_ms"]) - int(word["start_ms"])
        units = expected_units(word.get("text"))
        duration_per_unit = duration_ms / units
        duration_per_unit_values.append(duration_per_unit)
        base.append(
            {
                "token_index": int(word["token_index"]),
                "text": str(word.get("text") or ""),
                "start_ms": int(word["start_ms"]),
                "end_ms": int(word["end_ms"]),
                "duration_ms": duration_ms,
                "expected_units": units,
                "duration_per_unit_ms": duration_per_unit,
                "provider_id": word.get("provider_id"),
                "timing_source": word.get("timing_source"),
            }
        )

    for index, feature in enumerate(base):
        left = max(0, index - 2)
        right = min(len(base), index + 3)
        local_values = [
            duration_per_unit_values[i]
            for i in range(left, right)
            if i != index and duration_per_unit_values[i] > 0
        ]
        local_median = median(local_values) or median(duration_per_unit_values) or feature["duration_per_unit_ms"]
        ratio = feature["duration_per_unit_ms"] / local_median if local_median else None
        rate = feature["expected_units"] / max(0.001, feature["duration_ms"] / 1000)
        gap_after = None
        if index + 1 < len(base):
            gap_after = int(base[index + 1]["start_ms"]) - int(feature["end_ms"])
        feature["local_median_duration_per_unit_ms"] = round_float(local_median)
        feature["duration_ratio_to_local_median"] = round_float(ratio)
        feature["rate_units_per_second"] = round_float(rate)
        feature["gap_after_ms"] = gap_after
    return base


def energy_word_features(
    duration_features: list[dict[str, Any]],
    audio: AudioWindow | None,
) -> list[dict[str, Any]]:
    features = []
    sentence_db_values: list[float] = []
    for word in duration_features:
        rms = dbfs = None
        if audio is not None:
            rms, dbfs = rms_dbfs(audio, int(word["start_ms"]), int(word["end_ms"]))
            if dbfs is not None:
                sentence_db_values.append(dbfs)
        features.append(
            {
                "token_index": word["token_index"],
                "text": word["text"],
                "start_ms": word["start_ms"],
                "end_ms": word["end_ms"],
                "duration_ms": word["duration_ms"],
                "rms": rms,
                "dbfs": dbfs,
            }
        )
    sentence_median_db = median(sentence_db_values)
    for feature in features:
        dbfs = feature["dbfs"]
        delta = dbfs - sentence_median_db if dbfs is not None and sentence_median_db is not None else None
        feature["sentence_median_dbfs"] = round_float(sentence_median_db)
        feature["db_delta_from_sentence_median"] = round_float(delta)
        feature["rms"] = round_float(feature["rms"])
        feature["dbfs"] = round_float(feature["dbfs"])
    return features


def candidate_item(feature: dict[str, Any], evidence: list[str], reason: str) -> dict[str, Any]:
    return {
        "token_index": feature["token_index"],
        "label": feature["text"],
        "start_ms": feature["start_ms"],
        "end_ms": feature["end_ms"],
        "evidence": evidence,
        "reason": reason,
    }


def duration_rate_summary(features: list[dict[str, Any]]) -> dict[str, Any]:
    anchors = []
    compression_words = []
    boundaries = []
    for feature in features:
        ratio = as_float(feature.get("duration_ratio_to_local_median"))
        gap_after = as_int(feature.get("gap_after_ms"))
        if ratio is not None and ratio >= DURATION_ANCHOR_RATIO and int(feature["duration_ms"]) >= 180:
            anchors.append(
                {
                    **candidate_item(
                        feature,
                        ["forced_alignment_timing", "duration_supported"],
                        "Word duration is high relative to nearby words.",
                    ),
                    "duration_ratio_to_local_median": round_float(ratio),
                }
            )
        if ratio is not None and ratio <= COMPRESSION_RATIO:
            compression_words.append(
                {
                    **candidate_item(
                        feature,
                        ["forced_alignment_timing", "rate_supported"],
                        "Word is short relative to nearby words.",
                    ),
                    "duration_ratio_to_local_median": round_float(ratio),
                }
            )
        if gap_after is not None and gap_after >= BOUNDARY_GAP_MS:
            boundaries.append(
                {
                    "after_token_index": feature["token_index"],
                    "at_ms": feature["end_ms"],
                    "gap_after_ms": gap_after,
                    "evidence": ["forced_alignment_timing", "pause"],
                    "reason": "WordTimeline shows a following gap.",
                }
            )
        elif (
            ratio is not None
            and ratio >= BOUNDARY_LENGTHENING_RATIO
            and gap_after is not None
            and gap_after >= 40
        ):
            boundaries.append(
                {
                    "after_token_index": feature["token_index"],
                    "at_ms": feature["end_ms"],
                    "gap_after_ms": gap_after,
                    "duration_ratio_to_local_median": round_float(ratio),
                    "evidence": ["forced_alignment_timing", "duration_supported"],
                    "reason": "Boundary-final lengthening candidate without a long pause.",
                }
            )
    return {
        "evidence_class": "heuristic_proxy",
        "evidence": ["forced_alignment_timing", "duration_supported", "rate_supported"],
        "word_features": [
            {
                **feature,
                "duration_per_unit_ms": round_float(as_float(feature.get("duration_per_unit_ms"))),
            }
            for feature in features
        ],
        "duration_anchor_candidates": anchors,
        "compression_candidates": compression_words,
        "phrase_boundary_candidates": boundaries,
    }


def energy_summary(features: list[dict[str, Any]], audio: AudioWindow | None) -> dict[str, Any]:
    candidates = []
    for feature in features:
        delta = as_float(feature.get("db_delta_from_sentence_median"))
        if delta is not None and delta >= PROMINENCE_DELTA_DB:
            candidates.append(
                {
                    **candidate_item(
                        feature,
                        ["energy_supported"],
                        "RMS energy is high relative to this sentence.",
                    ),
                    "db_delta_from_sentence_median": round_float(delta),
                    "dbfs": feature.get("dbfs"),
                }
            )
    top_energy = sorted(
        [feature for feature in features if as_float(feature.get("dbfs")) is not None],
        key=lambda feature: as_float(feature.get("dbfs")) or -999.0,
        reverse=True,
    )[:5]
    return {
        "evidence_class": "heuristic_proxy",
        "evidence": ["energy_supported"],
        "audio_source": audio.source if audio is not None else None,
        "word_features": features,
        "prominence_candidates": candidates,
        "top_energy_words": [
            {
                "token_index": feature["token_index"],
                "label": feature["text"],
                "start_ms": feature["start_ms"],
                "end_ms": feature["end_ms"],
                "dbfs": feature.get("dbfs"),
                "db_delta_from_sentence_median": feature.get("db_delta_from_sentence_median"),
            }
            for feature in top_energy
        ],
    }


def timeline_path(case: dict[str, Any], repo_root: Path) -> Path | None:
    llt = case.get("lltimeline") if isinstance(case.get("lltimeline"), dict) else {}
    path = expand_path(llt.get("local_path") or llt.get("path"), repo_root)
    return path if path and path.is_file() else None


def media_path(case: dict[str, Any], document: dict[str, Any], repo_root: Path) -> Path | None:
    media = case.get("media") if isinstance(case.get("media"), dict) else {}
    metadata_media = document.get("metadata", {}).get("media", {})
    raw = media.get("local_path") or metadata_media.get("path")
    path = expand_path(raw, repo_root)
    return path if path and path.is_file() else None


def selected_sentence_ids(
    document: dict[str, Any],
    explicit_ids: set[str],
) -> list[str]:
    segments = ordered_segments(document)
    if explicit_ids:
        return [str(segment["id"]) for segment in segments if segment.get("id") in explicit_ids]

    phone_ids = set(phone_timelines_by_sentence(document))
    if phone_ids:
        return [str(segment["id"]) for segment in segments if segment.get("id") in phone_ids]
    return [str(segment["id"]) for segment in segments if isinstance(segment.get("id"), str)]


def audio_window_for_case(
    path: Path | None,
    segments: list[dict[str, Any]],
    padding_ms: int,
) -> tuple[AudioWindow | None, str | None]:
    if path is None:
        return None, "missing_audio"
    starts = [as_int(segment.get("start_ms")) for segment in segments]
    ends = [as_int(segment.get("end_ms")) for segment in segments]
    starts_clean = [value for value in starts if value is not None]
    ends_clean = [value for value in ends if value is not None]
    if not starts_clean or not ends_clean:
        return None, "missing_segment_timing"
    start_ms = max(0, min(starts_clean) - padding_ms)
    end_ms = max(start_ms + 1, max(ends_clean) + padding_ms)
    try:
        return load_audio_window(path, start_ms, end_ms), None
    except Exception as error:  # noqa: BLE001 - diagnostics must preserve the selected rows.
        return None, str(error)


def sentence_row(
    case: dict[str, Any],
    segment: dict[str, Any],
    word_timeline: dict[str, Any] | None,
    phone_timeline: dict[str, Any] | None,
    audio: AudioWindow | None,
    audio_error: str | None,
) -> dict[str, Any]:
    case_id = str(case.get("case_id") or "")
    sentence_id = str(segment.get("id") or "")
    words = words_for_sentence(word_timeline, sentence_id)
    row: dict[str, Any] = {
        "case_id": case_id,
        "sentence_id": sentence_id,
        "transcript": segment.get("text", ""),
        "media_start_ms": segment.get("start_ms"),
        "media_end_ms": segment.get("end_ms"),
        "current_rhythm_frame": compact_rhythm_frame(phone_timeline),
        "word_timeline": word_timeline_summary(word_timeline, words),
        "manual_labels": {
            "stress_anchors": [],
            "weak_groups": [],
            "compression_spans": [],
            "phrase_boundaries": [],
            "listening_hotspots": [],
            "overall": {
                "manual_score": None,
                "misleading_reason": "",
                "phone_detail_needed": None,
                "notes": "",
            },
        },
    }
    if not words:
        row["status"] = "missing_word_timing"
        row["duration_rate"] = {"status": "missing_word_timing"}
        row["rms_energy"] = {"status": "missing_word_timing", "audio_error": audio_error}
        return row
    duration_features = duration_word_features(words)
    energy_features = energy_word_features(duration_features, audio)
    row["status"] = "scored" if audio is not None else "scored_without_energy"
    row["duration_rate"] = duration_rate_summary(duration_features)
    row["rms_energy"] = energy_summary(energy_features, audio) if audio is not None else {
        "status": "missing_audio",
        "audio_error": audio_error,
        "evidence_class": "heuristic_proxy",
        "evidence": ["energy_supported"],
    }
    return row


def evaluate_case(
    case: dict[str, Any],
    repo_root: Path,
    sentence_ids: set[str],
    remaining_limit: int | None,
    padding_ms: int,
) -> dict[str, Any]:
    path = timeline_path(case, repo_root)
    case_id = str(case.get("case_id") or "")
    if path is None:
        return {
            "case_id": case_id,
            "title": case.get("title"),
            "dataset": case.get("dataset"),
            "status": "missing_timeline",
            "sentences": [],
        }
    document = read_json(path)
    segments = segments_by_id(document)
    word_timeline = active_word_timeline(document)
    phone_timelines = phone_timelines_by_sentence(document)
    selected_ids = selected_sentence_ids(document, sentence_ids)
    if remaining_limit is not None:
        selected_ids = selected_ids[:remaining_limit]
    selected_segments = [segments[sentence_id] for sentence_id in selected_ids if sentence_id in segments]
    media = media_path(case, document, repo_root)
    audio, audio_error = audio_window_for_case(media, selected_segments, padding_ms)
    rows = [
        sentence_row(
            case,
            segment,
            word_timeline,
            phone_timelines.get(str(segment.get("id"))),
            audio,
            audio_error,
        )
        for segment in selected_segments
    ]
    return {
        "case_id": case_id,
        "title": case.get("title"),
        "dataset": case.get("dataset"),
        "layer": case.get("layer"),
        "status": "scored" if rows else "no_selected_sentences",
        "timeline_path": str(path),
        "media_path": str(media) if media is not None else None,
        "audio": {
            "status": "loaded" if audio is not None else "missing",
            "source": audio.source if audio is not None else None,
            "start_ms": audio.start_ms if audio is not None else None,
            "end_ms": audio.end_ms if audio is not None else None,
            "sample_rate_hz": audio.sample_rate_hz if audio is not None else None,
            "error": audio_error,
        },
        "sentences": rows,
    }


def summarize(results: list[dict[str, Any]]) -> dict[str, Any]:
    rows = [
        row
        for result in results
        for row in safe_list(result.get("sentences"))
        if isinstance(row, dict)
    ]
    return {
        "case_count": len(results),
        "selected_sentence_count": len(rows),
        "scored_sentence_count": sum(1 for row in rows if row.get("status") == "scored"),
        "scored_without_energy_count": sum(1 for row in rows if row.get("status") == "scored_without_energy"),
        "missing_word_timing_count": sum(1 for row in rows if row.get("status") == "missing_word_timing"),
        "current_rhythm_frame_count": sum(
            1
            for row in rows
            if (row.get("current_rhythm_frame") or {}).get("status") == "present"
        ),
        "energy_candidate_count": sum(
            len(((row.get("rms_energy") or {}).get("prominence_candidates") or []))
            for row in rows
        ),
        "duration_anchor_candidate_count": sum(
            len(((row.get("duration_rate") or {}).get("duration_anchor_candidates") or []))
            for row in rows
        ),
        "compression_candidate_count": sum(
            len(((row.get("duration_rate") or {}).get("compression_candidates") or []))
            for row in rows
        ),
        "phrase_boundary_candidate_count": sum(
            len(((row.get("duration_rate") or {}).get("phrase_boundary_candidates") or []))
            for row in rows
        ),
    }


def manual_template_row(row: dict[str, Any]) -> dict[str, Any]:
    labels = row.get("manual_labels") if isinstance(row.get("manual_labels"), dict) else {}
    return {
        "case_id": row.get("case_id"),
        "sentence_id": row.get("sentence_id"),
        "transcript": row.get("transcript"),
        "media_start_ms": row.get("media_start_ms"),
        "media_end_ms": row.get("media_end_ms"),
        "system_compare": {
            "status": row.get("status"),
            "current_rhythm_frame": row.get("current_rhythm_frame"),
            "duration_rate": row.get("duration_rate"),
            "rms_energy": row.get("rms_energy"),
        },
        "stress_anchors": labels.get("stress_anchors", []),
        "weak_groups": labels.get("weak_groups", []),
        "compression_spans": labels.get("compression_spans", []),
        "phrase_boundaries": labels.get("phrase_boundaries", []),
        "listening_hotspots": labels.get("listening_hotspots", []),
        "overall": labels.get("overall", {}),
        "reviewer": "",
        "reviewed_at": "",
    }


def build_report(args: argparse.Namespace, repo_root: Path) -> dict[str, Any]:
    manifest_path = expand_path(args.manifest, repo_root)
    if manifest_path is None or not manifest_path.is_file():
        raise ValueError(f"manifest not found: {args.manifest}")
    manifest = load_jsonl(manifest_path)
    selected_cases = set(args.case_id or [])
    sentence_ids = set(args.sentence_id or [])
    cases = [case for case in manifest if not selected_cases or case.get("case_id") in selected_cases]
    results = []
    remaining = args.limit
    for case in cases:
        if remaining is not None and remaining <= 0:
            break
        result = evaluate_case(case, repo_root, sentence_ids, remaining, args.audio_padding_ms)
        results.append(result)
        if remaining is not None:
            remaining -= len(result.get("sentences") or [])
    return {
        "experiment": {
            "id": EXPERIMENT_ID,
            "evidence_class": "heuristic_proxy",
            "closeout_use": "manual_product_qa_input",
            "purpose": "Compare current RhythmFrame with WordTimeline duration/rate and RMS energy before product promotion.",
            "thresholds": {
                "prominence_delta_db": PROMINENCE_DELTA_DB,
                "duration_anchor_ratio": DURATION_ANCHOR_RATIO,
                "compression_ratio": COMPRESSION_RATIO,
                "boundary_gap_ms": BOUNDARY_GAP_MS,
                "boundary_lengthening_ratio": BOUNDARY_LENGTHENING_RATIO,
            },
        },
        "manifest": str(manifest_path),
        "case_filter": sorted(selected_cases),
        "sentence_filter": sorted(sentence_ids),
        "summary": summarize(results),
        "results": results,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default="testdata/sound-line-real-media/manifest.jsonl")
    parser.add_argument("--case-id", action="append")
    parser.add_argument("--sentence-id", action="append")
    parser.add_argument("--limit", type=int, default=10, help="Maximum selected sentences across all cases.")
    parser.add_argument("--audio-padding-ms", type=int, default=250)
    parser.add_argument(
        "--emit-template",
        action="store_true",
        help="Emit JSONL manual annotation rows with system_compare instead of the full report.",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    report = build_report(args, repo_root)
    if args.emit_template:
        for result in report.get("results") or []:
            for row in result.get("sentences") or []:
                print(json.dumps(manual_template_row(row), ensure_ascii=False, sort_keys=True))
    else:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
