"""Provider-neutral ASR adapters.

The v1 media packaging orchestration was removed in the Slice 3 cutover; the
adapter layer survives unchanged behind the capability production engine
(``media_to_structured_reading`` derivations).
"""

from __future__ import annotations

import hashlib
import json
import re
import unicodedata
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Callable, Protocol

from .media import AudioPreprocessor
from .package import LANGUAGE_RE, TIMING_SOURCES, ConversionError
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv

TOKEN_RE = re.compile(r"\w+(?:['\u2019]\w+)*|\s+|[^\w\s]", re.UNICODE)
ASR_STDOUT_LIMIT_BYTES = 16 * 1024 * 1024


def _tokens(text: str) -> list[dict[str, Any]]:
    """Deterministically tokenize one sentence into word/whitespace/punct.

    The emitted token indexes are the exact coordinates the word timeline
    resource refers to; tokenization must be lossless or it is a failure.
    """
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

    def __init__(
        self, fixture_path: Path, *, progress: Callable[[str], None] | None = None
    ):
        self.fixture_path = fixture_path
        self.progress = progress

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        if self.progress is not None:
            self.progress("transcribing")
        raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        return _parse_transcript(raw)


class CommandAsrAdapter:
    """Run an external ASR wrapper as an argv-only subprocess.

    The wrapper receives the normalized 16 kHz mono PCM WAV path through the
    single ``{media}`` placeholder and writes one normalized ASR result JSON
    object to stdout. No shell is used.
    """

    def __init__(
        self,
        executable: str,
        arguments: list[str],
        timeout_seconds: float,
        *,
        progress: Callable[[str], None] | None = None,
    ):
        if not executable.strip():
            raise ValueError("asr command executable must be non-empty")
        if arguments.count("{media}") != 1:
            raise ValueError(
                "asr command arguments must contain exactly one {media} placeholder"
            )
        if timeout_seconds <= 0:
            raise ValueError("asr command timeout must be positive")
        self.executable = executable
        self.arguments = list(arguments)
        self.timeout_seconds = timeout_seconds
        self.progress = progress

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if self.progress is not None:
            self.progress("transcribing")
        argv = [
            item.replace("{media}", str(media_path)) for item in self.arguments
        ]
        try:
            completed = run_argv(
                [self.executable, *argv],
                timeout_seconds=self.timeout_seconds,
                stdout_limit_bytes=ASR_STDOUT_LIMIT_BYTES,
            )
        except ProcessTimedOut as error:
            raise ConversionError("asr command timed out") from error
        except ProcessOutputTooLarge as error:
            raise ConversionError("asr command output exceeded the safety limit") from error
        if completed.returncode != 0:
            raise ConversionError(
                f"asr command failed with exit status {completed.returncode}"
            )
        try:
            document = json.loads(completed.stdout)
        except json.JSONDecodeError as error:
            raise ConversionError("asr command returned invalid json") from error
        return _parse_transcript(document)


class PreprocessingAsrAdapter:
    """Supply normalized temporary audio to an underlying ASR adapter."""

    def __init__(
        self,
        adapter: AsrAdapter,
        preprocessor: AudioPreprocessor,
        *,
        audio_stream_index: int | None,
        progress: Callable[[str], None] | None = None,
    ):
        self.adapter = adapter
        self.preprocessor = preprocessor
        self.audio_stream_index = audio_stream_index
        self.progress = progress

    def transcribe(self, media_path: Path) -> AsrTranscript:
        with self.preprocessor.prepare(
            media_path, audio_stream_index=self.audio_stream_index
        ) as prepared:
            if self.progress is not None:
                self.progress("transcribing")
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
        raise ConversionError(f"{location} must be a JSON object")
    return value


def _integer(value: Any, location: str, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise ConversionError(f"{location} must be an integer")
    if value < minimum:
        raise ConversionError(f"{location} must be at least {minimum}")
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
        if raw_words is None:
            raw_words = []
        if not isinstance(raw_words, list):
            raise ConversionError(f"{location}/words must be an array")
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


# ---------------------------------------------------------------------------
# Neural ASR sidecar adapters (Qwen3-ASR, SenseVoice)
# ---------------------------------------------------------------------------
#
# Both providers run their heavy runtime (torch / transformers / qwen-asr /
# FunASR) in a separate ``tools/*_asr_wrapper.py`` subprocess so the base
# install stays light.  The wrapper receives the normalized 16 kHz mono WAV
# and prints one small "core" JSON object.  These adapters do the pure work
# that must be tested without a model: language mapping, char-anchored word
# timing, provider provenance, and the config identity hash.

_WORD_RE = re.compile(r"\w+(?:['’]\w+)*", re.UNICODE)

# Qwen3-ASR emits a language *name*; the reading layer needs a stable BCP-47
# primary subtag.  This covers every language the 0.6B model supports.  An
# unrecognized value is a provider output error, never a silent fall back to
# English.
_QWEN_NAME_TO_TAG = {
    "chinese": "zh",
    "english": "en",
    "cantonese": "yue",
    "arabic": "ar",
    "german": "de",
    "french": "fr",
    "spanish": "es",
    "portuguese": "pt",
    "indonesian": "id",
    "italian": "it",
    "korean": "ko",
    "russian": "ru",
    "thai": "th",
    "vietnamese": "vi",
    "japanese": "ja",
    "turkish": "tr",
    "hindi": "hi",
    "malay": "ms",
    "dutch": "nl",
    "swedish": "sv",
    "danish": "da",
    "finnish": "fi",
    "polish": "pl",
    "czech": "cs",
    "filipino": "fil",
    "persian": "fa",
    "greek": "el",
    "romanian": "ro",
    "hungarian": "hu",
    "macedonian": "mk",
}
_TAG_TO_QWEN_NAME = {
    tag: name.capitalize() for name, tag in _QWEN_NAME_TO_TAG.items()
}

# SenseVoiceSmall emits ``<|lang|>`` / ``<|emotion|>`` / ``<|event|>`` meta
# tags.  Only these language tags become the reading language; everything else
# is stripped from the transcript text.
_SENSEVOICE_TAG_TO_TAG = {
    "zh": "zh",
    "en": "en",
    "yue": "yue",
    "ja": "ja",
    "ko": "ko",
}
_META_TAG_RE = re.compile(r"<\|[^|>]*\|>")

QWEN3_ASR_PROVIDER_ID = "qwen3-asr"
QWEN3_ASR_PROVIDER_VERSION = "v1"
QWEN3_ASR_CORE_SCHEMA = "listen_gen.qwen3-asr-core.v1"
QWEN3_ASR_DEFAULT_MODEL_ID = "Qwen/Qwen3-ASR-0.6B"
QWEN3_ASR_DEFAULT_ALIGNER_MODEL_ID = "Qwen/Qwen3-ForcedAligner-0.6B"

SENSEVOICE_PROVIDER_ID = "sensevoice"
SENSEVOICE_PROVIDER_VERSION = "v1"
SENSEVOICE_CORE_SCHEMA = "listen_gen.sensevoice-asr-core.v1"
SENSEVOICE_DEFAULT_MODEL_ID = "iic/SenseVoiceSmall"
SENSEVOICE_DEFAULT_VAD_MODEL = "fsmn-vad"


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _fold_token(text: str) -> str:
    """Fold a unit to case-folded alphanumerics for text-vs-item matching.

    The forced aligner may tokenize differently from the reading (``don't`` as
    ``do`` + ``n't``, CJK per character, surrounding punctuation).  Reducing to
    alphanumerics collapses those differences so a reading word and the
    provider item(s) that spell it fold to the same key.
    """
    return "".join(
        ch for ch in unicodedata.normalize("NFC", text).casefold() if ch.isalnum()
    )


def _run_sidecar(argv: list[str], timeout_seconds: float) -> str:
    try:
        completed = run_argv(
            argv,
            timeout_seconds=timeout_seconds,
            stdout_limit_bytes=ASR_STDOUT_LIMIT_BYTES,
        )
    except ProcessTimedOut as error:
        raise ConversionError("asr wrapper timed out") from error
    except ProcessOutputTooLarge as error:
        raise ConversionError("asr wrapper output exceeded the safety limit") from error
    except OSError as error:
        raise ConversionError("asr wrapper could not be started") from error
    if completed.returncode != 0:
        raise ConversionError(
            f"asr wrapper failed with exit status {completed.returncode}"
        )
    return completed.stdout


def _core_document(stdout: str, schema: str, provider: str) -> dict[str, Any]:
    try:
        document = json.loads(stdout)
    except json.JSONDecodeError as error:
        raise ConversionError(f"{provider} wrapper returned invalid json") from error
    if not isinstance(document, dict) or document.get("schema") != schema:
        raise ConversionError(f"{provider} wrapper returned an unexpected schema")
    return document


def _core_runtime_version(document: dict[str, Any], provider: str) -> str:
    version = document.get("runtime_version")
    if not isinstance(version, str) or not version.strip():
        raise ConversionError(f"{provider} wrapper omitted its runtime version")
    return version.strip()


def _normalize_core_items(raw_items: Any, provider: str) -> list[tuple[str, int, int]]:
    """Validate the flat forced-align items a wrapper reports (absolute ms)."""
    if raw_items is None:
        return []
    if not isinstance(raw_items, list):
        raise ConversionError(f"{provider} wrapper items must be an array")
    items: list[tuple[str, int, int]] = []
    for raw_item in raw_items:
        if not isinstance(raw_item, dict):
            raise ConversionError(f"{provider} wrapper item must be an object")
        text = raw_item.get("text")
        start_ms = raw_item.get("start_ms")
        end_ms = raw_item.get("end_ms")
        if not isinstance(text, str):
            raise ConversionError(f"{provider} wrapper item text must be a string")
        if (
            not isinstance(start_ms, int)
            or isinstance(start_ms, bool)
            or not isinstance(end_ms, int)
            or isinstance(end_ms, bool)
            or start_ms < 0
            or end_ms < start_ms
        ):
            raise ConversionError(f"{provider} wrapper item timing is invalid")
        items.append((text, start_ms, end_ms))
    return items


def _words_from_aligned_items(
    text: str, items: list[tuple[str, int, int]]
) -> list[dict[str, Any]]:
    """Anchor flat forced-align items onto the reading word tokens.

    Every emitted word is exactly a ``_WORD_RE`` token span of ``text`` (so its
    span coincides with the sentence-assembly lexical spans that decide
    boundaries), and its timing comes from the provider item(s) that spell it.

    The forced aligner tokenizes the exact transcript text, so the folded
    reading words and the folded items are the same character stream — only the
    token boundaries differ (``red-eye`` reads as two words but aligns as one
    ``redeye`` item; ``don't`` reads as one word but aligns as ``do`` + ``n't``;
    CJK reads as one run but aligns per character).  Walking that shared folded
    stream character-by-character reunites each reading word with the item(s)
    that spell it, handling 1:1, provider sub-splits, and provider merges
    uniformly.  A reading word the aligner never spells carries no timing —
    nothing is fabricated or interpolated from character counts.
    """
    word_spans = [(match.start(), match.end()) for match in _WORD_RE.finditer(text)]
    item_folds = [_fold_token(item_text) for item_text, _start, _end in items]
    char_item: list[int] = []
    for index, folded in enumerate(item_folds):
        char_item.extend([index] * len(folded))
    stream = "".join(item_folds)
    total = len(stream)
    words: list[dict[str, Any]] = []
    position = 0
    previous_end_ms = 0
    for start_char, end_char in word_spans:
        target = _fold_token(text[start_char:end_char])
        if not target:
            continue
        length = len(target)
        if position + length <= total and stream[position : position + length] == target:
            begin = position
        else:
            # Divergence should not happen (same underlying text); if the
            # aligner ever omits a word, resync to its next occurrence rather
            # than desyncing the whole stream.
            begin = stream.find(target, position)
            if begin == -1:
                continue
        end = begin + length
        position = end
        start_ms = items[char_item[begin]][1]
        end_ms = items[char_item[end - 1]][2]
        if start_ms < previous_end_ms:
            start_ms = previous_end_ms
        if end_ms <= start_ms:
            continue
        words.append(
            {
                "start_char": start_char,
                "end_char": end_char,
                "start_ms": start_ms,
                "end_ms": end_ms,
                "timing_source": "asr_reported",
            }
        )
        previous_end_ms = end_ms
    return words


def _qwen_language_to_tag(raw_language: str) -> str:
    first = raw_language.split(",")[0].strip().lower() if raw_language else ""
    tag = _QWEN_NAME_TO_TAG.get(first)
    if tag is None:
        raise ConversionError("qwen3 asr returned an unrecognized language")
    return tag


class Qwen3AsrAdapter:
    """Default local ASR provider backed by Qwen3-ASR-0.6B via a sidecar.

    The ``tools/qwen3_asr_wrapper.py`` subprocess runs the official ``qwen-asr``
    Transformers backend with the Qwen3 forced aligner attached, so the wrapper
    already handles long-audio chunking and returns real per-token timestamps.
    This adapter maps the wrapper's language name to a BCP-47 tag, anchors the
    forced-align items onto reading word tokens, and stamps provider
    provenance.  The word timings are only *evidence* for sentence assembly; the
    authoritative word timeline is still produced by the configured forced
    aligner in the rich chain.
    """

    def __init__(
        self,
        python: Path,
        sidecar: Path,
        *,
        model_id: str = QWEN3_ASR_DEFAULT_MODEL_ID,
        forced_aligner_model_id: str = QWEN3_ASR_DEFAULT_ALIGNER_MODEL_ID,
        language: str = "auto",
        device: str = "auto",
        dtype: str = "auto",
        timeout_seconds: float = 3600.0,
        progress: Callable[[str], None] | None = None,
    ) -> None:
        if not python.is_file():
            raise ConversionError("qwen3 asr python interpreter must be a regular file")
        if not sidecar.is_file():
            raise ConversionError("qwen3 asr sidecar must be a regular file")
        if not model_id.strip():
            raise ConversionError("qwen3 asr model id must be non-empty")
        if not forced_aligner_model_id.strip():
            raise ConversionError("qwen3 asr forced aligner model id must be non-empty")
        if timeout_seconds <= 0:
            raise ConversionError("qwen3 asr timeout must be positive")
        self.python = python
        self.sidecar = sidecar
        self.model_id = model_id.strip()
        self.forced_aligner_model_id = forced_aligner_model_id.strip()
        self.language = (language or "auto").strip() or "auto"
        self.device = (device or "auto").strip() or "auto"
        self.dtype = (dtype or "auto").strip() or "auto"
        self.timeout_seconds = timeout_seconds
        self.progress = progress

    def _request_language(self) -> str:
        lang = self.language.lower()
        if lang in ("", "auto", "und"):
            return "auto"
        name = _TAG_TO_QWEN_NAME.get(lang.split("-")[0])
        if name is None:
            raise ConversionError("qwen3 asr language is unsupported")
        return name

    def _config_sha256(self, runtime_version: str) -> str:
        config = {
            "schema": "listen_gen.qwen3-asr-config.v1",
            "provider": QWEN3_ASR_PROVIDER_ID,
            "model_id": self.model_id,
            "forced_aligner_model_id": self.forced_aligner_model_id,
            "language": self.language,
            "device": self.device,
            "dtype": self.dtype,
            "sidecar_sha256": _file_sha256(self.sidecar),
            "runtime_version": runtime_version,
        }
        return "sha256:" + hashlib.sha256(
            json.dumps(config, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        if self.progress is not None:
            self.progress("transcribing")
        argv = [
            str(self.python),
            str(self.sidecar),
            "--audio",
            str(media_path),
            "--model-id",
            self.model_id,
            "--forced-aligner-model-id",
            self.forced_aligner_model_id,
            "--language",
            self._request_language(),
            "--device",
            self.device,
            "--dtype",
            self.dtype,
        ]
        document = _core_document(
            _run_sidecar(argv, self.timeout_seconds),
            QWEN3_ASR_CORE_SCHEMA,
            "qwen3 asr",
        )
        runtime_version = _core_runtime_version(document, "qwen3 asr")
        raw_language = document.get("language")
        text = document.get("text")
        if not isinstance(raw_language, str) or not isinstance(text, str):
            raise ConversionError("qwen3 asr wrapper returned invalid fields")
        text = text.strip()
        if not text:
            raise ConversionError("qwen3 asr produced an empty transcript")
        language = _qwen_language_to_tag(raw_language)
        items = _normalize_core_items(document.get("items"), "qwen3 asr")
        words = _words_from_aligned_items(text, items)
        if words:
            segment_start = words[0]["start_ms"]
            segment_end = words[-1]["end_ms"]
        else:
            duration_ms = document.get("duration_ms")
            if (
                not isinstance(duration_ms, int)
                or isinstance(duration_ms, bool)
                or duration_ms <= 0
            ):
                raise ConversionError("qwen3 asr produced neither timing nor duration")
            segment_start, segment_end = 0, duration_ms
        if segment_end <= segment_start:
            segment_end = segment_start + 1
        normalized = {
            "schema": "listen_gen.asr-result.v1",
            "language": language,
            "provider": {
                "id": QWEN3_ASR_PROVIDER_ID,
                "version": QWEN3_ASR_PROVIDER_VERSION,
            },
            "model": {"id": self.model_id, "version": runtime_version},
            "config_sha256": self._config_sha256(runtime_version),
            "segments": [
                {
                    "start_ms": segment_start,
                    "end_ms": segment_end,
                    "text": text,
                    "display_text": text,
                    "words": words,
                }
            ],
        }
        return _parse_transcript(normalized)


class SenseVoiceAsrAdapter:
    """Fast / CPU ASR provider backed by SenseVoiceSmall via a sidecar.

    The ``tools/sensevoice_asr_wrapper.py`` subprocess runs the FunASR
    SenseVoice + FSMN-VAD pipeline and returns one timed fragment per VAD speech
    region.  This adapter strips the SenseVoice ``<|...|>`` meta tags out of the
    reading text, maps the language tag to a stable BCP-47 tag, and emits
    segments without word timings (``words=()``) — a VAD region is coarse timed
    evidence, and forced alignment supplies the final word timeline.
    """

    def __init__(
        self,
        python: Path,
        sidecar: Path,
        *,
        model_id: str = SENSEVOICE_DEFAULT_MODEL_ID,
        language: str = "auto",
        device: str = "auto",
        vad_model: str = SENSEVOICE_DEFAULT_VAD_MODEL,
        timeout_seconds: float = 3600.0,
        progress: Callable[[str], None] | None = None,
    ) -> None:
        if not python.is_file():
            raise ConversionError("sensevoice python interpreter must be a regular file")
        if not sidecar.is_file():
            raise ConversionError("sensevoice sidecar must be a regular file")
        if not model_id.strip():
            raise ConversionError("sensevoice model id must be non-empty")
        if timeout_seconds <= 0:
            raise ConversionError("sensevoice timeout must be positive")
        self.python = python
        self.sidecar = sidecar
        self.model_id = model_id.strip()
        self.language = (language or "auto").strip() or "auto"
        self.device = (device or "auto").strip() or "auto"
        self.vad_model = (vad_model or SENSEVOICE_DEFAULT_VAD_MODEL).strip()
        self.timeout_seconds = timeout_seconds
        self.progress = progress

    def _config_sha256(self, runtime_version: str) -> str:
        config = {
            "schema": "listen_gen.sensevoice-asr-config.v1",
            "provider": SENSEVOICE_PROVIDER_ID,
            "model_id": self.model_id,
            "language": self.language,
            "device": self.device,
            "vad_model": self.vad_model,
            "sidecar_sha256": _file_sha256(self.sidecar),
            "runtime_version": runtime_version,
        }
        return "sha256:" + hashlib.sha256(
            json.dumps(config, sort_keys=True, separators=(",", ":")).encode("utf-8")
        ).hexdigest()

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        if self.progress is not None:
            self.progress("transcribing")
        argv = [
            str(self.python),
            str(self.sidecar),
            "--audio",
            str(media_path),
            "--model-id",
            self.model_id,
            "--language",
            self.language,
            "--device",
            self.device,
            "--vad-model",
            self.vad_model,
        ]
        document = _core_document(
            _run_sidecar(argv, self.timeout_seconds),
            SENSEVOICE_CORE_SCHEMA,
            "sensevoice",
        )
        runtime_version = _core_runtime_version(document, "sensevoice")
        raw_segments = document.get("segments")
        if not isinstance(raw_segments, list) or not raw_segments:
            raise ConversionError("sensevoice wrapper returned no segments")
        language: str | None = None
        segments: list[dict[str, Any]] = []
        for raw_segment in raw_segments:
            if not isinstance(raw_segment, dict):
                raise ConversionError("sensevoice segment must be an object")
            start_ms = raw_segment.get("start_ms")
            end_ms = raw_segment.get("end_ms")
            raw_text = raw_segment.get("text")
            if (
                not isinstance(start_ms, int)
                or isinstance(start_ms, bool)
                or not isinstance(end_ms, int)
                or isinstance(end_ms, bool)
                or not isinstance(raw_text, str)
            ):
                raise ConversionError("sensevoice segment fields are invalid")
            segment_language, clean_text = _clean_sensevoice_text(raw_text)
            if not clean_text:
                continue
            if segment_language is not None and language is None:
                language = segment_language
            segments.append(
                {
                    "start_ms": start_ms,
                    "end_ms": end_ms,
                    "text": clean_text,
                    "display_text": clean_text,
                    "words": [],
                }
            )
        if not segments:
            raise ConversionError("sensevoice produced an empty transcript")
        if language is None:
            language = _sensevoice_language(self.language)
        if language is None:
            raise ConversionError("sensevoice returned an unrecognized language")
        normalized = {
            "schema": "listen_gen.asr-result.v1",
            "language": language,
            "provider": {
                "id": SENSEVOICE_PROVIDER_ID,
                "version": SENSEVOICE_PROVIDER_VERSION,
            },
            "model": {"id": self.model_id, "version": runtime_version},
            "config_sha256": self._config_sha256(runtime_version),
            "segments": segments,
        }
        return _parse_transcript(normalized)


def _sensevoice_language(value: str) -> str | None:
    return _SENSEVOICE_TAG_TO_TAG.get((value or "").strip().lower())


def _clean_sensevoice_text(raw_text: str) -> tuple[str | None, str]:
    """Split a SenseVoice hypothesis into (language tag, clean reading text).

    SenseVoice prefixes meta tags such as ``<|en|><|NEUTRAL|><|Speech|>``.  The
    first language tag becomes the reading language; every ``<|...|>`` tag is
    removed from the text so audio-event and emotion markers never leak into
    Structured Reading.
    """
    language: str | None = None
    for match in _META_TAG_RE.finditer(raw_text):
        token = match.group(0)[2:-2].strip().lower()
        if language is None and token in _SENSEVOICE_TAG_TO_TAG:
            language = _SENSEVOICE_TAG_TO_TAG[token]
    clean = _META_TAG_RE.sub("", raw_text)
    return language, " ".join(clean.split()).strip()
