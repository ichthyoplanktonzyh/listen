from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

PACKAGE_SCHEMA = "listen.resource-package.v1"
SOURCE_SCHEMA = "llplayer.timeline.v1"
RESOURCE_SCHEMAS = {
    "subtitle_text_track": "listen.resource.subtitle-text-track.v1",
    "word_timeline": "listen.resource.word-timeline.v1",
    "phone_timeline": "listen.resource.phone-timeline.v1",
    "sense_group_analysis": "listen.resource.sense-group-analysis.v1",
    "word_acoustics": "listen.resource.word-acoustics.v1",
}
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
SHA256_RE = re.compile(r"^(?:sha256:)?([0-9a-fA-F]{64})$")


class ConversionError(ValueError):
    """The legacy document cannot be represented by the v1 package."""


@dataclass(frozen=True)
class ResourceFile:
    kind: str
    path: str
    body: bytes
    required: bool

    @property
    def resource_id(self) -> str:
        return f"sha256:{hashlib.sha256(self.body).hexdigest()}"


def _canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_ref(value: Any, location: str) -> str:
    if not isinstance(value, str):
        raise ConversionError(f"{location} must be a SHA-256 string")
    match = SHA256_RE.fullmatch(value)
    if not match:
        raise ConversionError(f"{location} must contain exactly 64 hexadecimal SHA-256 digits")
    return f"sha256:{match.group(1).lower()}"


def _segment_id(source_sha256: str, index: int) -> str:
    digest = _sha256(f"{source_sha256}:segment:{index}".encode("utf-8"))
    return f"sentence.{digest[:24]}"


def _require_object(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConversionError(f"{location} must be an object")
    return value


def _select_active(
    document: dict[str, Any], collection: str, active_field: str
) -> dict[str, Any] | None:
    active_id = document.get(active_field)
    if active_id is None:
        return None
    candidates = document.get(collection) or []
    if not isinstance(candidates, list):
        raise ConversionError(f"/{collection} must be an array")
    matches = [item for item in candidates if isinstance(item, dict) and item.get("id") == active_id]
    if len(matches) != 1:
        raise ConversionError(
            f"/{active_field} must reference exactly one /{collection} entry"
        )
    return matches[0]


def _producer(value: dict[str, Any]) -> dict[str, str] | None:
    producer_id = value.get("provider_id") or value.get("algorithm_id") or value.get("id")
    version = value.get("provider_version") or value.get("algorithm_version") or value.get("version")
    if not producer_id or not version:
        return None
    return {"id": str(producer_id), "version": str(version)}


def _provenance(
    source: dict[str, Any], created_at_ms: int, warnings: list[str], location: str
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "created_at_ms": created_at_ms,
        "tool": {"id": "listen-gen.lltimeline-compat", "version": "0.1.0"},
    }
    if provider := _producer(source):
        result["provider"] = provider
    model_id = source.get("model_id")
    model_revision = source.get("model_revision")
    if model_id and model_revision:
        result["model"] = {"id": str(model_id), "version": str(model_revision)}
    config = source.get("config_hash")
    if config is not None:
        try:
            result["config_sha256"] = _sha256_ref(config, f"{location}/config_hash")
        except ConversionError:
            warnings.append(f"ignored non-SHA-256 config hash at {location}/config_hash")
    return result


def _quality(human_reviewed: bool, warnings: list[str] | None = None) -> dict[str, Any]:
    result: dict[str, Any] = {
        "review_status": "human_reviewed" if human_reviewed else "unreviewed"
    }
    if warnings:
        result["warnings"] = warnings
    return result


def _envelope(
    *,
    kind: str,
    media_fingerprint: str,
    dependencies: list[ResourceFile],
    provenance: dict[str, Any],
    quality: dict[str, Any],
    payload: dict[str, Any],
    required: bool,
) -> ResourceFile:
    document = {
        "schema": RESOURCE_SCHEMAS[kind],
        "kind": kind,
        "subject": {"media_fingerprint": media_fingerprint},
        "dependencies": [
            {"resource_id": resource.resource_id, "kind": resource.kind}
            for resource in dependencies
        ],
        "provenance": provenance,
        "quality": quality,
        "payload": payload,
    }
    return ResourceFile(
        kind=kind,
        path=f"resources/{kind.replace('_', '-')}.json",
        body=_canonical_json(document),
        required=required,
    )


def _convert_sentences(
    segments: Any, source_sha256: str
) -> tuple[list[dict[str, Any]], dict[str, str]]:
    if not isinstance(segments, list) or not segments:
        raise ConversionError("/segments must be a non-empty array")
    sentences: list[dict[str, Any]] = []
    id_map: dict[str, str] = {}
    for position, raw in enumerate(segments):
        segment = _require_object(raw, f"/segments/{position}")
        old_id = segment.get("id")
        index = segment.get("index")
        if not isinstance(old_id, str) or not isinstance(index, int):
            raise ConversionError(f"/segments/{position} has invalid id or index")
        if index != position:
            raise ConversionError(f"/segments/{position}/index must be contiguous from zero")
        if old_id in id_map:
            raise ConversionError(f"/segments/{position}/id is duplicated")
        new_id = _segment_id(source_sha256, index)
        id_map[old_id] = new_id
        sentences.append(
            {
                "id": new_id,
                "index": index,
                "start_ms": segment.get("start_ms"),
                "end_ms": segment.get("end_ms"),
                "original_text": segment.get("text"),
                "display_text": segment.get("display_text"),
                "tokens": segment.get("tokens") or [],
            }
        )
    return sentences, id_map


def _map_sentence_id(value: Any, id_map: dict[str, str], location: str) -> str:
    if not isinstance(value, str) or value not in id_map:
        raise ConversionError(f"{location} references an unknown sentence")
    return id_map[value]


def _convert_words(timeline: dict[str, Any], id_map: dict[str, str]) -> list[dict[str, Any]]:
    words = []
    for index, raw in enumerate(timeline.get("words") or []):
        word = _require_object(raw, f"/word_timelines/active/words/{index}")
        converted = {
            "sentence_id": _map_sentence_id(
                word.get("sentence_id"), id_map, f"/word_timelines/active/words/{index}/sentence_id"
            ),
            "token_index": word.get("token_index"),
            "start_ms": word.get("start_ms"),
            "end_ms": word.get("end_ms"),
            "timing_source": word.get("timing_source"),
        }
        if word.get("confidence") is not None:
            converted["confidence"] = word["confidence"]
        words.append(converted)
    if not words:
        raise ConversionError("active word timeline has no words")
    return words


def _convert_phones(
    timeline: dict[str, Any], id_map: dict[str, str]
) -> list[dict[str, Any]]:
    legacy_sentence_id = timeline.get("sentence_id")
    sentence_id = (
        _map_sentence_id(legacy_sentence_id, id_map, "/phone_timelines/active/sentence_id")
        if legacy_sentence_id is not None
        else None
    )
    phones = []
    for index, raw in enumerate(timeline.get("phones") or []):
        phone = _require_object(raw, f"/phone_timelines/active/phones/{index}")
        token_index = phone.get("token_index")
        converted = {
            "symbol": phone.get("symbol"),
            "start_ms": phone.get("start_ms"),
            "end_ms": phone.get("end_ms"),
            "word_ref": (
                {"sentence_id": sentence_id, "token_index": token_index}
                if sentence_id is not None and isinstance(token_index, int)
                else None
            ),
        }
        if phone.get("display_ipa"):
            converted["display_ipa"] = phone["display_ipa"]
        if phone.get("confidence") is not None:
            converted["confidence"] = phone["confidence"]
        phones.append(converted)
    if not phones:
        raise ConversionError("active phone timeline has no phones")
    return phones


def _convert_groups(analysis: dict[str, Any], id_map: dict[str, str]) -> list[dict[str, Any]]:
    groups = []
    for index, raw in enumerate(analysis.get("groups") or []):
        group = _require_object(raw, f"/sense_group_analyses/active/groups/{index}")
        end_inclusive = group.get("end_token_index")
        if not isinstance(end_inclusive, int):
            raise ConversionError(
                f"/sense_group_analyses/active/groups/{index}/end_token_index must be an integer"
            )
        groups.append(
            {
                "sentence_id": _map_sentence_id(
                    group.get("sentence_id"),
                    id_map,
                    f"/sense_group_analyses/active/groups/{index}/sentence_id",
                ),
                "group_index": group.get("group_index"),
                "start_token_index": group.get("start_token_index"),
                "end_token_index_exclusive": end_inclusive + 1,
                "label": group.get("label"),
                "head_token_index": group.get("head_token_index"),
                "confidence": group.get("confidence"),
                "sources": group.get("sources") or [],
            }
        )
    if not groups:
        raise ConversionError("active sense-group analysis has no groups")
    return groups


def _nullable_number(cue: dict[str, Any], *names: str) -> int | float | None:
    for name in names:
        value = cue.get(name)
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return value
    return None


def _convert_acoustic_measurements(
    payload: dict[str, Any], id_map: dict[str, str]
) -> list[dict[str, Any]]:
    measurements = []
    for index, raw in enumerate(payload.get("cues") or []):
        cue = _require_object(raw, f"/artifacts/word_acoustics/payload/cues/{index}")
        start_ms = cue.get("start_ms")
        end_ms = cue.get("end_ms")
        if not isinstance(start_ms, int) or not isinstance(end_ms, int) or end_ms <= start_ms:
            raise ConversionError(
                f"/artifacts/word_acoustics/payload/cues/{index} has an invalid time range"
            )
        measurements.append(
            {
                "word_ref": {
                    "sentence_id": _map_sentence_id(
                        cue.get("sentence_id"),
                        id_map,
                        f"/artifacts/word_acoustics/payload/cues/{index}/sentence_id",
                    ),
                    "token_index": cue.get("token_index"),
                },
                "energy": {
                    "rms_dbfs": _nullable_number(cue, "dbfs", "rms_dbfs"),
                    "local_baseline_dbfs": _nullable_number(
                        cue, "sentence_median_dbfs", "local_baseline_dbfs"
                    ),
                    "delta_db": _nullable_number(
                        cue, "db_delta_from_sentence_median", "delta_db"
                    ),
                    "prominence": _nullable_number(cue, "energy_prominence"),
                },
                "pitch": {
                    "median_f0_hz": _nullable_number(cue, "median_f0_hz"),
                    "local_baseline_f0_hz": _nullable_number(
                        cue, "sentence_median_f0_hz", "local_baseline_f0_hz"
                    ),
                    "delta_semitones": _nullable_number(cue, "delta_semitones"),
                    "range_semitones": _nullable_number(cue, "range_semitones"),
                    "prominence": _nullable_number(cue, "pitch_prominence"),
                    "reset_after": _nullable_number(cue, "pitch_reset_after"),
                },
                "duration": {
                    "duration_ms": end_ms - start_ms,
                    "local_ratio": _nullable_number(cue, "duration_local_ratio", "local_ratio"),
                },
                "voiced_frame_ratio": _nullable_number(cue, "voiced_frame_ratio"),
            }
        )
    if not measurements:
        raise ConversionError("scored word-acoustics artifact has no measurements")
    return measurements


def _media_kind(media: dict[str, Any], warnings: list[str]) -> str:
    path = media.get("path")
    if isinstance(path, str):
        suffix = Path(path).suffix.lower()
        if suffix in {".mp3", ".wav", ".flac", ".m4a", ".aac", ".ogg", ".opus"}:
            return "audio"
        if suffix in {".mp4", ".mkv", ".mov", ".webm", ".avi"}:
            return "video"
    warnings.append("media kind was unavailable in LLTimeline; defaulted to video")
    return "video"


def convert_lltimeline(raw: bytes) -> tuple[dict[str, Any], list[ResourceFile], list[str]]:
    source_sha256 = _sha256(raw)
    document = _require_object(json.loads(raw), "/")
    if document.get("schema") != SOURCE_SCHEMA:
        raise ConversionError(f"/schema must equal {SOURCE_SCHEMA!r}")
    metadata = _require_object(document.get("metadata"), "/metadata")
    media = _require_object(metadata.get("media"), "/metadata/media")
    media_fingerprint = _sha256_ref(media.get("fingerprint"), "/metadata/media/fingerprint")
    created_at_ms = metadata.get("created_at_ms")
    if not isinstance(created_at_ms, int) or created_at_ms < 0:
        raise ConversionError("/metadata/created_at_ms must be a non-negative integer")
    language = metadata.get("language")
    if not isinstance(language, str) or not language:
        raise ConversionError("/metadata/language is required by the v1 subtitle resource")
    duration_ms = media.get("duration_ms")
    if not isinstance(duration_ms, int) or duration_ms < 1:
        raise ConversionError("/metadata/media/duration_ms must be a positive integer")
    title = media.get("title")
    if not isinstance(title, str) or not title:
        raise ConversionError("/metadata/media/title must be non-empty")

    warnings: list[str] = []
    if media.get("path"):
        warnings.append("ignored local media path from LLTimeline metadata")
    active_fields = (
        "active_word_timeline_id",
        "active_phone_timeline_id",
        "active_chunk_timeline_id",
        "active_sense_group_analysis_id",
    )
    if any(document.get(field) is not None for field in active_fields):
        warnings.append(
            "used legacy active selections to choose resources; omitted Core lifecycle state"
        )
    human_reviewed = metadata.get("human_reviewed") is True
    sentences, id_map = _convert_sentences(document.get("segments"), source_sha256)
    subtitle = _envelope(
        kind="subtitle_text_track",
        media_fingerprint=media_fingerprint,
        dependencies=[],
        provenance=_provenance(
            _require_object(metadata.get("generator") or {}, "/metadata/generator"),
            created_at_ms,
            warnings,
            "/metadata/generator",
        ),
        quality=_quality(human_reviewed),
        payload={"language": language, "source_kind": "asr", "sentences": sentences},
        required=True,
    )
    resources = [subtitle]

    active_word = _select_active(document, "word_timelines", "active_word_timeline_id")
    active_word_legacy_id = active_word.get("id") if active_word else None
    word: ResourceFile | None = None
    if active_word:
        word = _envelope(
            kind="word_timeline",
            media_fingerprint=media_fingerprint,
            dependencies=[subtitle],
            provenance=_provenance(
                active_word, created_at_ms, warnings, "/word_timelines/active"
            ),
            quality=_quality(human_reviewed),
            payload={"words": _convert_words(active_word, id_map)},
            required=False,
        )
        resources.append(word)

    active_phone = _select_active(document, "phone_timelines", "active_phone_timeline_id")
    if active_phone:
        if word is None:
            raise ConversionError("active phone timeline requires an active word timeline")
        parent_word_id = active_phone.get("parent_word_timeline_id")
        if parent_word_id is not None and parent_word_id != active_word_legacy_id:
            raise ConversionError("active phone timeline does not depend on active word timeline")
        phone = _envelope(
            kind="phone_timeline",
            media_fingerprint=media_fingerprint,
            dependencies=[word],
            provenance=_provenance(
                active_phone, created_at_ms, warnings, "/phone_timelines/active"
            ),
            quality=_quality(human_reviewed),
            payload={
                "phone_set": active_phone.get("phone_set"),
                "precision": active_phone.get("precision"),
                "phones": _convert_phones(active_phone, id_map),
            },
            required=False,
        )
        resources.append(phone)

    active_sense = _select_active(
        document, "sense_group_analyses", "active_sense_group_analysis_id"
    )
    if active_sense:
        sense = _envelope(
            kind="sense_group_analysis",
            media_fingerprint=media_fingerprint,
            dependencies=[subtitle],
            provenance=_provenance(
                active_sense, created_at_ms, warnings, "/sense_group_analyses/active"
            ),
            quality=_quality(human_reviewed),
            payload={"groups": _convert_groups(active_sense, id_map)},
            required=False,
        )
        resources.append(sense)

    if document.get("chunk_timelines"):
        warnings.append("ignored legacy chunk timelines; v1 has no chunk-timeline resource kind")

    acoustics_seen = False
    artifacts = document.get("artifacts") or []
    if not isinstance(artifacts, list):
        raise ConversionError("/artifacts must be an array")
    for index, raw_artifact in enumerate(artifacts):
        artifact = _require_object(raw_artifact, f"/artifacts/{index}")
        kind = artifact.get("kind")
        if kind != "rhythm_word_acoustic_cues":
            warnings.append(f"ignored unknown LLTimeline artifact kind: {kind!r}")
            continue
        payload = _require_object(artifact.get("payload"), f"/artifacts/{index}/payload")
        if payload.get("status") != "scored":
            warnings.append("ignored word-acoustics artifact without scored measurements")
            continue
        if word is None or payload.get("timeline_id") != active_word_legacy_id:
            warnings.append("ignored word-acoustics artifact not bound to active word timeline")
            continue
        if acoustics_seen:
            warnings.append("ignored duplicate word-acoustics artifact")
            continue
        acoustic_warnings = [
            "legacy rhythm_word_acoustic_cues may not contain pitch, duration ratio, or voiced-frame observations"
        ]
        acoustics = _envelope(
            kind="word_acoustics",
            media_fingerprint=media_fingerprint,
            dependencies=[word],
            provenance=_provenance(
                artifact, created_at_ms, warnings, f"/artifacts/{index}"
            ),
            quality=_quality(human_reviewed, acoustic_warnings),
            payload={
                "sample_rate_hz": payload.get("sample_rate_hz"),
                "energy_baseline": "sentence_median_dbfs",
                "pitch_baseline": "sentence_median_f0_hz",
                "measurements": _convert_acoustic_measurements(payload, id_map),
            },
            required=False,
        )
        resources.append(acoustics)
        acoustics_seen = True

    manifest = {
        "schema": PACKAGE_SCHEMA,
        "created_at_ms": created_at_ms,
        "content_document": {
            "media_fingerprint": media_fingerprint,
            "title": title,
            "media_kind": _media_kind(media, warnings),
            "duration_ms": duration_ms,
        },
        "resources": [
            {
                "resource_id": resource.resource_id,
                "path": resource.path,
                "kind": resource.kind,
                "schema": RESOURCE_SCHEMAS[resource.kind],
                "required": resource.required,
                "size_bytes": len(resource.body),
            }
            for resource in resources
        ],
    }
    return manifest, resources, warnings


def _zip_info(path: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(path, date_time=ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    return info


def write_package(
    output_path: Path, manifest: dict[str, Any], resources: list[ResourceFile]
) -> str:
    """Write a v1 package using the contract's deterministic ZIP profile."""
    manifest_bytes = _canonical_json(manifest)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output_path.parent,
        prefix=f".{output_path.name}.",
        suffix=".tmp",
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        with zipfile.ZipFile(
            temporary_path,
            "w",
            compression=zipfile.ZIP_STORED,
            allowZip64=True,
        ) as archive:
            archive.writestr(_zip_info("manifest.json"), manifest_bytes)
            for resource in sorted(resources, key=lambda item: item.path.encode("utf-8")):
                archive.writestr(_zip_info(resource.path), resource.body)
        digest = hashlib.sha256()
        with temporary_path.open("rb") as package:
            for chunk in iter(lambda: package.read(1024 * 1024), b""):
                digest.update(chunk)
            os.fsync(package.fileno())
        os.replace(temporary_path, output_path)
        directory_descriptor = os.open(output_path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
        return digest.hexdigest()
    finally:
        temporary_path.unlink(missing_ok=True)


def package_from_lltimeline(input_path: Path, output_path: Path) -> dict[str, Any]:
    raw = input_path.read_bytes()
    manifest, resources, warnings = convert_lltimeline(raw)
    package_sha256 = write_package(output_path, manifest, resources)
    return {
        "status": "created",
        "output": str(output_path),
        "source_sha256": _sha256(raw),
        "package_sha256": package_sha256,
        "resource_count": len(resources),
        "warnings": warnings,
    }
