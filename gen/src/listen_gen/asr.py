from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Protocol

from .media import AudioPreprocessor
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv

from .package import (
    PACKAGE_SCHEMA,
    RESOURCE_SCHEMAS,
    ConversionError,
    ResourceFile,
    _envelope,
    write_package,
)

TOOL_VERSION = "0.1.0"
LANGUAGE_RE = re.compile(r"^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$")
TOKEN_RE = re.compile(r"\w+(?:['\u2019]\w+)*|\s+|[^\w\s]", re.UNICODE)
TIMING_SOURCES = {
    "asr_reported",
    "asr_aligned",
    "forced_aligned",
    "estimated",
    "user_adjusted",
}
ASR_STDOUT_LIMIT_BYTES = 16 * 1024 * 1024


@dataclass(frozen=True)
class AsrWord:
    start_char: int
    end_char: int
    start_ms: int
    end_ms: int
    confidence: float | None
    timing_source: str


@dataclass(frozen=True)
class AsrSegment:
    start_ms: int
    end_ms: int
    text: str
    display_text: str
    words: tuple[AsrWord, ...]


@dataclass(frozen=True)
class AsrTranscript:
    language: str
    segments: tuple[AsrSegment, ...]
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


class AsrAdapter(Protocol):
    """Provider-neutral seam for expensive media transcription."""

    def transcribe(self, media_path: Path) -> AsrTranscript: ...


class FixtureAsrAdapter:
    """Offline adapter for contract tests; it never contacts a service."""

    def __init__(self, fixture_path: Path):
        self.fixture_path = fixture_path

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        return _parse_transcript(raw)


class CommandAsrAdapter:
    """Run a provider wrapper as an argv-only subprocess.

    The wrapper receives the media path at the exact ``{media}`` placeholder
    and must write one normalized ``listen_gen.asr-result.v1`` JSON document
    to stdout. Shell parsing is deliberately never involved.
    """

    def __init__(self, executable: str, arguments: list[str], timeout_seconds: float):
        if not executable:
            raise ConversionError("ASR command executable must be non-empty")
        if arguments.count("{media}") != 1:
            raise ConversionError("ASR command arguments must contain exactly one {media} placeholder")
        if timeout_seconds <= 0:
            raise ConversionError("ASR command timeout must be positive")
        self.executable = executable
        self.arguments = tuple(arguments)
        self.timeout_seconds = timeout_seconds

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        argv = [
            self.executable,
            *(str(media_path) if argument == "{media}" else argument for argument in self.arguments),
        ]
        try:
            completed = run_argv(
                argv,
                timeout_seconds=self.timeout_seconds,
                stdout_limit_bytes=ASR_STDOUT_LIMIT_BYTES,
            )
        except ProcessTimedOut as error:
            raise ConversionError("ASR command timed out without producing a usable result") from error
        except ProcessOutputTooLarge as error:
            raise ConversionError("ASR command output exceeded the safety limit") from error
        except OSError as error:
            raise ConversionError("ASR command could not be started") from error
        if completed.returncode != 0:
            raise ConversionError(f"ASR command failed with exit status {completed.returncode}")
        try:
            raw = json.loads(completed.stdout)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ConversionError("ASR command returned invalid normalized JSON") from error
        return _parse_transcript(raw)


class PreprocessingAsrAdapter:
    """Supply normalized temporary audio to an underlying ASR adapter."""

    def __init__(
        self,
        adapter: AsrAdapter,
        preprocessor: AudioPreprocessor,
        *,
        audio_stream_index: int | None,
    ):
        self.adapter = adapter
        self.preprocessor = preprocessor
        self.audio_stream_index = audio_stream_index

    def transcribe(self, media_path: Path) -> AsrTranscript:
        with self.preprocessor.prepare(
            media_path, audio_stream_index=self.audio_stream_index
        ) as prepared:
            transcript = self.adapter.transcribe(prepared.path)
        pipeline_config = {
            "adapter_protocol": "listen_gen.asr-result.v1",
            "audio_preprocessing": {
                "audio_stream_index": prepared.stream_index,
                "channels": 1,
                "container": "wav",
                "sample_format": "pcm_s16le",
                "sample_rate_hz": 16000,
            },
            "provider_config_sha256": transcript.config_sha256,
            "schema": "listen_gen.asr-pipeline-config.v1",
        }
        config_bytes = json.dumps(
            pipeline_config, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        return replace(
            transcript,
            config_sha256=f"sha256:{hashlib.sha256(config_bytes).hexdigest()}",
        )


def _object(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ConversionError(f"{location} must be an object")
    return value


def _integer(value: Any, location: str, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise ConversionError(f"{location} must be an integer >= {minimum}")
    return value


def _parse_transcript(raw: Any) -> AsrTranscript:
    value = _object(raw, "/")
    if value.get("schema") != "listen_gen.asr-result.v1":
        raise ConversionError("/schema must equal 'listen_gen.asr-result.v1'")
    language = value.get("language")
    if not isinstance(language, str) or not LANGUAGE_RE.fullmatch(language):
        raise ConversionError("/language must be a valid language tag")
    provider = _object(value.get("provider"), "/provider")
    provider_id = provider.get("id")
    provider_version = provider.get("version")
    if not all(isinstance(item, str) and item.strip() for item in (provider_id, provider_version)):
        raise ConversionError("/provider id and version must be non-empty strings")
    model = value.get("model")
    model_id = model_version = None
    if model is not None:
        model = _object(model, "/model")
        model_id, model_version = model.get("id"), model.get("version")
        if not all(isinstance(item, str) and item.strip() for item in (model_id, model_version)):
            raise ConversionError("/model id and version must be non-empty strings")
    config_sha256 = value.get("config_sha256")
    if config_sha256 is not None and not re.fullmatch(r"sha256:[0-9a-f]{64}", config_sha256):
        raise ConversionError("/config_sha256 must be a lowercase SHA-256 identity")
    raw_segments = value.get("segments")
    if not isinstance(raw_segments, list) or not raw_segments:
        raise ConversionError("/segments must be a non-empty array")
    segments: list[AsrSegment] = []
    previous_end = 0
    for segment_index, raw_segment in enumerate(raw_segments):
        location = f"/segments/{segment_index}"
        segment = _object(raw_segment, location)
        start_ms = _integer(segment.get("start_ms"), f"{location}/start_ms")
        end_ms = _integer(segment.get("end_ms"), f"{location}/end_ms", 1)
        text = segment.get("text")
        display_text = segment.get("display_text", text)
        if end_ms <= start_ms or start_ms < previous_end:
            raise ConversionError(f"{location} must be a positive, monotonic time range")
        if not isinstance(text, str) or not text or not isinstance(display_text, str):
            raise ConversionError(f"{location} text fields must be strings and text must be non-empty")
        raw_words = segment.get("words")
        if not isinstance(raw_words, list) or not raw_words:
            raise ConversionError(f"{location}/words must be a non-empty array")
        words: list[AsrWord] = []
        previous_word_end = start_ms
        previous_char_end = 0
        for word_index, raw_word in enumerate(raw_words):
            word_location = f"{location}/words/{word_index}"
            word = _object(raw_word, word_location)
            start_char = _integer(word.get("start_char"), f"{word_location}/start_char")
            end_char = _integer(word.get("end_char"), f"{word_location}/end_char", 1)
            word_start = _integer(word.get("start_ms"), f"{word_location}/start_ms")
            word_end = _integer(word.get("end_ms"), f"{word_location}/end_ms", 1)
            confidence = word.get("confidence")
            timing_source = word.get("timing_source", "asr_reported")
            if (
                end_char <= start_char
                or end_char > len(text)
                or start_char < previous_char_end
                or word_start < start_ms
                or word_end > end_ms
                or word_end <= word_start
                or word_start < previous_word_end
            ):
                raise ConversionError(f"{word_location} has an invalid or non-monotonic span")
            if confidence is not None and (
                not isinstance(confidence, (int, float))
                or isinstance(confidence, bool)
                or not 0 <= confidence <= 1
            ):
                raise ConversionError(f"{word_location}/confidence must be between zero and one")
            if timing_source not in TIMING_SOURCES:
                raise ConversionError(f"{word_location}/timing_source is unsupported")
            words.append(AsrWord(start_char, end_char, word_start, word_end, confidence, timing_source))
            previous_char_end = end_char
            previous_word_end = word_end
        segments.append(AsrSegment(start_ms, end_ms, text, display_text, tuple(words)))
        previous_end = end_ms
    return AsrTranscript(
        language, tuple(segments), provider_id, provider_version,
        model_id, model_version, config_sha256,
    )


def _tokens(text: str) -> list[dict[str, Any]]:
    tokens = []
    for index, match in enumerate(TOKEN_RE.finditer(text)):
        value = match.group(0)
        if value.isspace():
            kind, normalized = "whitespace", None
        elif any(character.isalnum() or character == "_" for character in value):
            kind, normalized = "word", unicodedata.normalize("NFKC", value).casefold()
        elif all(unicodedata.category(character).startswith("P") for character in value):
            kind, normalized = "punctuation", None
        else:
            kind, normalized = "other", None
        tokens.append({
            "index": index, "kind": kind, "text": value, "normalized": normalized,
            "start_char": match.start(), "end_char": match.end(),
        })
    if not tokens or "".join(token["text"] for token in tokens) != text:
        raise ConversionError("ASR segment could not be losslessly tokenized")
    return tokens


def _fingerprint(media_path: Path) -> str:
    digest = hashlib.sha256()
    with media_path.open("rb") as media:
        for chunk in iter(lambda: media.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def _sentence_id(media_fingerprint: str, segment_index: int, segment: AsrSegment) -> str:
    identity = f"{media_fingerprint}:{segment_index}:{segment.start_ms}:{segment.end_ms}:{segment.text}"
    return f"sentence.{hashlib.sha256(identity.encode('utf-8')).hexdigest()[:24]}"


def _provenance(transcript: AsrTranscript, created_at_ms: int) -> dict[str, Any]:
    value: dict[str, Any] = {
        "created_at_ms": created_at_ms,
        "tool": {"id": "listen-gen.asr-package", "version": TOOL_VERSION},
        "provider": {"id": transcript.provider_id, "version": transcript.provider_version},
    }
    if transcript.model_id is not None:
        value["model"] = {"id": transcript.model_id, "version": transcript.model_version}
    if transcript.config_sha256 is not None:
        value["config_sha256"] = transcript.config_sha256
    return value


def package_media(
    media_path: Path,
    output_path: Path,
    adapter: AsrAdapter,
    *,
    title: str,
    media_kind: str,
    duration_ms: int,
    created_at_ms: int,
) -> dict[str, Any]:
    if not media_path.is_file():
        raise ConversionError("media input is not a regular file")
    if not title.strip():
        raise ConversionError("title must be non-empty")
    if media_kind not in {"audio", "video"}:
        raise ConversionError("media kind must be audio or video")
    _integer(duration_ms, "duration_ms", 1)
    _integer(created_at_ms, "created_at_ms")
    media_fingerprint = _fingerprint(media_path)
    transcript = adapter.transcribe(media_path)
    if _fingerprint(media_path) != media_fingerprint:
        raise ConversionError("media input changed during processing")
    sentences = []
    timings = []
    for index, segment in enumerate(transcript.segments):
        if segment.end_ms > duration_ms:
            raise ConversionError(f"ASR segment {index} exceeds media duration")
        tokens = _tokens(segment.text)
        token_by_span = {
            (token["start_char"], token["end_char"]): token for token in tokens if token["kind"] == "word"
        }
        sentence_id = _sentence_id(media_fingerprint, index, segment)
        sentences.append({
            "id": sentence_id, "index": index, "start_ms": segment.start_ms,
            "end_ms": segment.end_ms, "original_text": segment.text,
            "display_text": segment.display_text, "tokens": tokens,
        })
        for word_index, word in enumerate(segment.words):
            token = token_by_span.get((word.start_char, word.end_char))
            if token is None:
                raise ConversionError(
                    f"ASR segment {index} word {word_index} does not exactly match a word token"
                )
            timing = {
                "sentence_id": sentence_id, "token_index": token["index"],
                "start_ms": word.start_ms, "end_ms": word.end_ms,
                "timing_source": word.timing_source,
            }
            if word.confidence is not None:
                timing["confidence"] = word.confidence
            timings.append(timing)
    provenance = _provenance(transcript, created_at_ms)
    quality = {"review_status": "machine_checked"}
    subtitle = _envelope(
        kind="subtitle_text_track", media_fingerprint=media_fingerprint,
        dependencies=[], provenance=provenance, quality=quality,
        payload={"language": transcript.language, "source_kind": "asr", "sentences": sentences},
        required=True,
    )
    word_timeline = _envelope(
        kind="word_timeline", media_fingerprint=media_fingerprint,
        dependencies=[subtitle], provenance=provenance, quality=quality,
        payload={"words": timings}, required=False,
    )
    resources: list[ResourceFile] = [subtitle, word_timeline]
    manifest = {
        "schema": PACKAGE_SCHEMA,
        "created_at_ms": created_at_ms,
        "content_document": {
            "media_fingerprint": media_fingerprint, "title": title,
            "media_kind": media_kind, "duration_ms": duration_ms,
        },
        "resources": [{
            "resource_id": resource.resource_id, "path": resource.path,
            "kind": resource.kind, "schema": RESOURCE_SCHEMAS[resource.kind],
            "required": resource.required, "size_bytes": len(resource.body),
        } for resource in resources],
    }
    package_sha256 = write_package(output_path, manifest, resources)
    return {
        "status": "created", "output": str(output_path),
        "media_fingerprint": media_fingerprint, "package_sha256": package_sha256,
        "resource_count": len(resources), "warnings": [],
    }
