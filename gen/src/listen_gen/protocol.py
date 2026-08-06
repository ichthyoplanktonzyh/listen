from __future__ import annotations

import json
import sys
from typing import Any, TextIO

from . import __version__ as TOOL_VERSION
from .package import PACKAGE_SCHEMA, ConversionError

MACHINE_EVENT_SCHEMA = "listen_gen.machine-event.v1"
MACHINE_PROTOCOL_VERSION = 1
TOOL_ID = "listen-gen"

EVENT_TYPES = ("protocol", "started", "phase", "completed", "failed", "cancelled")
PHASE_NAMES = (
    "validating",
    "probing_media",
    "normalizing_audio",
    "transcribing",
    "building_package",
)
TERMINAL_EVENTS = frozenset({"completed", "failed", "cancelled"})

MACHINE_ERROR_MESSAGES: dict[str, str] = {
    "invalid_arguments": "Generation arguments are invalid.",
    "input_not_found": "Input media is unavailable.",
    "input_changed": "Input media changed during generation.",
    "media_probe_failed": "The media audio streams could not be inspected.",
    "audio_stream_required": "An audio stream must be selected.",
    "audio_stream_not_found": "The selected audio stream is unavailable.",
    "audio_normalization_failed": "The media audio could not be prepared.",
    "provider_start_failed": "The transcription provider could not be started.",
    "provider_timeout": "The transcription provider timed out.",
    "provider_failed": "The transcription provider failed.",
    "provider_output_invalid": "The transcription provider returned an invalid result.",
    "package_validation_failed": "Generated resources did not pass package validation.",
    "package_write_failed": "The learning package could not be written.",
    "internal_error": "Generation failed because of an internal error.",
}


def protocol_capabilities() -> dict[str, object]:
    return {
        "package_schema": PACKAGE_SCHEMA,
        "machine_protocol_version": MACHINE_PROTOCOL_VERSION,
        "events": list(EVENT_TYPES),
        "phases": list(PHASE_NAMES),
    }


class MachineEventEmitter:
    """Emit the listen-gen machine protocol as strict NDJSON on stdout."""

    def __init__(self, stream: TextIO | None = None) -> None:
        self.sequence = 0
        self.terminal_emitted = False
        self.terminal_event: str | None = None
        self._stream = sys.stdout if stream is None else stream
        self._protocol_emitted = False
        self._started_emitted = False

    def protocol(self, capabilities: dict[str, object]) -> None:
        self._emit("protocol", capabilities=capabilities)

    def started(self) -> None:
        self._emit("started")

    def phase(self, phase: str) -> None:
        self._emit("phase", phase=phase)

    def completed(
        self,
        *,
        package_sha256: str,
        media_fingerprint: str,
        resources: list[dict[str, object]],
        warnings: list[str],
    ) -> None:
        self._emit(
            "completed",
            package_sha256=package_sha256,
            media_fingerprint=media_fingerprint,
            resources=resources,
            warnings=warnings,
        )

    def failed(self, *, code: str, message: str) -> None:
        self._emit("failed", code=code, message=message)

    def cancelled(self) -> None:
        self._emit("cancelled")

    def _emit(self, event: str, **payload: Any) -> None:
        if self.terminal_emitted:
            raise RuntimeError(
                "machine event emitter cannot emit after a terminal event"
            )
        if event == "protocol":
            if self.sequence != 0 or self._protocol_emitted:
                raise RuntimeError("protocol must be the first and only emitted event")
            self._protocol_emitted = True
        elif event == "started":
            if not self._protocol_emitted:
                raise RuntimeError("started must follow the protocol event")
            if self._started_emitted:
                raise RuntimeError("started may only be emitted once")
            self._started_emitted = True
        elif event == "phase":
            if not self._started_emitted:
                raise RuntimeError("phase must follow the started event")
            if phase := payload.get("phase"):
                if phase not in PHASE_NAMES:
                    raise RuntimeError(f"unknown machine phase: {phase!r}")
        elif event in TERMINAL_EVENTS:
            if not self._started_emitted:
                raise RuntimeError("terminal events must follow the started event")
        else:
            raise RuntimeError(f"unknown machine event: {event!r}")
        document: dict[str, object] = {
            "schema": MACHINE_EVENT_SCHEMA,
            "protocol_version": MACHINE_PROTOCOL_VERSION,
            "sequence": self.sequence,
            "tool": {"id": TOOL_ID, "version": TOOL_VERSION},
            "event": event,
            **payload,
        }
        self.sequence += 1
        if event in TERMINAL_EVENTS:
            self.terminal_emitted = True
            self.terminal_event = event
        line = json.dumps(
            document, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        )
        self._stream.write(line + "\n")
        self._stream.flush()


def machine_error(error: BaseException) -> tuple[str, str]:
    """Map a pipeline exception to a stable machine-protocol error."""
    code = _classify_error(error)
    return code, MACHINE_ERROR_MESSAGES[code]


def _classify_error(error: BaseException) -> str:
    if isinstance(error, (json.JSONDecodeError, UnicodeDecodeError)):
        return "provider_output_invalid"
    if isinstance(error, FileNotFoundError):
        return "input_not_found"
    message = str(error).lower()
    if "media input is not a regular file" in message:
        return "input_not_found"
    if "changed during" in message:
        return "input_changed"
    if "audio stream" in message:
        if "multiple audio streams" in message or "must be selected" in message:
            return "audio_stream_required"
        if "does not exist" in message or "no audio stream" in message:
            return "audio_stream_not_found"
        if "must be an integer" in message or "must be non-negative" in message:
            return "invalid_arguments"
    if "probe" in message:
        return "media_probe_failed"
    if "preprocess" in message:
        return "audio_normalization_failed"
    if "timed out" in message:
        return "provider_timeout"
    if "could not be started" in message:
        return "provider_start_failed"
    if "returned invalid" in message or "invalid normalized json" in message:
        return "provider_output_invalid"
    if "asr command" in message and "failed with exit status" in message:
        return "provider_failed"
    if "exceeded the safety limit" in message:
        return "provider_output_invalid"
    if message.startswith("/") or "asr segment" in message:
        return "provider_output_invalid"
    argument_hints = (
        "is required for the",
        "must be non-empty",
        "must be positive",
        "{media}",
        "duration_ms",
        "created_at_ms",
        "title must",
        "media kind must",
    )
    if any(hint in message for hint in argument_hints):
        return "invalid_arguments"
    if isinstance(error, OSError):
        # Missing inputs surface as ConversionError ("media input is not a
        # regular file") before any read, so an escaped OSError is most
        # plausibly a filesystem failure while writing the package.
        return "package_write_failed"
    if isinstance(error, ConversionError):
        return "package_validation_failed"
    return "internal_error"
