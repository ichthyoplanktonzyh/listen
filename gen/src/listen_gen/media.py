from __future__ import annotations

import json
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, ContextManager, Iterator, Protocol

from .package import ConversionError
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv

PROBE_STDOUT_LIMIT_BYTES = 1024 * 1024


@dataclass(frozen=True)
class AudioStream:
    """An audio stream addressable by its input-container stream index."""

    index: int


@dataclass(frozen=True)
class PreparedAudio:
    path: Path
    stream_index: int


class AudioPreprocessor(Protocol):
    """Provider-neutral seam that supplies normalized audio for model input."""

    def prepare(
        self, media_path: Path, *, audio_stream_index: int | None
    ) -> ContextManager[PreparedAudio]: ...


class FfmpegAudioPreprocessor:
    """Probe media and produce temporary 16 kHz mono signed-16-bit PCM WAV."""

    def __init__(
        self,
        *,
        ffprobe_executable: str = "ffprobe",
        ffmpeg_executable: str = "ffmpeg",
        timeout_seconds: float = 300.0,
    ):
        if not ffprobe_executable or not ffmpeg_executable:
            raise ConversionError("media tool executables must be non-empty")
        if timeout_seconds <= 0:
            raise ConversionError("media command timeout must be positive")
        self.ffprobe_executable = ffprobe_executable
        self.ffmpeg_executable = ffmpeg_executable
        self.timeout_seconds = timeout_seconds

    def _run_probe(self, media_path: Path) -> tuple[AudioStream, ...]:
        try:
            completed = run_argv(
                [
                    self.ffprobe_executable,
                    "-v",
                    "error",
                    "-show_entries",
                    "stream=index,codec_type",
                    "-of",
                    "json",
                    str(media_path),
                ],
                timeout_seconds=self.timeout_seconds,
                stdout_limit_bytes=PROBE_STDOUT_LIMIT_BYTES,
            )
        except ProcessTimedOut as error:
            raise ConversionError("media probe timed out") from error
        except ProcessOutputTooLarge as error:
            raise ConversionError("media probe output exceeded the safety limit") from error
        except OSError as error:
            raise ConversionError("media probe could not be started") from error
        if completed.returncode != 0:
            raise ConversionError(
                f"media probe failed with exit status {completed.returncode}"
            )
        try:
            document: Any = json.loads(completed.stdout)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ConversionError("media probe returned invalid JSON") from error
        if not isinstance(document, dict) or not isinstance(document.get("streams"), list):
            raise ConversionError("media probe returned an invalid stream list")
        streams: list[AudioStream] = []
        seen: set[int] = set()
        for stream in document["streams"]:
            if not isinstance(stream, dict) or stream.get("codec_type") != "audio":
                continue
            index = stream.get("index")
            if not isinstance(index, int) or isinstance(index, bool) or index < 0 or index in seen:
                raise ConversionError("media probe returned an invalid audio stream index")
            streams.append(AudioStream(index))
            seen.add(index)
        if not streams:
            raise ConversionError("media contains no audio stream")
        return tuple(streams)

    @staticmethod
    def _select_stream(
        streams: tuple[AudioStream, ...], requested_index: int | None
    ) -> AudioStream:
        if requested_index is None:
            if len(streams) != 1:
                raise ConversionError(
                    "media contains multiple audio streams; --audio-stream-index is required"
                )
            return streams[0]
        if not isinstance(requested_index, int) or isinstance(requested_index, bool):
            raise ConversionError("audio stream index must be an integer")
        if requested_index < 0:
            raise ConversionError("audio stream index must be non-negative")
        matches = [stream for stream in streams if stream.index == requested_index]
        if not matches:
            raise ConversionError("selected audio stream index does not exist")
        return matches[0]

    @contextmanager
    def prepare(
        self, media_path: Path, *, audio_stream_index: int | None
    ) -> Iterator[PreparedAudio]:
        if not media_path.is_file():
            raise ConversionError("media input is not a regular file")
        stream = self._select_stream(self._run_probe(media_path), audio_stream_index)
        with tempfile.TemporaryDirectory(prefix="listen-gen-audio-") as directory:
            output_path = Path(directory) / "normalized.wav"
            try:
                completed = run_argv(
                    [
                        self.ffmpeg_executable,
                        "-v",
                        "error",
                        "-nostdin",
                        "-i",
                        str(media_path),
                        "-map",
                        f"0:{stream.index}",
                        "-vn",
                        "-ac",
                        "1",
                        "-ar",
                        "16000",
                        "-c:a",
                        "pcm_s16le",
                        "-f",
                        "wav",
                        "-y",
                        str(output_path),
                    ],
                    timeout_seconds=self.timeout_seconds,
                    stdout_limit_bytes=None,
                )
            except ProcessTimedOut as error:
                raise ConversionError("audio preprocessing timed out") from error
            except OSError as error:
                raise ConversionError("audio preprocessing could not be started") from error
            if completed.returncode != 0:
                raise ConversionError(
                    f"audio preprocessing failed with exit status {completed.returncode}"
                )
            if not output_path.is_file():
                raise ConversionError("audio preprocessing produced no usable output")
            yield PreparedAudio(output_path, stream.index)
