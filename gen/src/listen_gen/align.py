"""Forced alignment providers and the aligned word timeline resource.

The word timeline is the single seam the rich chain depends on. ASR supplies
the exact sentence text and its time windows; a forced aligner turns that
text-plus-window into per-word timings anchored to the audio. The aligner is
provider-neutral (fixture / command / torchaudio MMS_FA) and the word
timeline it produces always declares ``timing_source: forced_aligned``.
"""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Protocol

from .command_identity import command_identity_sha256, compose_config_sha256
from .package import ConversionError
from .package_v3 import (
    WORD_TIMELINE_SCHEMA_V1,
    PackageResource,
    blob_declaration,
    canonical_json,
    provenance,
    quality,
    sha256_of_bytes,
)
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv

ALIGN_RESULT_SCHEMA = "listen_gen.alignment-result.v1"
ALIGN_TIMEOUT_DEFAULT = 600.0
ALIGN_STDOUT_LIMIT_BYTES = 16 * 1024 * 1024

WORD_TIMELINE_TIMING_SOURCE = "forced_aligned"
WORD_TIMELINE_RESOURCE_KIND = "word_timeline"


@dataclass(frozen=True)
class AlignSegment:
    """One sentence window the aligner anchors into the audio.

    ``words`` is the exact word-token text sequence sent to the provider;
    ``word_indexes`` maps each word to its reading token index (the provider
    indexes into the sent list, while the reading coordinates are global).
    """

    index: int
    words: tuple[str, ...]
    word_indexes: tuple[int, ...]
    start_ms: int
    end_ms: int


@dataclass(frozen=True)
class AlignmentRequest:
    audio_path: Path
    segments: tuple[AlignSegment, ...]


@dataclass(frozen=True)
class AlignedWord:
    segment_index: int
    word_index: int
    text: str
    start_ms: int
    end_ms: int
    score: float | None = None
    skipped: bool = False


@dataclass(frozen=True)
class AlignmentResult:
    words: tuple[AlignedWord, ...]
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


class AlignAdapter(Protocol):
    """Provider-neutral seam for acoustic forced alignment."""

    def align(self, request: AlignmentRequest) -> AlignmentResult: ...


def _failure(code: str) -> ConversionError:
    return ConversionError(f"aligner_{code}")


def _parse_result(raw: Any) -> AlignmentResult:
    try:
        if not isinstance(raw, dict) or raw.get("schema") != ALIGN_RESULT_SCHEMA:
            raise ValueError
        provider = raw.get("provider")
        if not isinstance(provider, dict):
            raise ValueError
        provider_id, provider_version = provider.get("id"), provider.get("version")
        if not all(
            isinstance(item, str) and item.strip() for item in (provider_id, provider_version)
        ):
            raise ValueError
        model_id = model_version = None
        model = raw.get("model")
        if model is not None:
            if not isinstance(model, dict):
                raise ValueError
            model_id, model_version = model.get("id"), model.get("version")
            if not all(
                isinstance(item, str) and item.strip()
                for item in (model_id, model_version)
            ):
                raise ValueError
        config_sha256 = raw.get("config_sha256")
        if config_sha256 is not None and not isinstance(config_sha256, str):
            raise ValueError
        entries = raw.get("words")
        if not isinstance(entries, list):
            raise ValueError
        words: list[AlignedWord] = []
        previous: dict[tuple[int, int], None] = {}
        for entry in entries:
            if not isinstance(entry, dict):
                raise ValueError
            segment_index = entry.get("segment_index")
            word_index = entry.get("word_index")
            skipped = entry.get("skipped") is True
            if (
                not isinstance(segment_index, int)
                or isinstance(segment_index, bool)
                or not isinstance(word_index, int)
                or isinstance(word_index, bool)
            ):
                raise ValueError
            key = (segment_index, word_index)
            if key in previous:
                raise ValueError
            previous[key] = None
            text = entry.get("text")
            if not skipped and (
                not isinstance(text, str) or not text.strip()
            ):
                raise ValueError
            if not skipped:
                start_ms = entry.get("start_ms")
                end_ms = entry.get("end_ms")
                if (
                    not isinstance(start_ms, int)
                    or isinstance(start_ms, bool)
                    or not isinstance(end_ms, int)
                    or isinstance(end_ms, bool)
                    or end_ms <= start_ms
                ):
                    raise ValueError
            else:
                start_ms = end_ms = 0
                if not isinstance(text, str):
                    text = ""
            score = entry.get("score")
            if score is not None and (
                not isinstance(score, (int, float))
                or isinstance(score, bool)
                or not math.isfinite(score)
            ):
                raise ValueError
            words.append(
                AlignedWord(
                    segment_index, word_index, text, start_ms, end_ms, score, skipped
                )
            )
        return AlignmentResult(
            tuple(words), provider_id, provider_version, model_id, model_version,
            config_sha256,
        )
    except (TypeError, ValueError) as error:
        raise _failure("output_invalid") from error


class FixtureAlignAdapter:
    def __init__(self, path: Path):
        if not path.is_file():
            raise ValueError("aligner fixture must be a regular file")
        self.path = path

    def align(self, request: AlignmentRequest) -> AlignmentResult:
        try:
            return _parse_result(json.loads(self.path.read_text(encoding="utf-8")))
        except ConversionError:
            raise
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("output_invalid") from error


def _run(argv: list[str], input_bytes: bytes, timeout_seconds: float) -> bytes:
    try:
        completed = run_argv(
            argv,
            timeout_seconds=timeout_seconds,
            stdout_limit_bytes=ALIGN_STDOUT_LIMIT_BYTES,
            input_bytes=input_bytes,
        )
    except ProcessTimedOut as error:
        raise _failure("timeout") from error
    except ProcessOutputTooLarge as error:
        raise _failure("output_too_large") from error
    except OSError as error:
        raise _failure("start_failed") from error
    if completed.returncode != 0:
        raise _failure("failed")
    return completed.stdout


class CommandAlignAdapter:
    def __init__(self, executable: str, arguments: list[str], timeout_seconds: float):
        if not executable.strip():
            raise ValueError("aligner command executable must be non-empty")
        if sum(argument == "{media}" for argument in arguments) != 1:
            raise ValueError(
                "aligner command arguments must contain exactly one {media} placeholder"
            )
        if timeout_seconds <= 0:
            raise ValueError("aligner command timeout must be positive")
        self.executable = executable
        self.arguments = tuple(arguments)
        self.timeout_seconds = timeout_seconds

    def align(self, request: AlignmentRequest) -> AlignmentResult:
        request_json = json.dumps(
            {
                "audio_path": str(request.audio_path),
                "segments": [
                    {
                        "index": segment.index,
                        "words": list(segment.words),
                        "start_ms": segment.start_ms,
                        "end_ms": segment.end_ms,
                    }
                    for segment in request.segments
                ],
            },
            ensure_ascii=False,
        ).encode("utf-8")
        argv = [
            self.executable,
            *(str(request.audio_path) if item == "{media}" else item for item in self.arguments),
        ]
        try:
            before = command_identity_sha256(
                self.executable,
                self.arguments,
                frozenset({"{media}"}),
                self.timeout_seconds,
            )
        except OSError as error:
            raise _failure("start_failed") from error
        raw = _run(argv, request_json, self.timeout_seconds)
        try:
            after = command_identity_sha256(
                self.executable,
                self.arguments,
                frozenset({"{media}"}),
                self.timeout_seconds,
            )
        except OSError as error:
            raise _failure("failed") from error
        if after != before:
            raise _failure("failed")
        try:
            result = _parse_result(json.loads(raw))
            return replace(
                result,
                config_sha256=compose_config_sha256(
                    result.config_sha256, before
                ),
            )
        except ConversionError:
            raise
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("output_invalid") from error


class TorchaudioAlignAdapter:
    """First-class wrapper for the torchaudio MMS_FA forced alignment sidecar."""

    def __init__(
        self,
        python: Path,
        sidecar: Path,
        timeout_seconds: float,
    ):
        if not python.is_file() or not sidecar.is_file():
            raise ValueError("torchaudio aligner runtime inputs must exist")
        if timeout_seconds <= 0:
            raise ValueError("torchaudio aligner timeout must be positive")
        self.python, self.sidecar = python, sidecar
        self.timeout_seconds = timeout_seconds

    def _identity(self) -> tuple[str, str]:
        return (
            _file_sha256(self.python),
            _file_sha256(self.sidecar),
        )

    def align(self, request: AlignmentRequest) -> AlignmentResult:
        before = self._identity()
        request_json = json.dumps(
            {
                "audio_path": str(request.audio_path),
                "segments": [
                    {
                        "index": segment.index,
                        "words": list(segment.words),
                        "start_ms": segment.start_ms,
                        "end_ms": segment.end_ms,
                    }
                    for segment in request.segments
                ],
            },
            ensure_ascii=False,
        ).encode("utf-8")
        raw = _run(
            [str(self.python), str(self.sidecar)],
            request_json,
            self.timeout_seconds,
        )
        after = self._identity()
        if after != before:
            raise _failure("failed")
        try:
            core = json.loads(raw)
            if not isinstance(core, dict) or not isinstance(core.get("timings"), list):
                raise _failure("output_invalid")
            torchaudio_version = ""
            provenance_info = core.get("provenance")
            if isinstance(provenance_info, dict) and isinstance(
                provenance_info.get("torchaudio_version"), str
            ):
                torchaudio_version = provenance_info["torchaudio_version"]
            config = {
                "schema": "listen_gen.torchaudio-align-config.v1",
                "python_sha256": before[0],
                "sidecar_sha256": before[1],
                "torchaudio_version": torchaudio_version,
            }
            normalized = {
                "schema": ALIGN_RESULT_SCHEMA,
                "provider": {"id": "torchaudio-mms-fa", "version": "ctc-align-v1"},
                "model": {"id": "facebook/mms-300m-ctc-align", "version": "torchaudio-mms-fa"},
                "config_sha256": "sha256:"
                + hashlib.sha256(
                    json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
                ).hexdigest(),
                "words": core["timings"],
            }
            return _parse_result(normalized)
        except ConversionError:
            raise
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("output_invalid") from error


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def build_word_timeline_from_alignment(
    *,
    result: AlignmentResult,
    segments: tuple[AlignSegment, ...],
    sentence_ids: tuple[str, ...],
    subtitle_resource_id: str,
    context,
) -> tuple[PackageResource, bytes]:
    """Anchor aligned words into the reading sentence tokens.

    Every aligner segment corresponds to exactly one reading sentence in
    order (by ``index``), and every word index maps through the segment's
    ``word_indexes`` back to the reading token coordinate. Skipped words and
    out-of-range references are dropped; a result with no anchored words is
    a qualification failure, never a fabricated timing.
    """
    indexes_by_segment: dict[int, tuple[int, ...]] = {
        segment.index: segment.word_indexes for segment in segments
    }
    words_by_segment: dict[int, tuple[str, ...]] = {
        segment.index: segment.words for segment in segments
    }
    words: list[dict[str, Any]] = []
    for aligned in result.words:
        if aligned.skipped:
            continue
        if aligned.segment_index < 0 or aligned.segment_index >= len(sentence_ids):
            raise _failure("qualification_failed")
        word_indexes = indexes_by_segment.get(aligned.segment_index)
        segment_words = words_by_segment.get(aligned.segment_index)
        if (
            word_indexes is None
            or segment_words is None
            or aligned.word_index >= len(word_indexes)
            or aligned.text != segment_words[aligned.word_index]
        ):
            raise _failure("qualification_failed")
        entry: dict[str, Any] = {
            "sentence_id": sentence_ids[aligned.segment_index],
            "token_index": word_indexes[aligned.word_index],
            "start_ms": aligned.start_ms,
            "end_ms": aligned.end_ms,
            "timing_source": WORD_TIMELINE_TIMING_SOURCE,
        }
        words.append(entry)
    if not words:
        raise _failure("qualification_failed")
    payload: dict[str, Any] = {
        "words": words,
    }
    payload_bytes = canonical_json(payload)
    resource = PackageResource(
        kind=WORD_TIMELINE_RESOURCE_KIND,
        schema=WORD_TIMELINE_SCHEMA_V1,
        role="base",
        content_language=context.language,
        payload_blob=blob_declaration(
            sha256_of_bytes(payload_bytes), len(payload_bytes), True
        ),
        subject=context.subject,
        dependencies=(subtitle_resource_id, context.anchor_resource_id),
        provenance=provenance(
            context.created_at_ms,
            input_rendition_ids=[context.rendition_id],
            input_resource_ids=[context.anchor_resource_id],
            provider={"id": result.provider_id, "version": result.provider_version},
            model=(
                {"id": result.model_id, "version": result.model_version}
                if result.model_id is not None
                else None
            ),
            config_sha256=result.config_sha256,
        ),
        quality=quality(),
        required=False,
    )
    return resource, payload_bytes
