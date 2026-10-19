from __future__ import annotations

import hashlib
import json
import os
import shutil
import tempfile
from pathlib import Path

from .asr import AsrSegment, AsrTranscript, AsrWord
from .package import LANGUAGE_RE, ConversionError
from .process import ProcessTimedOut, run_argv

WHISPER_CONFIG_SCHEMA = "listen_gen.whisper-cpp-config.v1"


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _integer_offset(value: object) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _word_timings_from_tokens(raw_tokens: object) -> tuple[AsrWord, ...]:
    """Aggregate whisper.cpp BPE tokens into exact word timings.

    ``-ojf`` output places per-token text, offsets, and probability inside each
    transcription segment. Tokens are model/BPE units, not guaranteed one per
    word: consecutive lexical tokens aggregate into one word timing whose
    character offsets cover the joined text. Special tokens (``<|``) are
    skipped; every retained token must carry a positive half-open range and
    advance the accumulated character offset exactly, so the emitted
    ``start_char``/``end_char`` agree with the deterministic tokenization of
    the segment text. Word timings are therefore exact ASR decoder facts, and
    never fabricated.
    """
    if not isinstance(raw_tokens, list):
        raise ConversionError("whisper.cpp provider returned an invalid result")
    words: list[AsrWord] = []
    char_cursor = 0
    first_token = True
    pending_text: list[str] = []
    pending_start: int | None = None
    pending_conf: list[float] = []
    pending_time_start: int | None = None
    pending_time_end: int | None = None

    def flush() -> None:
        nonlocal pending_text, pending_start, pending_conf
        nonlocal pending_time_start, pending_time_end
        if not pending_text or pending_start is None:
            return
        text = "".join(pending_text)
        end_char = pending_start + len(text)
        confidence = (
            round(sum(pending_conf) / len(pending_conf), 4)
            if pending_conf
            else None
        )
        words.append(
            AsrWord(
                start_char=pending_start,
                end_char=end_char,
                start_ms=pending_time_start or 0,
                end_ms=pending_time_end or 0,
                confidence=confidence,
                timing_source="asr_reported",
            )
        )
        pending_text, pending_start, pending_conf = [], None, []
        pending_time_start, pending_time_end = None, None

    for raw_token in raw_tokens:
        if not isinstance(raw_token, dict):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        text = raw_token.get("text")
        if not isinstance(text, str):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        if "<|" in text or (text.startswith("[_") and text.endswith("]")):
            continue
        offsets = raw_token.get("offsets")
        if not isinstance(offsets, dict):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        start_ms = offsets.get("from")
        end_ms = offsets.get("to")
        if not _integer_offset(start_ms) or not _integer_offset(end_ms):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        if end_ms <= start_ms:
            # A zero-length word boundary token (e.g. a split-on-word prefix
            # with no audio of its own) still carries text and advances the
            # character cursor; it contributes no timing of its own.
            leading = len(text) - len(text.lstrip(" "))
            stripped = text.lstrip(" ")
            if leading and pending_text:
                flush()
            pending_text.append(stripped)
            if not first_token:
                char_cursor += leading
            first_token = False
            if pending_start is None:
                pending_start = char_cursor
            char_cursor += len(stripped)
            continue
        probability = raw_token.get("p")
        confidence: float | None = None
        if isinstance(probability, (int, float)) and not isinstance(probability, bool):
            if not 0 <= probability <= 1:
                raise ConversionError("whisper.cpp provider returned an invalid result")
            confidence = float(probability)
        leading = len(text) - len(text.lstrip(" "))
        stripped = text.lstrip(" ")
        word_initial = bool(stripped) and (stripped[0].isalnum() or stripped[0] == "_")
        if leading and pending_text:
            flush()
        elif pending_text and not word_initial:
            # A punctuation token continues nothing: it is its own entry,
            # matching the deterministic word/punctuation tokenization.
            flush()
        pending_text.append(stripped)
        # The segment text is stripped; the first token's leading space does
        # not exist in the emitted sentence, so only inter-word spaces count.
        if not first_token:
            char_cursor += leading
        first_token = False
        if pending_start is None:
            pending_start = char_cursor
        if pending_time_start is None:
            pending_time_start = start_ms
        pending_time_end = end_ms
        if confidence is not None:
            pending_conf.append(confidence)
        char_cursor += len(stripped)
    flush()
    return tuple(words)


def _parse_whisper_result(
    raw: object,
    *,
    requested_language: str,
    translate_to_english: bool,
) -> tuple[str, tuple[AsrSegment, ...]]:
    """Parse the whisper.cpp standard JSON result with fixed validation rules."""

    if not isinstance(raw, dict):
        raise ConversionError("whisper.cpp provider returned an invalid result")
    transcription = raw.get("transcription")
    if not isinstance(transcription, list) or not transcription:
        raise ConversionError("whisper.cpp provider returned an invalid result")
    segments: list[AsrSegment] = []
    previous_to = 0
    for raw_segment in transcription:
        if not isinstance(raw_segment, dict):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        offsets = raw_segment.get("offsets")
        if not isinstance(offsets, dict):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        start_ms = offsets.get("from")
        end_ms = offsets.get("to")
        if not _integer_offset(start_ms) or not _integer_offset(end_ms):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        if end_ms <= start_ms or start_ms < previous_to:
            raise ConversionError("whisper.cpp provider returned an invalid result")
        text = raw_segment.get("text")
        if not isinstance(text, str):
            raise ConversionError("whisper.cpp provider returned an invalid result")
        trimmed_text = text.strip()
        if not trimmed_text:
            raise ConversionError("whisper.cpp provider returned an invalid result")
        raw_tokens = raw_segment.get("tokens")
        words = (
            _word_timings_from_tokens(raw_tokens)
            if raw_tokens is not None
            else ()
        )
        segments.append(
            AsrSegment(
                start_ms=start_ms,
                end_ms=end_ms,
                text=trimmed_text,
                display_text=trimmed_text,
                words=words,
            )
        )
        previous_to = end_ms
    if translate_to_english:
        language = "en"
    else:
        result = raw.get("result")
        detected = result.get("language") if isinstance(result, dict) else None
        if isinstance(detected, str) and detected.strip():
            language = detected.strip()
        elif requested_language == "auto":
            raise ConversionError("whisper.cpp provider returned an invalid result")
        else:
            language = requested_language
        if not LANGUAGE_RE.fullmatch(language):
            raise ConversionError("whisper.cpp provider returned an invalid result")
    return language, tuple(segments)


class WhisperCppAsrAdapter:
    """Transcribe a normalized WAV with a local whisper-cli binary.

    ``media_path`` is the temporary 16 kHz mono PCM WAV produced by
    :class:`PreprocessingAsrAdapter`; this adapter never sees the original
    media container.
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
            raise ConversionError("whisper.cpp executable must be non-empty")
        if model_path is None or not model_path.is_file():
            raise ConversionError("whisper.cpp model must be a regular file")
        if not isinstance(model_id, str) or not model_id.strip():
            raise ConversionError("whisper.cpp model id must be non-empty")
        if not isinstance(language, str) or not LANGUAGE_RE.fullmatch(language):
            raise ConversionError("whisper.cpp language must be a valid language tag")
        if timeout_seconds <= 0:
            raise ConversionError("whisper.cpp timeout must be positive")
        self.executable = executable
        self.model_path = model_path
        self.model_id = model_id.strip()
        self.language = language
        self.translate_to_english = translate_to_english
        self.timeout_seconds = timeout_seconds

    def _resolve_executable(self) -> str:
        candidate = Path(self.executable)
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
        resolved = shutil.which(self.executable)
        if resolved is None:
            raise ConversionError("whisper.cpp provider could not be started")
        return resolved

    def transcribe(self, media_path: Path) -> AsrTranscript:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        resolved = self._resolve_executable()
        try:
            runtime_sha256 = _sha256_file(Path(resolved))
        except OSError as error:
            raise ConversionError(
                "whisper.cpp provider could not be started"
            ) from error
        try:
            model_sha256 = _sha256_file(self.model_path)
        except OSError as error:
            raise ConversionError(
                "whisper.cpp model must be a regular file"
            ) from error
        with tempfile.TemporaryDirectory(prefix="listen-gen-whisper-") as directory:
            output_prefix = Path(directory) / "result"
            argv = [
                resolved,
                "-m",
                str(self.model_path),
                "-f",
                str(media_path),
                "-ojf",
                "-sow",
                "-wt", "0.01",
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
                raise ConversionError("whisper.cpp provider timed out") from error
            except OSError as error:
                raise ConversionError(
                    "whisper.cpp provider could not be started"
                ) from error
            if completed.returncode != 0:
                raise ConversionError(
                    f"whisper.cpp provider failed with exit status {completed.returncode}"
                )
            try:
                runtime_sha256_after = _sha256_file(Path(resolved))
                model_sha256_after = _sha256_file(self.model_path)
            except OSError as error:
                raise ConversionError(
                    "whisper.cpp provider runtime or model changed during transcription"
                ) from error
            if (
                runtime_sha256_after != runtime_sha256
                or model_sha256_after != model_sha256
            ):
                raise ConversionError(
                    "whisper.cpp provider runtime or model changed during transcription"
                )
            result_path = Path(f"{output_prefix}.json")
            if not result_path.is_file():
                raise ConversionError(
                    "whisper.cpp provider produced no JSON output"
                )
            try:
                result_bytes = result_path.read_bytes()
            except OSError as error:
                raise ConversionError(
                    "whisper.cpp provider returned an invalid result"
                ) from error
            try:
                raw = json.loads(result_bytes)
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise ConversionError(
                    "whisper.cpp provider returned invalid JSON"
                ) from error
            language, segments = _parse_whisper_result(
                raw,
                requested_language=self.language,
                translate_to_english=self.translate_to_english,
            )
        config_value = {
            "schema": WHISPER_CONFIG_SCHEMA,
            "provider_id": "whisper.cpp",
            "provider_version": f"sha256:{runtime_sha256}",
            "model_id": self.model_id,
            "model_version": f"sha256:{model_sha256}",
            "requested_language": self.language,
            "task": "translate_to_english" if self.translate_to_english else "transcribe",
            "output_format": "whisper.cpp-full-json",
            "word_timestamps": True,
            "word_threshold": 0.01,
            "split_on_word": True,
        }
        config_bytes = json.dumps(
            config_value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
        return AsrTranscript(
            language,
            segments,
            "whisper.cpp",
            f"sha256:{runtime_sha256}",
            self.model_id,
            f"sha256:{model_sha256}",
            f"sha256:{hashlib.sha256(config_bytes).hexdigest()}",
        )
