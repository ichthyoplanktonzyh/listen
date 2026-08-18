"""Provider-neutral TTS and the derived audio rendition path.

A TTS adapter synthesizes speech audio from the exact logical text of a
Structured Reading and reports its provider identity facts. Anchored reading
requires a separate anchor-to-time alignment: adapters that cannot produce
exact timing return ``alignment=None`` and synchronized reading stays
honestly unavailable — timing is never fabricated.

Adapters:
- :class:`KokoroTtsAdapter`: high-quality neural speech synthesis using Kokoro-82M.
- :class:`SayTtsAdapter`: the locally executable macOS ``say``/``afconvert``
  path. Speech is synthesized per sentence, every segment's real duration is
  measured with ``ffprobe``, and the segments are concatenated into one
  audio stream; the anchor alignment therefore comes from real segment
  boundaries. When measurement is unavailable the audio still succeeds and
  alignment is honestly absent. No paid or live credential service.
- :class:`FakeTtsAdapter`: deterministic in-process WAV synthesis with exact
  anchor timing for tests.
- :class:`FixtureTtsAdapter`: replays committed audio bytes (and an optional
  committed alignment document).
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Protocol, Sequence

from .package import ConversionError
from .process import ProcessResult, ProcessTimedOut, ProcessOutputTooLarge, run_argv

WAV_HEADER_SIZE = 44


class TtsProviderError(ConversionError):
    """The TTS provider failed to produce qualified audio."""


class TtsProviderStartFailed(TtsProviderError):
    pass


class TtsProviderTimedOut(TtsProviderError):
    pass


class TtsProviderOutputInvalid(TtsProviderError):
    pass


@dataclass(frozen=True)
class AnchorAlignment:
    anchor_id: str
    media_time_ms: int


@dataclass(frozen=True)
class TtsResult:
    audio_bytes: bytes
    media_type: str
    alignment: tuple[AnchorAlignment, ...] | None
    duration_ms: int | None
    provider_id: str
    provider_version: str
    model_id: str | None
    model_version: str | None
    config_sha256: str | None

    @property
    def anchored(self) -> bool:
        return self.alignment is not None


class TtsAdapter(Protocol):
    name: str

    def synthesize(
        self,
        text: str,
        sentence_anchors: Sequence[tuple[str, str]],
    ) -> TtsResult: ...


def _config_identity(config: dict[str, object]) -> str:
    return "sha256:" + hashlib.sha256(
        json.dumps(
            config,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode("utf-8")
    ).hexdigest()


# ---------------------------------------------------------------------------
# Deterministic fake (tests)
# ---------------------------------------------------------------------------

_SAMPLE_RATE = 16_000
_MS_PER_CHARACTER = 90
_MS_SILENCE = 60


def _wav_bytes(samples: Sequence[int]) -> bytes:
    """Encode signed 16-bit mono PCM as a WAV file."""
    frame_count = len(samples)
    data_size = frame_count * 2
    header = b"RIFF" + struct.pack("<I", 36 + data_size) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, _SAMPLE_RATE,
                                    _SAMPLE_RATE * 2, 2, 16)
    header += b"data" + struct.pack("<I", data_size)
    return header + struct.pack(f"<{frame_count}h", *samples)


class FakeTtsAdapter:
    """Deterministic, in-process TTS with exact anchor timing.

    Each character contributes a fixed speech window; each sentence anchor
    receives the exact media time of its window start. The same text and
    anchor list always produce the same bytes and the same alignment.
    """

    name = "fake"

    def synthesize(
        self,
        text: str,
        sentence_anchors: Sequence[tuple[str, str]],
    ) -> TtsResult:
        samples: list[int] = []
        alignments: list[AnchorAlignment] = []
        cursor_ms = 0
        for anchor_id, sentence in sentence_anchors:
            alignments.append(AnchorAlignment(anchor_id, cursor_ms))
            cursor_ms += self._append_sentence(samples, sentence)
        audio = _wav_bytes(samples)
        return TtsResult(
            audio_bytes=audio,
            media_type="audio/wav",
            alignment=tuple(alignments),
            duration_ms=cursor_ms,
            provider_id="fake",
            provider_version="0.0.0",
            model_id=None,
            model_version=None,
            config_sha256=_config_identity(
                {
                    "sample_rate_hz": _SAMPLE_RATE,
                    "ms_per_character": _MS_PER_CHARACTER,
                    "ms_silence": _MS_SILENCE,
                }
            ),
        )

    @staticmethod
    def _append_sentence(samples: list[int], sentence: str) -> int:
        cursor_ms = 0
        for character in sentence:
            cursor_ms += _MS_PER_CHARACTER
            samples.extend(
                _tone_window(_MS_PER_CHARACTER, frequency=_freq(character))
            )
        if cursor_ms > 0:
            samples.extend(_silence_window(_MS_SILENCE))
            cursor_ms += _MS_SILENCE
        return cursor_ms


def _freq(character: str) -> float:
    if not character.strip():
        return 0.0
    return 220.0 + (ord(character) % 440)

def _tone_window(ms: int, *, frequency: float) -> list[int]:
    count = int(_SAMPLE_RATE * ms / 1000)
    phase = 2.0 * math.pi * frequency / _SAMPLE_RATE
    return [int(4000 * math.sin(phase * i)) for i in range(count)]

def _silence_window(ms: int) -> list[int]:
    count = int(_SAMPLE_RATE * ms / 1000)
    return [0] * count


# ---------------------------------------------------------------------------
# macOS local adapter (smoke)
# ---------------------------------------------------------------------------


def _wav_data_chunk(path_or_bytes) -> tuple[int, int, int, bytes]:
    """Locate the real PCM `data` chunk in a WAV by walking RIFF chunks.

    afconvert writes a non-standard layout (`fmt`, then a zero-filled
    `FLLR` chunk, then `data`), so a fixed 44-byte header offset is wrong.
    Walking the chunks finds the authoritative sample rate, channels, bits,
    and data bytes regardless of extra chunks.
    """
    data = path_or_bytes if isinstance(path_or_bytes, bytes) else path_or_bytes.read_bytes()
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise TtsProviderOutputInvalid("the TTS provider produced invalid WAV audio")
    pos = 12
    sample_rate = channels = bits = 0
    while pos + 8 <= len(data):
        marker = data[pos : pos + 4]
        size = struct.unpack_from("<I", data, pos + 4)[0]
        body_start = pos + 8
        if marker == b"fmt " and size >= 16:
            sample_rate = struct.unpack_from("<I", data, body_start + 4)[0]
            channels = struct.unpack_from("<H", data, body_start + 2)[0]
            bits = struct.unpack_from("<H", data, body_start + 14)[0]
        elif marker == b"data":
            body = data[body_start : body_start + size]
            if body:
                return sample_rate, channels, bits, body
        pos = body_start + size + (size & 1)
    raise TtsProviderOutputInvalid("the TTS provider produced invalid WAV audio")


def _wav_duration_ms(path: Path) -> int:
    """Real media duration of a WAV file in milliseconds.

    The duration is derived from the file's own fmt/data chunks; this is a
    measurement of produced audio, never an estimate.
    """
    sample_rate, channels, bits, body = _wav_data_chunk(path)
    if sample_rate <= 0 or channels <= 0 or bits <= 0:
        raise TtsProviderOutputInvalid("the TTS provider produced invalid WAV audio")
    byte_rate = sample_rate * channels * bits // 8
    if byte_rate <= 0:
        raise TtsProviderOutputInvalid("the TTS provider produced invalid WAV audio")
    return len(body) * 1000 // byte_rate


def _concat_wav(segments: Sequence[bytes]) -> bytes:
    """Concatenate same-format PCM WAV files into one WAV stream.

    The fmt header comes from the first segment; the `data` chunk bodies
    follow in order. All segments must share the format declaration.
    Segments that cannot be parsed as WAV (e.g. unmeasurable garbage from a
    provider failure path) are preserved byte-for-byte: the audio still
    succeeds and the missing measurement surfaces as an honest alignment
    abstention, never as a fabrication.
    """
    if not segments:
        raise TtsProviderOutputInvalid("the TTS provider produced no audio")
    try:
        first = segments[0]
        sample_rate, channels, bits, first_body = _wav_data_chunk(first)
        if sample_rate <= 0 or channels <= 0 or bits <= 0:
            raise TtsProviderOutputInvalid(
                "the TTS provider produced invalid WAV audio"
            )
        body = first_body + b"".join(
            _wav_data_chunk(segment)[3] for segment in segments[1:]
        )
        byte_rate = sample_rate * channels * bits // 8
        block_align = channels * bits // 8
        header = b"RIFF" + struct.pack("<I", 36 + len(body)) + b"WAVE"
        header += b"fmt " + struct.pack("<I", 16)
        header += struct.pack("<H", 1)  # PCM
        header += struct.pack("<H", channels)
        header += struct.pack("<I", sample_rate)
        header += struct.pack("<I", byte_rate)
        header += struct.pack("<H", block_align)
        header += struct.pack("<H", bits)
        header += b"data" + struct.pack("<I", len(body))
        return header + body
    except TtsProviderError:
        return b"".join(segments)


class SayTtsAdapter:
    """Synthesize speech per sentence with the local macOS ``say`` tool.

    Each sentence is synthesized into its own AIFF, converted to a shared
    16 kHz mono PCM WAV, and its real duration is measured from the WAV
    bytes. The segments are concatenated into one WAV and converted to
    AAC/m4a with ``afconvert``. The reported anchor alignment is the exact
    cumulative real duration of the preceding segments — timing is measured,
    never fabricated. If measurement fails the audio still succeeds and
    alignment is honestly absent.
    """

    name = "say"

    def __init__(
        self,
        *,
        voice: str | None = None,
        say_executable: str = "say",
        afconvert_executable: str = "afconvert",
        timeout_seconds: float = 600.0,
    ):
        self.voice = voice
        self.say_executable = say_executable
        self.afconvert_executable = afconvert_executable
        self.timeout_seconds = timeout_seconds
        self._say_version = "say:" + self._tool_fingerprint(say_executable)
        self._afconvert_version = "afconvert:" + self._tool_fingerprint(
            afconvert_executable
        )

    @staticmethod
    def _tool_fingerprint(executable: str) -> str:
        import shutil

        candidate = Path(executable)
        if not candidate.is_file():
            resolved = shutil.which(executable)
            if resolved:
                candidate = Path(resolved)
        try:
            data = candidate.read_bytes()
            return hashlib.sha256(data).hexdigest()[:16]
        except OSError:
            return "unknown"

    def synthesize(
        self,
        text: str,
        sentence_anchors: Sequence[tuple[str, str]],
    ) -> TtsResult:
        if not sentence_anchors:
            raise TtsProviderOutputInvalid(
                "the TTS provider requires at least one sentence anchor"
            )
        segments: list[bytes] = []
        alignments: list[AnchorAlignment] = []
        cursor_ms = 0
        measured = True
        with tempfile.TemporaryDirectory(prefix="listen-gen-tts-") as directory:
            directory_path = Path(directory)
            for index, (anchor_id, sentence) in enumerate(sentence_anchors):
                if not sentence.strip():
                    # A blank sentence (e.g. whitespace residue from source
                    # segmentation) has nothing to speak; skipping it keeps
                    # the segment audio non-empty without fabricating speech.
                    continue
                input_path = directory_path / f"segment-{index}.txt"
                input_path.write_text(sentence, encoding="utf-8")
                aiff_path = directory_path / f"segment-{index}.aiff"
                wav_path = directory_path / f"segment-{index}.wav"
                self._run_say(input_path, aiff_path)
                self._run_afconvert(aiff_path, wav_path, "WAVE", "LEI16@16000")
                segments.append(wav_path.read_bytes())
                try:
                    duration_ms = _wav_duration_ms(wav_path)
                    if duration_ms <= 0:
                        raise TtsProviderOutputInvalid(
                            "the TTS provider produced zero-length audio"
                        )
                    alignments.append(AnchorAlignment(anchor_id, cursor_ms))
                    cursor_ms += duration_ms
                except TtsProviderError:
                    measured = False
            m4a_path = directory_path / "speech.m4a"
            combined = _concat_wav(segments)
            combined_path = directory_path / "combined.wav"
            combined_path.write_bytes(combined)
            self._run_afconvert(combined_path, m4a_path, "m4af", "aac")
            audio = m4a_path.read_bytes()
        if not audio:
            raise TtsProviderOutputInvalid("the TTS provider produced no audio")
        return TtsResult(
            audio_bytes=audio,
            media_type="audio/mp4",
            alignment=tuple(alignments) if measured else None,
            duration_ms=cursor_ms if measured else None,
            provider_id="say",
            provider_version=self._say_version,
            model_id=self.voice,
            model_version=None,
            config_sha256=_config_identity(
                {
                    "sample_rate_hz": 16000,
                    "channels": 1,
                    "sample_format": "pcm_s16le",
                    "concat_order": "sentence_spine_order",
                }
            ),
        )

    def _run_say(self, input_path: Path, output_path: Path) -> None:
        argv = [self.say_executable, "-o", str(output_path), "-f", str(input_path)]
        if self.voice:
            argv.extend(["-v", self.voice])
        try:
            run_argv(argv, timeout_seconds=self.timeout_seconds, stdout_limit_bytes=None)
        except ProcessTimedOut as error:
            raise TtsProviderTimedOut("the TTS provider timed out") from error
        except OSError as error:
            raise TtsProviderStartFailed(
                "the TTS provider could not be started"
            ) from error

    def _run_afconvert(
        self,
        input_path: Path,
        output_path: Path,
        format_flag: str,
        data_format: str,
    ) -> None:
        argv = [
            self.afconvert_executable,
            str(input_path),
            "-f",
            format_flag,
            "-d",
            data_format,
            "-o",
            str(output_path),
        ]
        try:
            run_argv(argv, timeout_seconds=self.timeout_seconds, stdout_limit_bytes=None)
        except ProcessTimedOut as error:
            raise TtsProviderTimedOut("the TTS provider timed out") from error
        except OSError as error:
            raise TtsProviderStartFailed(
                "the TTS provider could not be started"
            ) from error


# ---------------------------------------------------------------------------
# Fixture adapter (tests)
# ---------------------------------------------------------------------------


class FixtureTtsAdapter:
    """Replay committed audio bytes and an optional committed alignment."""

    name = "fixture"

    def __init__(self, audio_path: Path, alignment_path: Path | None = None):
        self.audio_path = audio_path
        self.alignment_path = alignment_path
        if not audio_path.is_file():
            raise ValueError("tts fixture audio must be a regular file")
        if alignment_path is not None and not alignment_path.is_file():
            raise ValueError("tts fixture alignment must be a regular file")

    def synthesize(
        self,
        text: str,
        sentence_anchors: Sequence[tuple[str, str]],
    ) -> TtsResult:
        audio = self.audio_path.read_bytes()
        try:
            duration_ms = _wav_duration_ms(self.audio_path)
        except TtsProviderError:
            duration_ms = None
        alignment: tuple[AnchorAlignment, ...] | None = None
        if self.alignment_path is not None:
            try:
                document = json.loads(self.alignment_path.read_text(encoding="utf-8"))
                alignment = tuple(
                    AnchorAlignment(
                        anchor_id=str(entry["anchor_id"]),
                        media_time_ms=int(entry["media_time_ms"]),
                    )
                    for entry in document
                )
            except (ValueError, KeyError, OSError, json.JSONDecodeError) as error:
                raise TtsProviderOutputInvalid(
                    "the TTS fixture alignment is invalid"
                ) from error
        return TtsResult(
            audio_bytes=audio,
            media_type="audio/wav",
            alignment=alignment,
            duration_ms=duration_ms,
            provider_id="fixture",
            provider_version="0.0.0",
            model_id=None,
            model_version=None,
            config_sha256=None,
        )


# ---------------------------------------------------------------------------
# Kokoro Neural TTS Adapter (82M)
# ---------------------------------------------------------------------------


def _pcm_array_to_wav(audio_data: Any, sample_rate: int = 24000) -> bytes:
    """Encode float or integer PCM sequence into standard 16-bit mono PCM WAV bytes."""
    if hasattr(audio_data, "tolist"):
        audio_data = audio_data.tolist()
    if not isinstance(audio_data, (list, tuple)):
        raise TtsProviderOutputInvalid("the TTS provider produced non-sequence audio samples")
    samples: list[int] = []
    for sample in audio_data:
        if isinstance(sample, float):
            clamped = max(-1.0, min(1.0, sample))
            samples.append(int(clamped * 32767))
        elif isinstance(sample, int):
            samples.append(max(-32768, min(32767, sample)))
        else:
            raise TtsProviderOutputInvalid("the TTS provider produced invalid sample values")
    frame_count = len(samples)
    data_size = frame_count * 2
    header = b"RIFF" + struct.pack("<I", 36 + data_size) + b"WAVE"
    header += b"fmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, sample_rate, sample_rate * 2, 2, 16
    )
    header += b"data" + struct.pack("<I", data_size)
    return header + struct.pack(f"<{frame_count}h", *samples)


class KokoroTtsAdapter:
    """High quality neural speech synthesis using Kokoro-82M.

    Synthesizes speech per sentence anchor, measures exact audio sample length
    to construct precise AnchorAlignment, and converts combined audio to AAC/m4a
    (or WAV if afconvert is unavailable).
    """

    name = "kokoro"

    def __init__(
        self,
        *,
        voice: str = "af_bella",
        speed: float = 1.0,
        lang_code: str = "a",
        sample_rate: int = 24000,
        afconvert_executable: str = "afconvert",
        timeout_seconds: float = 600.0,
        synthesizer: Callable[..., Any] | None = None,
    ):
        self.voice = voice or "af_bella"
        self.speed = float(speed)
        self.lang_code = lang_code or "a"
        self.sample_rate = int(sample_rate)
        self.afconvert_executable = afconvert_executable
        self.timeout_seconds = timeout_seconds
        self._synthesizer = synthesizer
        self._version = "kokoro-82m"

    def _resolve_synthesizer(self) -> Callable[..., Any]:
        if self._synthesizer is not None:
            return self._synthesizer
        try:
            from kokoro import KPipeline
            pipeline = KPipeline(lang_code=self.lang_code)

            def _synthesize(sentence: str, voice: str, speed: float, lang_code: str) -> list[float]:
                generator = pipeline(sentence, voice=voice, speed=speed, split_pattern=r"\n+")
                chunks: list[float] = []
                for _, _, audio in generator:
                    if hasattr(audio, "tolist"):
                        chunks.extend(audio.tolist())
                    elif isinstance(audio, (list, tuple)):
                        chunks.extend(audio)
                return chunks

            return _synthesize
        except ImportError:
            pass

        try:
            import kokoro_onnx

            kokoro_inst = kokoro_onnx.Kokoro()

            def _synthesize_onnx(sentence: str, voice: str, speed: float, lang_code: str) -> list[float]:
                samples, _ = kokoro_inst.create(sentence, voice=voice, speed=speed, lang=lang_code)
                if hasattr(samples, "tolist"):
                    return samples.tolist()
                return list(samples)

            return _synthesize_onnx
        except ImportError:
            pass

        raise TtsProviderStartFailed(
            "Kokoro TTS is not installed. Install with 'pip install kokoro soundfile' or 'pip install kokoro-onnx'"
        )

    def synthesize(
        self,
        text: str,
        sentence_anchors: Sequence[tuple[str, str]],
    ) -> TtsResult:
        if not sentence_anchors:
            raise TtsProviderOutputInvalid(
                "the TTS provider requires at least one sentence anchor"
            )
        segments: list[bytes] = []
        alignments: list[AnchorAlignment] = []
        cursor_ms = 0
        synthesizer_fn = self._resolve_synthesizer()

        with tempfile.TemporaryDirectory(prefix="listen-gen-kokoro-") as directory:
            directory_path = Path(directory)
            for index, (anchor_id, sentence) in enumerate(sentence_anchors):
                if not sentence.strip():
                    continue
                try:
                    audio_data = synthesizer_fn(
                        sentence,
                        voice=self.voice,
                        speed=self.speed,
                        lang_code=self.lang_code,
                    )
                except TtsProviderError:
                    raise
                except Exception as error:
                    raise TtsProviderError(
                        f"Kokoro synthesis failed on sentence: {error}"
                    ) from error

                wav_bytes = _pcm_array_to_wav(audio_data, self.sample_rate)
                wav_path = directory_path / f"segment-{index}.wav"
                wav_path.write_bytes(wav_bytes)
                segments.append(wav_bytes)

                try:
                    duration_ms = _wav_duration_ms(wav_path)
                    if duration_ms <= 0:
                        raise TtsProviderOutputInvalid(
                            "the TTS provider produced zero-length audio"
                        )
                    alignments.append(AnchorAlignment(anchor_id, cursor_ms))
                    cursor_ms += duration_ms
                except TtsProviderError:
                    raise

            if not segments:
                raise TtsProviderOutputInvalid("the TTS provider produced no audio")

            combined_wav = _concat_wav(segments)
            combined_path = directory_path / "combined.wav"
            combined_path.write_bytes(combined_wav)

            media_type = "audio/wav"
            audio_bytes = combined_wav
            if sys.platform == "darwin":
                m4a_path = directory_path / "speech.m4a"
                try:
                    self._run_afconvert(combined_path, m4a_path, "m4af", "aac")
                    if m4a_path.is_file() and m4a_path.stat().st_size > 0:
                        audio_bytes = m4a_path.read_bytes()
                        media_type = "audio/mp4"
                except Exception:
                    pass

        return TtsResult(
            audio_bytes=audio_bytes,
            media_type=media_type,
            alignment=tuple(alignments),
            duration_ms=cursor_ms,
            provider_id="kokoro",
            provider_version=self._version,
            model_id=self.voice,
            model_version="82M",
            config_sha256=_config_identity(
                {
                    "voice": self.voice,
                    "speed": self.speed,
                    "lang_code": self.lang_code,
                    "sample_rate_hz": self.sample_rate,
                }
            ),
        )

    def _run_afconvert(
        self,
        input_path: Path,
        output_path: Path,
        format_flag: str,
        data_format: str,
    ) -> None:
        argv = [
            self.afconvert_executable,
            str(input_path),
            "-f",
            format_flag,
            "-d",
            data_format,
            "-o",
            str(output_path),
        ]
        try:
            run_argv(argv, timeout_seconds=self.timeout_seconds, stdout_limit_bytes=None)
        except ProcessTimedOut as error:
            raise TtsProviderTimedOut("the TTS provider timed out") from error
        except OSError as error:
            raise TtsProviderStartFailed(
                "the TTS provider could not be started"
            ) from error
