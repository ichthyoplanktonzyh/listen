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
# Faster-Whisper (CTranslate2) & OpenAI Cloud Audio Adapters
# ---------------------------------------------------------------------------


class FasterWhisperAsrAdapter:
    """High-throughput local Whisper transcription using faster-whisper (CTranslate2)."""

    def __init__(
        self,
        *,
        model_size_or_path: str = "base",
        device: str = "auto",
        compute_type: str = "default",
        language: str = "auto",
        beam_size: int = 5,
        word_timestamps: bool = True,
        vad_filter: bool = True,
        engine: Any = None,
    ) -> None:
        self.model_size_or_path = model_size_or_path
        self.device = device
        self.compute_type = compute_type
        self.language = language
        self.beam_size = beam_size
        self.word_timestamps = word_timestamps
        self.vad_filter = vad_filter
        self._engine = engine
        self.config_sha256 = f"sha256:{hashlib.sha256(json.dumps({"schema": "listen_gen.faster-whisper-config.v1", "model": model_size_or_path, "device": device, "compute_type": compute_type, "beam_size": beam_size}, sort_keys=True).encode()).hexdigest()}"

    def _resolve_model(self) -> Any:
        if self._engine is not None:
            return self._engine
        try:
            from faster_whisper import WhisperModel

            return WhisperModel(
                self.model_size_or_path,
                device=self.device,
                compute_type=self.compute_type,
            )
        except ImportError as e:
            raise ConversionError(
                "faster-whisper is not installed. Install with 'pip install faster-whisper'"
            ) from e

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        model = self._resolve_model()
        try:
            kwargs: dict[str, Any] = {
                "beam_size": self.beam_size,
                "word_timestamps": self.word_timestamps,
                "vad_filter": self.vad_filter,
            }
            if self.language != "auto":
                kwargs["language"] = self.language
            segments_gen, info = model.transcribe(str(media_path), **kwargs)
            detected_lang = (
                getattr(info, "language", "en")
                if self.language == "auto"
                else self.language
            )
            if not LANGUAGE_RE.fullmatch(detected_lang):
                detected_lang = "en"
            segments: list[AsrSegment] = []
            previous_end = 0
            for seg in segments_gen:
                start_ms = int(seg.start * 1000)
                end_ms = max(start_ms + 1, int(seg.end * 1000))
                if start_ms < previous_end:
                    start_ms = previous_end
                if end_ms <= start_ms:
                    end_ms = start_ms + 1
                text = seg.text.strip()
                if not text:
                    continue
                words: list[AsrWord] = []
                if getattr(seg, "words", None):
                    prev_char = 0
                    prev_word_end = start_ms
                    for w in seg.words:
                        w_text = w.word.strip()
                        if not w_text:
                            continue
                        w_start = max(start_ms, int(w.start * 1000))
                        w_end = min(end_ms, max(w_start + 1, int(w.end * 1000)))
                        if w_start < prev_word_end:
                            w_start = prev_word_end
                        if w_end <= w_start:
                            w_end = w_start + 1
                        char_pos = text.find(w_text, prev_char)
                        if char_pos == -1:
                            char_pos = prev_char
                        char_end = char_pos + len(w_text)
                        words.append(
                            AsrWord(
                                start_char=char_pos,
                                end_char=char_end,
                                start_ms=w_start,
                                end_ms=w_end,
                                confidence=float(getattr(w, "probability", 0.9)),
                                timing_source="asr_reported",
                            )
                        )
                        prev_char = char_end
                        prev_word_end = w_end
                segments.append(
                    AsrSegment(
                        start_ms=start_ms,
                        end_ms=end_ms,
                        text=text,
                        display_text=text,
                        words=tuple(words),
                    )
                )
                previous_end = end_ms
            if not segments:
                raise ConversionError("faster-whisper produced no speech segments")
            return AsrTranscript(
                language=detected_lang,
                segments=tuple(segments),
                provider_id="faster-whisper",
                provider_version="1.0.0",
                model_id=str(self.model_size_or_path),
                model_version="ctranslate2",
                config_sha256=self.config_sha256,
            )
        except ConversionError:
            raise
        except Exception as error:
            raise ConversionError(f"faster-whisper transcription failed: {error}") from error


class OpenAiAudioAsrAdapter:
    """Cloud / Remote ASR adapter using OpenAI Audio Transcriptions API."""

    def __init__(
        self,
        *,
        base_url: str = "https://api.openai.com/v1",
        api_key: str | None = None,
        model: str = "whisper-1",
        language: str = "auto",
        timeout_seconds: float = 300.0,
        client: Any = None,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.api_key = api_key or os.environ.get("OPENAI_API_KEY")
        self.model = model
        self.language = language
        self.timeout_seconds = timeout_seconds
        self._client = client
        self.config_sha256 = f"sha256:{hashlib.sha256(json.dumps({"schema": "listen_gen.openai-audio-config.v1", "base_url": self.base_url, "model": self.model}, sort_keys=True).encode()).hexdigest()}"

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        if self._client is not None:
            raw = self._client(media_path)
        else:
            if not self.api_key:
                raise ConversionError("OpenAI API key is required for cloud ASR transcription")
            import urllib.request
            import uuid

            boundary = f"----WebKitFormBoundary{uuid.uuid4().hex}"
            body = bytearray()

            def add_field(name: str, value: str):
                body.extend(f"--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n".encode())

            def add_file(name: str, filename: str, data: bytes, content_type: str):
                body.extend(f"--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\r\nContent-Type: {content_type}\r\n\r\n".encode())
                body.extend(data)
                body.extend(b"\r\n")

            add_field("model", self.model)
            add_field("response_format", "verbose_json")
            add_field("timestamp_granularities[]", "word")
            add_field("timestamp_granularities[]", "segment")
            if self.language != "auto":
                add_field("language", self.language)
            add_file("file", media_path.name, media_path.read_bytes(), "audio/wav")
            body.extend(f"--{boundary}--\r\n".encode())

            req = urllib.request.Request(
                f"{self.base_url}/audio/transcriptions",
                data=bytes(body),
                headers={
                    "Authorization": f"Bearer {self.api_key}",
                    "Content-Type": f"multipart/form-data; boundary={boundary}",
                },
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=self.timeout_seconds) as resp:
                    raw = json.loads(resp.read().decode("utf-8"))
            except Exception as e:
                raise ConversionError(f"OpenAI audio transcription request failed: {e}") from e

        # Parse verbose_json format from OpenAI API
        language = raw.get("language", "en") if self.language == "auto" else self.language
        if not LANGUAGE_RE.fullmatch(language):
            language = "en"
        raw_segments = raw.get("segments") or []
        segments: list[AsrSegment] = []
        previous_end = 0
        for seg in raw_segments:
            start_ms = int(seg.get("start", 0) * 1000)
            end_ms = max(start_ms + 1, int(seg.get("end", 0) * 1000))
            if start_ms < previous_end:
                start_ms = previous_end
            if end_ms <= start_ms:
                end_ms = start_ms + 1
            text = str(seg.get("text", "")).strip()
            if not text:
                continue
            words: list[AsrWord] = []
            for w in seg.get("words", []):
                w_text = str(w.get("word", "")).strip()
                if not w_text:
                    continue
                w_start = max(start_ms, int(w.get("start", 0) * 1000))
                w_end = min(end_ms, max(w_start + 1, int(w.get("end", 0) * 1000)))
                words.append(
                    AsrWord(
                        start_char=0,
                        end_char=len(w_text),
                        start_ms=w_start,
                        end_ms=w_end,
                        confidence=0.9,
                        timing_source="asr_reported",
                    )
                )
            segments.append(
                AsrSegment(
                    start_ms=start_ms,
                    end_ms=end_ms,
                    text=text,
                    display_text=text,
                    words=tuple(words),
                )
            )
            previous_end = end_ms

        if not segments:
            raise ConversionError("OpenAI audio transcription returned no segments")

        return AsrTranscript(
            language=language,
            segments=tuple(segments),
            provider_id="openai-audio",
            provider_version="1.0.0",
            model_id=self.model,
            model_version=None,
            config_sha256=self.config_sha256,
        )
