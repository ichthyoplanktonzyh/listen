"""Provider-neutral word alignment for native content packages.

The alignment stage is optional and sits behind the same
media -> machine events -> deterministic ``.listenpkg`` interface as the ASR
stage. It aligns the exact Subtitle Text Track tokenization that was emitted
into the package against the media and produces a v1 ``word_timeline``
resource with exactly one dependency on that subtitle resource.

Adapters in this module are provider-neutral over an immutable
:class:`AlignmentRequest` / :class:`AlignmentResult` boundary:

* :class:`FixtureAlignerAdapter` replays a committed
  ``listen_gen.align-result.v1`` document without any model or network;
* :class:`CommandAlignerAdapter` runs an external aligner as a direct argv
  subprocess with a stable normalized command protocol;
* :class:`WhisperCppAlignerAdapter` is the first-class whisper.cpp aligner:
  it runs a local ``whisper-cli`` directly against the normalized WAV and
  derives word timing from whisper.cpp full-JSON per-token offsets.

Degradable alignment failures raise :class:`AlignmentFailure`, a typed
exception carrying the stable machine-protocol warning code. The pipeline
stage (:func:`run_alignment`) converts them into a degraded outcome that
preserves the ASR subtitle package. Cancellation and media-change failures are
never treated as degradation.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import tempfile
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Protocol

from . import __version__ as TOOL_VERSION
from .package import (
    TIMING_SOURCES,
    LANGUAGE_RE,
    ConversionError,
    ResourceFile,
    _envelope,
)
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv
from .protocol import (
    ALIGNMENT_WARNING_MESSAGES,
    AlignmentFailure,
    alignment_warning,
)

ALIGN_RESULT_SCHEMA = "listen_gen.align-result.v1"
SUBTITLE_INPUT_SCHEMA = "listen_gen.subtitle-input.v1"
WHISPER_ALIGN_CONFIG_SCHEMA = "listen_gen.whisper-cpp-align-config.v1"
ALIGN_PIPELINE_CONFIG_SCHEMA = "listen_gen.align-pipeline-config.v1"
ALIGNMENT_TOOL_ID = "listen-gen.alignment"
ALIGNER_STDOUT_LIMIT_BYTES = 16 * 1024 * 1024
SHA256_RE = re.compile(r"sha256:[0-9a-f]{64}")


def _alignment_error(code: str) -> AlignmentFailure:
    return AlignmentFailure(code)


def _object(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise _alignment_error("alignment_output_invalid")
    return value


def _integer(value: Any, location: str, minimum: int = 0) -> int:
    if (
        not isinstance(value, int)
        or isinstance(value, bool)
        or value < minimum
    ):
        raise _alignment_error("alignment_output_invalid")
    return value


def _confidence(value: Any) -> float | None:
    if value is None:
        return None
    if (
        not isinstance(value, (int, float))
        or isinstance(value, bool)
        or not 0 <= value <= 1
    ):
        raise _alignment_error("alignment_output_invalid")
    return float(value)


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _integer_offset(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _read_bounded(path: Path, limit: int) -> bytes:
    """Read a file without ever buffering more than ``limit`` bytes.

    Stops as soon as the bound is exceeded so an oversized alignment result is
    never read into memory; the failure message carries no path or content.
    """
    total = 0
    chunks: list[bytes] = []
    with path.open("rb") as handle:
        while chunk := handle.read(64 * 1024):
            if total + len(chunk) > limit:
                raise _alignment_error("alignment_output_too_large")
            total += len(chunk)
            chunks.append(chunk)
    return b"".join(chunks)


# ---------------------------------------------------------------------------
# Immutable request / result types
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class AlignmentToken:
    index: int
    kind: str
    text: str
    normalized: str | None
    start_char: int
    end_char: int


@dataclass(frozen=True)
class AlignmentSentence:
    id: str
    index: int
    start_ms: int
    end_ms: int
    original_text: str
    display_text: str
    tokens: tuple[AlignmentToken, ...]


@dataclass(frozen=True)
class AlignmentRequest:
    """The exact media input plus the exact emitted subtitle tokenization."""

    media_path: Path
    language: str
    sentences: tuple[AlignmentSentence, ...]


@dataclass(frozen=True)
class RawComponent:
    """One aligner-provided timing component before word resolution.

    For the normalized command/fixture protocol a component is one word-level
    timing. For the whisper.cpp adapter a component is one lexical whisper
    token, and one-or-more consecutive components may be aggregated into a
    single emitted subtitle word token.
    """

    sentence_index: int | None
    text: str
    start_ms: int
    end_ms: int
    confidence: float | None
    timing_source: str


@dataclass(frozen=True)
class AlignedWord:
    sentence_id: str
    token_index: int
    start_ms: int
    end_ms: int
    confidence: float | None
    timing_source: str


@dataclass(frozen=True)
class AlignmentResult:
    """Provider-neutral alignment result with alignment provenance identity."""

    words: tuple[AlignedWord, ...]
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


class AlignerAdapter(Protocol):
    """Provider-neutral seam for expensive word alignment."""

    def align(self, request: AlignmentRequest) -> AlignmentResult: ...


# ---------------------------------------------------------------------------
# Shared normalization and token resolution
# ---------------------------------------------------------------------------


def _is_lexical(text: str) -> bool:
    return any(character.isalnum() or character == "_" for character in text)


def _normalize_aligned_text(text: str) -> str | None:
    """Normalize accumulated aligner text for exact subtitle-word matching.

    Whitespace is stripped and leading/trailing punctuation is removed so that
    whisper-style token text such as ``" Hello,"`` matches the subtitle word
    token ``"Hello"`` and an internal apostrophe such as ``"don'"`` keeps its
    match path. Non-lexical text (punctuation or whitespace only) returns
    ``None`` and is never fabricated into a word timing.
    """
    stripped = text.strip()
    if not stripped or not _is_lexical(stripped):
        return None
    while stripped and unicodedata.category(stripped[0]).startswith("P"):
        stripped = stripped[1:]
    while stripped and unicodedata.category(stripped[-1]).startswith("P"):
        stripped = stripped[:-1]
    if not _is_lexical(stripped):
        return None
    return unicodedata.normalize("NFKC", stripped).casefold()


def _aggregate_confidence(components: list[RawComponent]) -> float | None:
    """Deterministically aggregate the confidence of one matched word group.

    The confidence is emitted only when every lexical component in the matched
    group carries one, and is then the deterministic minimum; if any component
    confidence is missing, the aggregated confidence is omitted (``None``) so a
    partial confidence is never presented as a full one.
    """
    if any(component.confidence is None for component in components):
        return None
    return min(component.confidence for component in components)


def _resolve_words(
    sentences: tuple[AlignmentSentence, ...],
    components: list[RawComponent],
    *,
    aggregate: bool = False,
) -> tuple[AlignedWord, ...]:
    """Resolve aligner components to exact emitted subtitle word tokens.

    This enforces full lexical-token coverage: every ``word`` token of the
    emitted Subtitle Text Track must be matched by exactly one group of
    aligner components in presentation order, and no lexical component may
    remain unmatched. Any deviation raises a qualification failure so the
    package can degrade.

    With ``aggregate=False`` (the normalized command/fixture protocol) each
    component is a word-level timing and must match exactly one subtitle word
    token. With ``aggregate=True`` (whisper.cpp tokens) one-or-more
    consecutive lexical components are aggregated into each word: the grouped
    timing uses the first component start and last component end, the
    confidence is the deterministic minimum over the matched components
    (omitted when any component lacks one), and the normalized concatenation
    must equal the exact subtitle word token. Punctuation and special tokens
    are never fabricated into words.

    The matcher is linear: every component is consumed at most once, each
    consumed component adds at least one lexical character to the normalized
    accumulation, and the accumulation is checked against the target word, so
    aggregation terminates without an arbitrary component cap even for a
    single no-whitespace non-ASCII word token built from many components.
    """
    targets: list[tuple[AlignmentSentence, AlignmentToken]] = [
        (sentence, token)
        for sentence in sentences
        for token in sentence.tokens
        if token.kind == "word"
    ]
    if not targets or not components:
        raise _alignment_error("alignment_qualification_failed")
    aligned: list[AlignedWord] = []
    component_index = 0
    for sentence, token in targets:
        accumulation = ""
        used: list[RawComponent] = []
        matched = False
        while True:
            if component_index >= len(components) or (not aggregate and used):
                break
            component = components[component_index]
            text = component.text.strip()
            if not text or not _is_lexical(text):
                component_index += 1
                continue
            candidate = accumulation + text
            normalized = _normalize_aligned_text(candidate)
            if normalized == token.normalized:
                if (
                    component.sentence_index is not None
                    and component.sentence_index != sentence.index
                ):
                    raise _alignment_error("alignment_qualification_failed")
                used.append(component)
                component_index += 1
                aligned.append(
                    AlignedWord(
                        sentence_id=sentence.id,
                        token_index=token.index,
                        start_ms=used[0].start_ms,
                        end_ms=used[-1].end_ms,
                        confidence=_aggregate_confidence(used),
                        timing_source=used[0].timing_source,
                    )
                )
                matched = True
                break
            if normalized is None or not token.normalized.startswith(normalized):
                raise _alignment_error("alignment_qualification_failed")
            used.append(component)
            component_index += 1
            accumulation = candidate
        if not matched:
            raise _alignment_error("alignment_qualification_failed")
    while component_index < len(components):
        text = components[component_index].text.strip()
        if text and _is_lexical(text):
            raise _alignment_error("alignment_qualification_failed")
        component_index += 1
    return tuple(aligned)


def _qualify_words(
    words: tuple[AlignedWord, ...],
    sentences: tuple[AlignmentSentence, ...],
    duration_ms: int,
) -> tuple[AlignedWord, ...]:
    """Enforce monotonic, bounded, non-duplicated word timings.

    The rules mirror the Core content-package v1 inspector: half-open positive
    ranges, sentence and media bounds, non-decreasing times in presentation
    order, unique word references, and confidences within ``[0, 1]``.
    """
    by_id = {sentence.id: sentence for sentence in sentences}
    previous_reference: tuple[int, int] | None = None
    previous_time: tuple[int, int] | None = None
    seen: set[tuple[str, int]] = set()
    for word in words:
        sentence = by_id[word.sentence_id]
        if not (word.start_ms < word.end_ms):
            raise _alignment_error("alignment_qualification_failed")
        if word.end_ms > duration_ms:
            raise _alignment_error("alignment_qualification_failed")
        if word.start_ms < sentence.start_ms or word.end_ms > sentence.end_ms:
            raise _alignment_error("alignment_qualification_failed")
        if word.confidence is not None and not 0 <= word.confidence <= 1:
            raise _alignment_error("alignment_qualification_failed")
        reference = (sentence.index, word.token_index)
        timing = (word.start_ms, word.end_ms)
        if previous_reference is not None and previous_reference >= reference:
            raise _alignment_error("alignment_qualification_failed")
        if previous_time is not None and previous_time > timing:
            raise _alignment_error("alignment_qualification_failed")
        if (word.sentence_id, word.token_index) in seen:
            raise _alignment_error("alignment_qualification_failed")
        seen.add((word.sentence_id, word.token_index))
        previous_reference = reference
        previous_time = timing
    if not words:
        raise _alignment_error("alignment_qualification_failed")
    return words


# ---------------------------------------------------------------------------
# Normalized align-result protocol parsing
# ---------------------------------------------------------------------------


def _parse_align_result(raw: Any, request: AlignmentRequest) -> AlignmentResult:
    """Parse and validate a ``listen_gen.align-result.v1`` document.

    Words reference a subtitle sentence index plus the lexical word text; the
    shared resolver maps them onto the exact emitted sentence/token refs.
    """
    value = _object(raw, "/")
    if value.get("schema") != ALIGN_RESULT_SCHEMA:
        raise _alignment_error("alignment_output_invalid")
    provider = _object(value.get("provider"), "/provider")
    provider_id = provider.get("id")
    provider_version = provider.get("version")
    if not all(
        isinstance(item, str) and item.strip()
        for item in (provider_id, provider_version)
    ):
        raise _alignment_error("alignment_output_invalid")
    model = value.get("model")
    model_id = model_version = None
    if model is not None:
        model = _object(model, "/model")
        model_id, model_version = model.get("id"), model.get("version")
        if not all(
            isinstance(item, str) and item.strip()
            for item in (model_id, model_version)
        ):
            raise _alignment_error("alignment_output_invalid")
    config_sha256 = value.get("config_sha256")
    if config_sha256 is not None and (
        not isinstance(config_sha256, str) or not SHA256_RE.fullmatch(config_sha256)
    ):
        raise _alignment_error("alignment_output_invalid")
    raw_value = value.get("words")
    if not isinstance(raw_value, list) or not raw_value:
        raise _alignment_error("alignment_output_invalid")
    components: list[RawComponent] = []
    for index, raw_word in enumerate(raw_value):
        location = f"/words/{index}"
        word = _object(raw_word, location)
        sentence_index = _integer(word.get("sentence_index"), f"{location}/sentence_index")
        text = word.get("text")
        if not isinstance(text, str) or not text.strip():
            raise _alignment_error("alignment_output_invalid")
        start_ms = _integer(word.get("start_ms"), f"{location}/start_ms")
        end_ms = _integer(word.get("end_ms"), f"{location}/end_ms", 1)
        if end_ms <= start_ms:
            raise _alignment_error("alignment_output_invalid")
        timing_source = word.get("timing_source", "forced_aligned")
        if timing_source not in TIMING_SOURCES:
            raise _alignment_error("alignment_output_invalid")
        components.append(
            RawComponent(
                sentence_index=sentence_index,
                text=text,
                start_ms=start_ms,
                end_ms=end_ms,
                confidence=_confidence(word.get("confidence")),
                timing_source=timing_source,
            )
        )
    words = _resolve_words(request.sentences, components)
    return AlignmentResult(
        words=words,
        provider_id=provider_id,
        provider_version=provider_version,
        model_id=model_id,
        model_version=model_version,
        config_sha256=config_sha256,
    )


# ---------------------------------------------------------------------------
# Adapters
# ---------------------------------------------------------------------------


class FixtureAlignerAdapter:
    """Offline alignment adapter that replays a committed align-result fixture.

    It never contacts a service and needs no media commands, so the offline
    fixture provider path stays fully deterministic.
    """

    def __init__(self, fixture_path: Path):
        if not isinstance(fixture_path, Path) or not fixture_path.is_file():
            raise ConversionError("alignment fixture must be a regular file")
        self.fixture_path = fixture_path

    def align(self, request: AlignmentRequest) -> AlignmentResult:
        if not request.media_path.is_file():
            raise ConversionError("media input is not a regular file")
        try:
            raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        except OSError as error:
            raise _alignment_error("alignment_failed") from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _alignment_error("alignment_output_invalid") from error
        return _parse_align_result(raw, request)


def _subtitle_input_document(request: AlignmentRequest) -> bytes:
    """Serialize the exact emitted Subtitle Text Track payload for aligners."""
    document = {
        "schema": SUBTITLE_INPUT_SCHEMA,
        "language": request.language,
        "sentences": [
            {
                "id": sentence.id,
                "index": sentence.index,
                "start_ms": sentence.start_ms,
                "end_ms": sentence.end_ms,
                "original_text": sentence.original_text,
                "display_text": sentence.display_text,
                "tokens": [
                    {
                        "index": token.index,
                        "kind": token.kind,
                        "text": token.text,
                        "normalized": token.normalized,
                        "start_char": token.start_char,
                        "end_char": token.end_char,
                    }
                    for token in sentence.tokens
                ],
            }
            for sentence in request.sentences
        ],
    }
    return (
        json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


class CommandAlignerAdapter:
    """Run an external aligner as an argv-only subprocess.

    The aligner receives the normalized WAV at the exact ``{media}``
    placeholder and the exact emitted subtitle payload at the exact
    ``{transcript}`` placeholder, and must write one
    ``listen_gen.align-result.v1`` JSON document to stdout. Shell parsing is
    deliberately never involved.
    """

    def __init__(
        self,
        executable: str,
        arguments: list[str],
        timeout_seconds: float,
        *,
        progress: Callable[[str], None] | None = None,
    ):
        if not executable:
            raise ConversionError("alignment command executable must be non-empty")
        if (
            arguments.count("{media}") != 1
            or arguments.count("{transcript}") != 1
        ):
            raise ConversionError(
                "alignment command arguments must contain exactly one "
                "{media} and one {transcript} placeholder"
            )
        if timeout_seconds <= 0:
            raise ConversionError("alignment command timeout must be positive")
        self.executable = executable
        self.arguments = tuple(arguments)
        self.timeout_seconds = timeout_seconds
        self.progress = progress

    def align(self, request: AlignmentRequest) -> AlignmentResult:
        if not request.media_path.is_file():
            raise ConversionError("media input is not a regular file")
        with tempfile.TemporaryDirectory(prefix="listen-gen-align-") as directory:
            transcript_path = Path(directory) / "subtitle-input.json"
            try:
                transcript_path.write_bytes(_subtitle_input_document(request))
            except OSError as error:
                raise _alignment_error("alignment_failed") from error
            argv = [
                self.executable,
                *(
                    str(request.media_path)
                    if argument == "{media}"
                    else (
                        str(transcript_path)
                        if argument == "{transcript}"
                        else argument
                    )
                    for argument in self.arguments
                ),
            ]
            try:
                completed = run_argv(
                    argv,
                    timeout_seconds=self.timeout_seconds,
                    stdout_limit_bytes=ALIGNER_STDOUT_LIMIT_BYTES,
                )
            except ProcessTimedOut as error:
                raise _alignment_error("alignment_timeout") from error
            except ProcessOutputTooLarge as error:
                raise _alignment_error("alignment_output_too_large") from error
            except OSError as error:
                raise _alignment_error("alignment_start_failed") from error
            if completed.returncode != 0:
                raise _alignment_error("alignment_failed")
            try:
                raw = json.loads(completed.stdout)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise _alignment_error("alignment_output_invalid") from error
            return _parse_align_result(raw, request)


def _parse_whisper_tokens(raw: Any) -> list[RawComponent]:
    """Derive raw timing components from whisper.cpp full-JSON token offsets.

    whisper.cpp ``-ojf`` output places per-token text, offsets, and probability
    inside each transcription segment. These are model/BPE tokens, not
    guaranteed one per subtitle word; one-or-more consecutive lexical tokens
    are aggregated deterministically by :func:`_resolve_words`. Special tokens
    are skipped; every other token must carry a positive half-open millisecond
    range. The timing source is ``asr_aligned`` because these are the ASR
    decoder's own token timestamps qualified against the emitted subtitle,
    not text-constrained forced alignment.
    """
    if not isinstance(raw, dict):
        raise _alignment_error("alignment_output_invalid")
    transcription = raw.get("transcription")
    if not isinstance(transcription, list) or not transcription:
        raise _alignment_error("alignment_output_invalid")
    components: list[RawComponent] = []
    for raw_segment in transcription:
        if not isinstance(raw_segment, dict):
            raise _alignment_error("alignment_output_invalid")
        tokens = raw_segment.get("tokens")
        if not isinstance(tokens, list):
            raise _alignment_error("alignment_output_invalid")
        for token in tokens:
            if not isinstance(token, dict):
                raise _alignment_error("alignment_output_invalid")
            text = token.get("text")
            if not isinstance(text, str):
                raise _alignment_error("alignment_output_invalid")
            if "<|" in text:
                continue
            offsets = token.get("offsets")
            if not isinstance(offsets, dict):
                raise _alignment_error("alignment_output_invalid")
            start_ms = offsets.get("from")
            end_ms = offsets.get("to")
            if not _integer_offset(start_ms) or not _integer_offset(end_ms):
                raise _alignment_error("alignment_output_invalid")
            if end_ms <= start_ms:
                raise _alignment_error("alignment_output_invalid")
            confidence = _confidence(token.get("p"))
            components.append(
                RawComponent(
                    sentence_index=None,
                    text=text,
                    start_ms=start_ms,
                    end_ms=end_ms,
                    confidence=confidence,
                    timing_source="asr_aligned",
                )
            )
    if not components:
        raise _alignment_error("alignment_output_invalid")
    return components


class WhisperCppAlignerAdapter:
    """First-class whisper.cpp alignment adapter.

    ``media_path`` is the temporary 16 kHz mono PCM WAV produced for the
    pipeline; this adapter never sees the original media container. It reruns
    whisper-cli directly (never through a shell) with full JSON output and
    derives per-token timing from the ASR decoder's own token offsets, then
    qualifies those tokens against the emitted subtitle. This is
    ``asr_aligned`` timing, not text-constrained forced alignment; it is
    explicitly distinct from an external command adapter that may honestly
    emit ``forced_aligned``. One-or-more consecutive lexical tokens are
    aggregated into each exact subtitle word token. Runtime and model bytes
    are hashed before and after the run so mutation is detected.
    """

    def __init__(
        self,
        executable: str,
        model_path: Path,
        model_id: str,
        language: str,
        translate_to_english: bool,
        timeout_seconds: float,
    ) -> None:
        if not executable:
            raise ConversionError("whisper.cpp aligner executable must be non-empty")
        if model_path is None or not model_path.is_file():
            raise ConversionError("whisper.cpp aligner model must be a regular file")
        if not isinstance(model_id, str) or not model_id.strip():
            raise ConversionError("whisper.cpp aligner model id must be non-empty")
        if not isinstance(language, str) or not LANGUAGE_RE.fullmatch(language):
            raise ConversionError("whisper.cpp aligner language must be a valid language tag")
        if timeout_seconds <= 0:
            raise ConversionError("whisper.cpp aligner timeout must be positive")
        self.executable = executable
        self.model_path = model_path
        self.model_id = model_id.strip()
        self.language = language.strip()
        self.translate_to_english = translate_to_english
        self.timeout_seconds = timeout_seconds

    def _resolve_executable(self) -> str:
        candidate = Path(self.executable)
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
        resolved = shutil.which(self.executable)
        if resolved is None:
            raise _alignment_error("alignment_start_failed")
        return resolved

    def align(self, request: AlignmentRequest) -> AlignmentResult:
        if not request.media_path.is_file():
            raise ConversionError("media input is not a regular file")
        resolved = self._resolve_executable()
        try:
            runtime_sha256 = _sha256_file(Path(resolved))
        except OSError as error:
            raise _alignment_error("alignment_start_failed") from error
        try:
            model_sha256 = _sha256_file(self.model_path)
        except OSError as error:
            raise _alignment_error("alignment_start_failed") from error
        with tempfile.TemporaryDirectory(prefix="listen-gen-whisper-align-") as directory:
            output_prefix = Path(directory) / "result"
            argv = [
                resolved,
                "-m",
                str(self.model_path),
                "-f",
                str(request.media_path),
                "-ojf",
                "-of",
                str(output_prefix),
                "-l",
                self.language,
            ]
            if self.translate_to_english:
                argv.append("-tr")
            try:
                completed = run_argv(
                    argv,
                    timeout_seconds=self.timeout_seconds,
                    stdout_limit_bytes=None,
                )
            except ProcessTimedOut as error:
                raise _alignment_error("alignment_timeout") from error
            except OSError as error:
                raise _alignment_error("alignment_start_failed") from error
            if completed.returncode != 0:
                raise _alignment_error("alignment_failed")
            try:
                runtime_after = _sha256_file(Path(resolved))
                model_after = _sha256_file(self.model_path)
            except OSError as error:
                raise _alignment_error("alignment_failed") from error
            if runtime_after != runtime_sha256 or model_after != model_sha256:
                raise _alignment_error("alignment_failed")
            result_path = Path(f"{output_prefix}.json")
            if not result_path.is_file():
                raise _alignment_error("alignment_output_invalid")
            try:
                result_bytes = _read_bounded(
                    result_path, ALIGNER_STDOUT_LIMIT_BYTES
                )
            except OSError as error:
                raise _alignment_error("alignment_output_invalid") from error
            try:
                raw = json.loads(result_bytes)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise _alignment_error("alignment_output_invalid") from error
            components = _parse_whisper_tokens(raw)
        config_value = {
            "schema": WHISPER_ALIGN_CONFIG_SCHEMA,
            "provider_id": "whisper.cpp",
            "provider_version": f"sha256:{runtime_sha256}",
            "model_id": self.model_id,
            "model_version": f"sha256:{model_sha256}",
            "requested_language": self.language,
            "task": (
                "translate_to_english" if self.translate_to_english else "transcribe"
            ),
            "output_format": "whisper.cpp-full-json",
            "token_source": "transcription[].tokens",
            "timing_source": "asr_aligned",
            "matching": {
                "text_normalization": "nfkc_casefold",
                "token_aggregation": "consecutive_lexical_tokens",
                "confidence_aggregation": "minimum_when_all_present",
                "strip_whitespace": True,
                "strip_punctuation": True,
                "coverage": "every_subtitle_word_token",
                "bounds": "subtitle_sentence_and_media_duration",
            },
        }
        config_bytes = json.dumps(
            config_value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        words = _resolve_words(
            request.sentences, components, aggregate=True
        )
        return AlignmentResult(
            words=words,
            provider_id="whisper.cpp",
            provider_version=f"sha256:{runtime_sha256}",
            model_id=self.model_id,
            model_version=f"sha256:{model_sha256}",
            config_sha256=f"sha256:{hashlib.sha256(config_bytes).hexdigest()}",
        )


# ---------------------------------------------------------------------------
# Pipeline stage
# ---------------------------------------------------------------------------


def _compose_config_sha256(
    provider_config_sha256: str | None, audio_stream_index: int
) -> str:
    """Bind the aligner config identity to the normalization choices."""
    pipeline_config = {
        "schema": ALIGN_PIPELINE_CONFIG_SCHEMA,
        "adapter_protocol": ALIGN_RESULT_SCHEMA,
        "audio_preprocessing": {
            "audio_stream_index": audio_stream_index,
            "channels": 1,
            "container": "wav",
            "sample_format": "pcm_s16le",
            "sample_rate_hz": 16000,
        },
        "provider_config_sha256": provider_config_sha256,
    }
    config_bytes = json.dumps(
        pipeline_config,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(config_bytes).hexdigest()}"


def _word_timeline_resource(
    *,
    subtitle: ResourceFile,
    media_fingerprint: str,
    result: AlignmentResult,
    words: tuple[AlignedWord, ...],
    config_sha256: str | None,
    created_at_ms: int,
) -> ResourceFile:
    provenance: dict[str, Any] = {
        "created_at_ms": created_at_ms,
        "tool": {"id": ALIGNMENT_TOOL_ID, "version": TOOL_VERSION},
        "provider": {"id": result.provider_id, "version": result.provider_version},
    }
    if result.model_id is not None:
        provenance["model"] = {
            "id": result.model_id,
            "version": result.model_version,
        }
    if config_sha256 is not None:
        provenance["config_sha256"] = config_sha256
    payload = {
        "words": [
            {
                "sentence_id": word.sentence_id,
                "token_index": word.token_index,
                "start_ms": word.start_ms,
                "end_ms": word.end_ms,
                "timing_source": word.timing_source,
                **(
                    {"confidence": word.confidence}
                    if word.confidence is not None
                    else {}
                ),
            }
            for word in words
        ]
    }
    return _envelope(
        kind="word_timeline",
        media_fingerprint=media_fingerprint,
        dependencies=[subtitle],
        provenance=provenance,
        quality={"review_status": "machine_checked"},
        payload=payload,
        required=False,
    )


def run_alignment(
    *,
    aligner: AlignerAdapter,
    media_path: Path,
    audio_path: Path,
    audio_stream_index: int | None,
    language: str,
    sentences: tuple[AlignmentSentence, ...],
    subtitle: ResourceFile,
    media_fingerprint: str,
    duration_ms: int,
    created_at_ms: int,
    progress: Callable[[str], None] | None = None,
) -> tuple[str, ResourceFile | None, list[dict[str, str]]]:
    """Run the optional alignment stage and convert failures into degradation.

    Returns ``(status, word_resource, typed_warnings)`` where status is
    ``"produced"`` or ``"degraded"``. Degradable failures preserve the ASR
    subtitle package; cancellation and other ``BaseException`` failures are
    never swallowed.
    """
    if progress is not None:
        progress("aligning")
    try:
        request = AlignmentRequest(
            media_path=audio_path, language=language, sentences=sentences
        )
        result = aligner.align(request)
        words = _qualify_words(result.words, sentences, duration_ms)
        config_sha256 = result.config_sha256
        if audio_stream_index is not None:
            config_sha256 = _compose_config_sha256(
                result.config_sha256, audio_stream_index
            )
        resource = _word_timeline_resource(
            subtitle=subtitle,
            media_fingerprint=media_fingerprint,
            result=result,
            words=words,
            config_sha256=config_sha256,
            created_at_ms=created_at_ms,
        )
        return "produced", resource, []
    except AlignmentFailure as error:
        return "degraded", None, [{"code": error.code, "message": str(error)}]
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = alignment_warning(error)
        return "degraded", None, [{"code": code, "message": message}]
