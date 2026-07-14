from __future__ import annotations

import array
import json
import math
import sys
import wave
from pathlib import Path
from typing import Any

from production_pipeline_common import active_word_timeline, load_json, now_ms, stable_id

RHYTHM_WORD_ACOUSTIC_CUES_KIND = "rhythm_word_acoustic_cues"
RHYTHM_WORD_ACOUSTIC_PROVIDER_ID = "rms-word-energy-prominence"
RHYTHM_WORD_ACOUSTIC_PROVIDER_VERSION = "v1"
ENERGY_PROMINENCE_DB_FOR_MAX = 6.0


def median(values: list[float]) -> float | None:
    clean = sorted(value for value in values if math.isfinite(value))
    if not clean:
        return None
    middle = len(clean) // 2
    if len(clean) % 2 == 0:
        return (clean[middle - 1] + clean[middle]) / 2
    return clean[middle]


def load_wav_mono(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        sample_width = handle.getsampwidth()
        sample_rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    if channels != 1 or sample_width != 2:
        raise ValueError("expected 16-bit mono PCM wav")
    values = array.array("h")
    values.frombytes(frames)
    if sys.byteorder != "little":
        values.byteswap()
    return [sample / 32768.0 for sample in values], sample_rate


def rms_dbfs_for_window(
    samples: list[float],
    sample_rate_hz: int,
    start_ms: int,
    end_ms: int,
) -> float | None:
    start_index = max(0, int(start_ms * sample_rate_hz / 1000))
    end_index = min(len(samples), int(end_ms * sample_rate_hz / 1000))
    if end_index <= start_index:
        return None
    window = samples[start_index:end_index]
    if not window:
        return None
    rms = math.sqrt(sum(sample * sample for sample in window) / len(window))
    return 20 * math.log10(max(rms, 1e-9))


def rhythm_word_acoustic_cues(document: dict[str, Any], audio_path: Path) -> dict[str, Any]:
    timeline = active_word_timeline(document)
    if not timeline:
        return {
            "status": "missing_active_word_timeline",
            "timeline_id": None,
            "cues": [],
        }
    samples, sample_rate_hz = load_wav_mono(audio_path)
    by_sentence: dict[str, list[dict[str, Any]]] = {}
    for word in timeline.get("words") or []:
        if not isinstance(word, dict) or word.get("timing_source") == "estimated":
            continue
        sentence_id = word.get("sentence_id")
        token_index = word.get("token_index")
        start_ms = word.get("start_ms")
        end_ms = word.get("end_ms")
        if (
            not isinstance(sentence_id, str)
            or not isinstance(token_index, int)
            or not isinstance(start_ms, int)
            or not isinstance(end_ms, int)
            or end_ms <= start_ms
        ):
            continue
        by_sentence.setdefault(sentence_id, []).append(word)

    cues: list[dict[str, Any]] = []
    for sentence_id, words in by_sentence.items():
        measured = []
        for word in words:
            dbfs = rms_dbfs_for_window(samples, sample_rate_hz, int(word["start_ms"]), int(word["end_ms"]))
            if dbfs is not None:
                measured.append((word, dbfs))
        sentence_median = median([dbfs for _, dbfs in measured])
        if sentence_median is None:
            continue
        for word, dbfs in measured:
            delta = dbfs - sentence_median
            prominence = max(0.0, min(1.0, delta / ENERGY_PROMINENCE_DB_FOR_MAX))
            cues.append(
                {
                    "sentence_id": sentence_id,
                    "token_index": int(word["token_index"]),
                    "text": str(word.get("text") or ""),
                    "start_ms": int(word["start_ms"]),
                    "end_ms": int(word["end_ms"]),
                    "energy_prominence": round(prominence, 6),
                    "dbfs": round(dbfs, 6),
                    "sentence_median_dbfs": round(sentence_median, 6),
                    "db_delta_from_sentence_median": round(delta, 6),
                }
            )

    return {
        "status": "scored",
        "timeline_id": timeline.get("id"),
        "audio_path": str(audio_path),
        "sample_rate_hz": sample_rate_hz,
        "calibration": {
            "method": "sentence_median_dbfs_delta_v1",
            "delta_db_for_max": ENERGY_PROMINENCE_DB_FOR_MAX,
        },
        "cue_count": len(cues),
        "positive_cue_count": sum(1 for cue in cues if float(cue["energy_prominence"]) > 0.0),
        "cues": cues,
    }


def append_rhythm_word_acoustic_cues(document_path: Path, audio_path: Path) -> dict[str, Any]:
    document = load_json(document_path)
    payload = rhythm_word_acoustic_cues(document, audio_path)
    timeline_id = payload.get("timeline_id")
    artifacts = [
        artifact
        for artifact in document.get("artifacts") or []
        if not (
            isinstance(artifact, dict)
            and artifact.get("kind") == RHYTHM_WORD_ACOUSTIC_CUES_KIND
            and isinstance(artifact.get("payload"), dict)
            and artifact["payload"].get("timeline_id") == timeline_id
        )
    ]
    artifacts.append(
        {
            "kind": RHYTHM_WORD_ACOUSTIC_CUES_KIND,
            "provider_id": RHYTHM_WORD_ACOUSTIC_PROVIDER_ID,
            "provider_version": RHYTHM_WORD_ACOUSTIC_PROVIDER_VERSION,
            "payload": payload,
        }
    )
    document["artifacts"] = artifacts
    document_path.write_text(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return payload


def append_rhythm_word_acoustic_cues_safe(document_path: Path, audio_path: Path) -> dict[str, Any]:
    try:
        return append_rhythm_word_acoustic_cues(document_path, audio_path)
    except Exception as error:  # noqa: BLE001 - acoustic cue extraction must degrade.
        document = load_json(document_path)
        timeline = active_word_timeline(document)
        timeline_id = timeline.get("id") if isinstance(timeline, dict) else None
        payload = {
            "status": "failed",
            "timeline_id": timeline_id,
            "audio_path": str(audio_path),
            "error": str(error),
            "cues": [],
        }
        artifacts = [
            artifact
            for artifact in document.get("artifacts") or []
            if not (
                isinstance(artifact, dict)
                and artifact.get("kind") == RHYTHM_WORD_ACOUSTIC_CUES_KIND
                and isinstance(artifact.get("payload"), dict)
                and artifact["payload"].get("timeline_id") == timeline_id
            )
        ]
        artifacts.append(
            {
                "kind": RHYTHM_WORD_ACOUSTIC_CUES_KIND,
                "provider_id": RHYTHM_WORD_ACOUSTIC_PROVIDER_ID,
                "provider_version": RHYTHM_WORD_ACOUSTIC_PROVIDER_VERSION,
                "payload": payload,
            }
        )
        document["artifacts"] = artifacts
        document_path.write_text(
            json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return payload

