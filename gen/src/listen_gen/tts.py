"""Provider-neutral TTS and the derived audio rendition path.

A TTS adapter synthesizes speech audio from the exact extracted text and
reports an exact media type. Anchored reading requires a separate
anchor-to-time alignment: adapters that cannot produce exact timing return
``alignment=None`` and synchronized reading stays honestly unavailable —
timing is never fabricated.

Adapters:
- :class:`SayTtsAdapter`: the locally executable macOS ``say``/``afconvert``
  path used by the supported smoke test. No paid or live credential service.
- :class:`FakeTtsAdapter`: deterministic in-process WAV synthesis with exact
  anchor timing for tests.
- :class:`FixtureTtsAdapter`: replays committed audio bytes (and an optional
  committed alignment document).
"""

from __future__ import annotations

import json
import math
import struct
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, Sequence

from .package import ConversionError
from .process import ProcessResult, ProcessTimedOut, ProcessOutputTooLarge, run_argv


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


class SayTtsAdapter:
    """Synthesize speech with the locally executable macOS ``say`` tool.

    ``say`` writes AIFF; ``afconvert`` converts it to AAC/m4a. Both are
    shipped with macOS and require no credentials. Exact anchor timing cannot
    be derived from ``say`` output, so alignment is honestly absent.
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

    def synthesize(
        self,
        text: str,
        sentence_anchors: Sequence[tuple[str, str]],
    ) -> TtsResult:
        with tempfile.TemporaryDirectory(prefix="listen-gen-tts-") as directory:
            directory_path = Path(directory)
            input_path = directory_path / "speech.txt"
            input_path.write_text(text, encoding="utf-8")
            aiff_path = directory_path / "speech.aiff"
            m4a_path = directory_path / "speech.m4a"
            self._run_say(input_path, aiff_path)
            self._run_afconvert(aiff_path, m4a_path)
            audio = m4a_path.read_bytes()
        if not audio:
            raise TtsProviderOutputInvalid("the TTS provider produced no audio")
        return TtsResult(
            audio_bytes=audio,
            media_type="audio/mp4",
            alignment=None,
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

    def _run_afconvert(self, input_path: Path, output_path: Path) -> None:
        argv = [
            self.afconvert_executable,
            str(input_path),
            "-f",
            "m4af",
            "-d",
            "aac",
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
        )
