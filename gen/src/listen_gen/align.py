"""Forced alignment providers and the aligned word timeline resource.

The word timeline is the single seam the rich chain depends on. ASR (or a
subtitle track) supplies the exact sentence text and its rough time windows; a
forced aligner turns that text-plus-window into per-word timings anchored to
the audio. The aligner is provider-neutral (fixture / command /
Qwen3-ForcedAligner) and the word timeline it produces always declares
``timing_source: forced_aligned``.

The forced aligner only decides *timing*: the reading tokens stay
authoritative, so every anchored word carries the original reading text and
its reading-token coordinate, never the provider's own tokenization.
"""

from __future__ import annotations

import hashlib
import json
import math
import unicodedata
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Callable, Protocol

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
    language: str | None = None


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


QWEN_ALIGNER_PROVIDER_ID = "qwen3-forced-aligner"
QWEN_ALIGNER_PROVIDER_VERSION = "v1"
QWEN_DEFAULT_MODEL_ID = "Qwen/Qwen3-ForcedAligner-0.6B"
QWEN_DEFAULT_MODEL_REVISION = "main"
QWEN_SAMPLE_RATE = 16000
# The sentence windows Core/subtitles carry are approximate; media captions in
# particular drift by tens to hundreds of milliseconds.  A little context on
# each side keeps the aligner from clipping the first or last word.
QWEN_ALIGNER_PADDING_MS = 400
# Adjacent sentences are merged into one continuous alignment window so the
# model never sees a hard sentence cut; kept well under the model's 5-minute
# input ceiling.
QWEN_ALIGNER_CHUNK_TARGET_MS = 30_000
QWEN_ALIGNER_CHUNK_MAX_MS = 45_000
QWEN_ALIGNER_MODEL_CEILING_MS = 5 * 60 * 1000

# BCP-47 primary subtag -> Qwen language name (the 11 languages the model
# supports).  Anything else falls back to English rather than abstaining.
_QWEN_LANGUAGES = {
    "en": "English",
    "zh": "Chinese",
    "cmn": "Chinese",
    "yue": "Cantonese",
    "fr": "French",
    "de": "German",
    "it": "Italian",
    "ja": "Japanese",
    "ko": "Korean",
    "pt": "Portuguese",
    "ru": "Russian",
    "es": "Spanish",
}
_QWEN_DEFAULT_LANGUAGE = "English"


def _map_qwen_language(language: str | None) -> str:
    """Resolve a reading language code to a Qwen language name."""
    if not language:
        return _QWEN_DEFAULT_LANGUAGE
    primary = language.strip().lower().split("-")[0]
    if primary in ("", "auto", "und"):
        return _QWEN_DEFAULT_LANGUAGE
    return _QWEN_LANGUAGES.get(primary, _QWEN_DEFAULT_LANGUAGE)


def _normalize_token(text: str) -> str:
    """Fold a token to alphanumerics for provider-vs-reading text matching.

    Qwen decides timing, not text: its tokenization may differ from the
    reading's (``don't`` split into ``do`` + ``n't``, straight vs curly
    apostrophes, surrounding quotes/punctuation).  Reducing to case-folded
    alphanumerics collapses all of those differences, so a reading token and
    the provider unit(s) that spell it fold to the same key regardless of how
    each side punctuates it.
    """
    return "".join(
        ch for ch in unicodedata.normalize("NFC", text).casefold() if ch.isalnum()
    )


def _select_device(preference: str, torch: Any) -> str:
    """Pick a runtime device; explicit requests win, ``auto`` prefers CUDA."""
    choice = (preference or "auto").strip().lower()
    if choice in ("cpu", "cuda", "mps"):
        return choice
    if torch.cuda.is_available():
        return "cuda"
    mps = getattr(torch.backends, "mps", None)
    if mps is not None and mps.is_available():
        return "mps"
    return "cpu"


@dataclass(frozen=True)
class _AlignChunk:
    segments: tuple[AlignSegment, ...]
    start_ms: int
    end_ms: int


def _chunk_segments(
    segments: tuple[AlignSegment, ...],
    total_ms: int,
    *,
    target_ms: int,
    max_ms: int,
) -> list[_AlignChunk]:
    """Group consecutive sentences into padded alignment windows.

    Sentences carry rough windows; merging adjacent ones into ~30s chunks gives
    the aligner continuous audio and text (fewer boundary artifacts, fewer
    model calls).  When the sentence timing is unusable (all zero / non
    monotonic) the whole reading becomes one chunk over the full audio.
    """
    ordered = sorted(segments, key=lambda seg: seg.index)
    if not ordered:
        return []
    usable = (
        total_ms > 0
        and all(seg.end_ms >= seg.start_ms >= 0 for seg in ordered)
        and any(seg.end_ms > seg.start_ms for seg in ordered)
    )
    if not usable:
        return [_AlignChunk(tuple(ordered), 0, total_ms)]
    chunks: list[_AlignChunk] = []
    current: list[AlignSegment] = []
    chunk_start = chunk_end = 0
    for seg in ordered:
        seg_start = max(seg.start_ms, 0)
        seg_end = min(max(seg.end_ms, seg_start), total_ms)
        if not current:
            current, chunk_start, chunk_end = [seg], seg_start, seg_end
            continue
        prospective_end = max(chunk_end, seg_end)
        if prospective_end - chunk_start > max_ms:
            chunks.append(_AlignChunk(tuple(current), chunk_start, chunk_end))
            current, chunk_start, chunk_end = [seg], seg_start, seg_end
            continue
        current.append(seg)
        chunk_end = prospective_end
        if chunk_end - chunk_start >= target_ms:
            chunks.append(_AlignChunk(tuple(current), chunk_start, chunk_end))
            current = []
    if current:
        chunks.append(_AlignChunk(tuple(current), chunk_start, chunk_end))
    return chunks


def _seconds(value: Any) -> float:
    try:
        seconds = float(value)
    except (TypeError, ValueError):
        return 0.0
    if not math.isfinite(seconds) or seconds < 0:
        return 0.0
    return seconds


def _result_items(result: Any) -> list[Any]:
    items = getattr(result, "items", None)
    if items is not None:
        return list(items)
    try:
        return list(result)
    except TypeError:
        return []


def _forced_align_items(results: Any) -> list[Any]:
    """Flatten a Qwen ``align`` return into the ordered items of one window.

    ``align`` returns one ``ForcedAlignResult`` per input; a single window is
    passed, so the first result carries every ``ForcedAlignItem`` (each with
    ``text``/``start_time``/``end_time`` in seconds).  Tolerates an
    implementation that returns the items list directly.
    """
    if not results:
        return []
    sequence = list(results) if isinstance(results, (list, tuple)) else [results]
    if not sequence:
        return []
    head = sequence[0]
    if hasattr(head, "start_time"):
        return sequence
    return _result_items(head)


def _item_span_ms(
    first_item: Any, last_item: Any, offset_ms: int, total_ms: int
) -> tuple[int, int]:
    start_ms = offset_ms + int(round(_seconds(getattr(first_item, "start_time", 0.0)) * 1000))
    end_ms = offset_ms + int(round(_seconds(getattr(last_item, "end_time", 0.0)) * 1000))
    start_ms = max(0, min(start_ms, total_ms))
    end_ms = max(0, min(end_ms, total_ms))
    if end_ms <= start_ms:
        end_ms = min(total_ms, start_ms + 1)
    return start_ms, end_ms


def _anchor_items(
    expected: list[tuple[int, int, str]],
    items: list[Any],
    slice_start_ms: int,
    total_ms: int,
) -> list[AlignedWord]:
    """Map ordered provider items back onto the reading word tokens.

    A two-pointer forward match reunites the reading token with the provider
    unit(s) that reconstruct it (handling clean 1:1 hits and provider
    sub-splits alike).  A token the provider cannot reconstruct is emitted as
    ``skipped`` — its timing is never fabricated.
    """
    aligned: list[AlignedWord] = []
    cursor = 0
    count = len(items)
    for segment_index, word_index, word in expected:
        target = _normalize_token(word)
        span: tuple[int, int] | None = None
        if target and cursor < count:
            accumulated = ""
            probe = cursor
            while probe < count:
                accumulated += _normalize_token(getattr(items[probe], "text", ""))
                probe += 1
                if accumulated == target:
                    span = (cursor, probe - 1)
                    break
                if len(accumulated) >= len(target):
                    break
        if span is None:
            aligned.append(AlignedWord(segment_index, word_index, word, 0, 0, None, True))
            if target and cursor < count:
                cursor += 1  # resync past one unmatchable provider unit
            continue
        first_idx, last_idx = span
        start_ms, end_ms = _item_span_ms(
            items[first_idx], items[last_idx], slice_start_ms, total_ms
        )
        if end_ms <= start_ms:
            aligned.append(AlignedWord(segment_index, word_index, word, 0, 0, None, True))
        else:
            aligned.append(
                AlignedWord(segment_index, word_index, word, start_ms, end_ms, None, False)
            )
        cursor = last_idx + 1
    return aligned


class Qwen3ForcedAlignAdapter:
    """In-process forced aligner backed by Qwen3-ForcedAligner-0.6B.

    The model is imported and loaded lazily and reused across every request in
    an adapter instance's lifetime — one alignment run never reloads it per
    sentence.  Adjacent sentences are merged into padded chunks so the model
    sees continuous audio and text; the returned per-word timestamps (relative
    to each chunk) are offset back to absolute media time and re-mapped onto the
    reading's own tokens.

    Heavy dependencies (``torch``, ``qwen_asr``, ``librosa``) are optional and
    imported only when a real alignment runs; ``model_loader`` / ``audio_loader``
    are injection seams so tests exercise the mapping without them.
    """

    def __init__(
        self,
        *,
        model_id: str = QWEN_DEFAULT_MODEL_ID,
        model_revision: str = QWEN_DEFAULT_MODEL_REVISION,
        device: str = "auto",
        padding_ms: int = QWEN_ALIGNER_PADDING_MS,
        chunk_target_ms: int = QWEN_ALIGNER_CHUNK_TARGET_MS,
        chunk_max_ms: int = QWEN_ALIGNER_CHUNK_MAX_MS,
        sample_rate: int = QWEN_SAMPLE_RATE,
        model_loader: Callable[[], Any] | None = None,
        audio_loader: Callable[[Path, int], tuple[Any, int]] | None = None,
    ):
        if not model_id.strip():
            raise ValueError("qwen aligner model id must be non-empty")
        if padding_ms < 0:
            raise ValueError("qwen aligner padding must be non-negative")
        if chunk_target_ms <= 0 or chunk_max_ms <= 0:
            raise ValueError("qwen aligner chunk bounds must be positive")
        if sample_rate <= 0:
            raise ValueError("qwen aligner sample rate must be positive")
        self.model_id = model_id
        self.model_revision = model_revision
        self.device = device
        self.padding_ms = padding_ms
        self.chunk_target_ms = min(chunk_target_ms, chunk_max_ms)
        self.chunk_max_ms = min(chunk_max_ms, QWEN_ALIGNER_MODEL_CEILING_MS)
        self.sample_rate = sample_rate
        self._model_loader = model_loader
        self._audio_loader = audio_loader
        self._model: Any = None
        self._resolved_device: str | None = None
        self._forced_device: str | None = None
        self._fell_back = False

    def _config_sha256(self, language: str) -> str:
        config = {
            "schema": "listen_gen.qwen3-forced-aligner-config.v1",
            "model_id": self.model_id,
            "model_revision": self.model_revision,
            "device": self.device,
            "padding_ms": self.padding_ms,
            "chunk_target_ms": self.chunk_target_ms,
            "chunk_max_ms": self.chunk_max_ms,
            "sample_rate": self.sample_rate,
            "language": language,
        }
        return "sha256:" + hashlib.sha256(
            json.dumps(config, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()

    def _load_model(self) -> Any:
        if self._model is not None:
            return self._model
        if self._model_loader is not None:
            self._model = self._model_loader()
            self._resolved_device = self._forced_device or "cpu"
            return self._model
        try:
            import torch  # noqa: PLC0415
            from qwen_asr import Qwen3ForcedAligner  # noqa: PLC0415
        except ImportError as error:
            raise _failure("unavailable") from error
        device = self._forced_device or _select_device(self.device, torch)
        self._resolved_device = device
        # MPS lacks bfloat16 for some ops; only CUDA takes the reduced dtype.
        dtype = torch.bfloat16 if device == "cuda" else torch.float32
        device_map = "cuda:0" if device == "cuda" else device
        try:
            self._model = Qwen3ForcedAligner.from_pretrained(
                self.model_id,
                revision=self.model_revision,
                dtype=dtype,
                device_map=device_map,
            )
        except Exception as error:  # pragma: no cover - model init failure
            raise _failure("start_failed") from error
        return self._model

    def _load_audio(self, audio_path: Path) -> tuple[Any, int]:
        if self._audio_loader is not None:
            return self._audio_loader(audio_path, self.sample_rate)
        try:
            import librosa  # noqa: PLC0415
        except ImportError as error:
            raise _failure("unavailable") from error
        try:
            samples, sr = librosa.load(str(audio_path), sr=self.sample_rate, mono=True)
        except Exception as error:  # pragma: no cover - decode failure
            raise _failure("start_failed") from error
        return samples, int(sr)

    def align(self, request: AlignmentRequest) -> AlignmentResult:
        segments = request.segments
        if not segments:
            raise _failure("output_invalid")
        language = _map_qwen_language(request.language)
        samples, sr = self._load_audio(request.audio_path)
        total_samples = len(samples)
        if sr <= 0 or total_samples == 0:
            raise _failure("output_invalid")
        total_ms = int(total_samples * 1000 / sr)
        chunks = _chunk_segments(
            segments, total_ms, target_ms=self.chunk_target_ms, max_ms=self.chunk_max_ms
        )
        try:
            aligned = self._align_chunks(samples, sr, total_ms, chunks, language)
        except ConversionError:
            # Apple Silicon MPS can lack ops this model needs; retry once on CPU
            # rather than abstaining the whole word timeline.
            if self._resolved_device == "mps" and not self._fell_back:
                self._fell_back = True
                self._forced_device = "cpu"
                self._model = None
                aligned = self._align_chunks(samples, sr, total_ms, chunks, language)
            else:
                raise
        if not any(not word.skipped for word in aligned):
            raise _failure("qualification_failed")
        return AlignmentResult(
            words=tuple(aligned),
            provider_id=QWEN_ALIGNER_PROVIDER_ID,
            provider_version=QWEN_ALIGNER_PROVIDER_VERSION,
            model_id=self.model_id,
            model_version=self.model_revision,
            config_sha256=self._config_sha256(language),
        )

    def _align_chunks(
        self,
        samples: Any,
        sr: int,
        total_ms: int,
        chunks: list[_AlignChunk],
        language: str,
    ) -> list[AlignedWord]:
        model = self._load_model()
        aligned: list[AlignedWord] = []
        for chunk in chunks:
            aligned.extend(
                self._align_chunk(model, samples, sr, total_ms, chunk, language)
            )
        return aligned

    def _align_chunk(
        self,
        model: Any,
        samples: Any,
        sr: int,
        total_ms: int,
        chunk: _AlignChunk,
        language: str,
    ) -> list[AlignedWord]:
        expected = [
            (segment.index, local_index, word)
            for segment in chunk.segments
            for local_index, word in enumerate(segment.words)
        ]
        if not expected:
            return []
        slice_start_ms = max(0, chunk.start_ms - self.padding_ms)
        slice_end_ms = min(total_ms, chunk.end_ms + self.padding_ms)
        if slice_end_ms <= slice_start_ms:
            slice_start_ms, slice_end_ms = 0, total_ms
        start_sample = max(0, int(slice_start_ms * sr / 1000))
        end_sample = min(len(samples), int(slice_end_ms * sr / 1000))
        if end_sample <= start_sample:
            return [
                AlignedWord(segment_index, word_index, word, 0, 0, None, True)
                for segment_index, word_index, word in expected
            ]
        window = samples[start_sample:end_sample]
        text = " ".join(word for _, _, word in expected)
        try:
            results = model.align((window, sr), text, language)
        except Exception as error:  # pragma: no cover - inference failure
            raise _failure("failed") from error
        items = _forced_align_items(results)
        return _anchor_items(expected, items, slice_start_ms, total_ms)


def build_word_timeline_from_alignment(
    *,
    result: AlignmentResult,
    segments: tuple[AlignSegment, ...],
    sentence_ids: tuple[str, ...],
    subtitle_resource_id: str,
    context,
    upstream_config_sha256: str | None = None,
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
    timeline_config_sha256 = result.config_sha256
    if upstream_config_sha256 is not None:
        timeline_config_sha256 = "sha256:" + hashlib.sha256(
            json.dumps(
                {
                    "schema": "listen_gen.word-timeline-config.v1",
                    "assembly_or_upstream_config_sha256": upstream_config_sha256,
                    "aligner_config_sha256": result.config_sha256,
                },
                sort_keys=True,
                separators=(",", ":"),
            ).encode("utf-8")
        ).hexdigest()
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
            config_sha256=timeline_config_sha256,
        ),
        quality=quality(),
        required=False,
    )
    return resource, payload_bytes
