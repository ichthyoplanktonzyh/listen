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
    "aligning",
    "analyzing_sense_groups",
    "measuring_acoustics",
    "analyzing_prosody",
    "analyzing_phones",
    "building_package",
)
TERMINAL_EVENTS = frozenset({"completed", "failed", "cancelled"})

# The optional word-alignment stage degrades honestly: every failure below
# preserves the ASR Subtitle Text Track package and is reported as a stable
# typed warning code with a safe human message. Cancellation and media-change
# failures are never treated as degradation.
ALIGNMENT_WARNING_MESSAGES: dict[str, str] = {
    "alignment_start_failed": (
        "The word aligner could not be started; the subtitle package was preserved."
    ),
    "alignment_timeout": (
        "Word alignment timed out; the subtitle package was preserved."
    ),
    "alignment_failed": (
        "The word aligner failed; the subtitle package was preserved."
    ),
    "alignment_output_invalid": (
        "The word aligner returned an invalid result; the subtitle package was preserved."
    ),
    "alignment_output_too_large": (
        "The word aligner produced too much output; the subtitle package was preserved."
    ),
    "alignment_qualification_failed": (
        "Word alignment did not qualify; the subtitle package was preserved."
    ),
}


class AlignmentFailure(ConversionError):
    """A degradable alignment failure carrying a stable typed warning code.

    The human message is always the safe, stable message from
    :data:`ALIGNMENT_WARNING_MESSAGES`; internal details never leak into the
    package, machine events, or ordinary result.
    """

    def __init__(self, code: str):
        super().__init__(ALIGNMENT_WARNING_MESSAGES[code])
        self.code = code


def alignment_warning(error: BaseException) -> tuple[str, str]:
    """Map a degradable alignment error to a stable typed warning."""
    if isinstance(error, AlignmentFailure):
        return error.code, ALIGNMENT_WARNING_MESSAGES[error.code]
    message = str(error).lower()
    if "timed out" in message:
        return (
            "alignment_timeout",
            ALIGNMENT_WARNING_MESSAGES["alignment_timeout"],
        )
    if "safety limit" in message:
        return (
            "alignment_output_too_large",
            ALIGNMENT_WARNING_MESSAGES["alignment_output_too_large"],
        )
    if "could not be started" in message:
        return (
            "alignment_start_failed",
            ALIGNMENT_WARNING_MESSAGES["alignment_start_failed"],
        )
    return ("alignment_failed", ALIGNMENT_WARNING_MESSAGES["alignment_failed"])


# ---------------------------------------------------------------------------
# Rich resource stages (R4): sense groups, word acoustics, prosody
# ---------------------------------------------------------------------------

# The optional rich stages are provider-neutral over the same
# media -> machine events -> deterministic package interface as alignment.
# Every failure below preserves all already-qualified upstream resources and
# is reported as a stable typed warning code with a safe human message.
# Cancellation and media-change failures are never treated as degradation.
RICH_STAGE_TITLES: dict[str, str] = {
    "sense_groups": "Sense-group",
    "acoustics": "Acoustics",
    "prosody": "Prosody",
    "phone": "Phone",
}
RICH_WARNING_TAILS: dict[str, str] = {
    "start_failed": "provider could not be started",
    "timeout": "provider timed out",
    "failed": "provider failed",
    "output_invalid": "provider returned an invalid result",
    "output_too_large": "provider produced too much output",
    "qualification_failed": "result did not qualify",
    "upstream_missing": "required upstream resource was not produced",
}
RICH_WARNING_MESSAGES: dict[str, str] = {
    f"{stage}_{code}": (
        f"The {RICH_STAGE_TITLES[stage]} {tail}; "
        "already-qualified resources were preserved."
    )
    for stage in RICH_STAGE_TITLES
    for code, tail in RICH_WARNING_TAILS.items()
}


class RichStageFailure(ConversionError):
    """A degradable rich-stage failure carrying a stable typed warning code.

    The human message is always the safe, stable message from
    :data:`RICH_WARNING_MESSAGES`; internal details never leak into the
    package, machine events, or ordinary result.
    """

    def __init__(self, stage: str, code: str):
        if stage not in RICH_STAGE_TITLES:
            raise ValueError(f"unknown rich stage: {stage!r}")
        if code not in RICH_WARNING_TAILS:
            raise ValueError(f"unknown rich warning code: {code!r}")
        self.stage = stage
        self.code = f"{stage}_{code}"
        super().__init__(RICH_WARNING_MESSAGES[self.code])


def rich_warning(error: BaseException, stage: str) -> tuple[str, str]:
    """Map a degradable rich-stage error to a stable typed warning."""
    if isinstance(error, RichStageFailure):
        return error.code, RICH_WARNING_MESSAGES[error.code]
    message = str(error).lower()
    if "timed out" in message:
        code = "timeout"
    elif "safety limit" in message:
        code = "output_too_large"
    elif "could not be started" in message:
        code = "start_failed"
    else:
        code = "failed"
    full = f"{stage}_{code}"
    return full, RICH_WARNING_MESSAGES[full]


def _rich_stage_capability(stage: str) -> dict[str, object]:
    return {
        "optional": True,
        "degradation": "preserve_upstream",
        "adapters": ["fixture", "command", "baseline"],
        "warning_codes": sorted(
            code for code in RICH_WARNING_MESSAGES if code.startswith(f"{stage}_")
        ),
    }

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
        "alignment": {
            "optional": True,
            "degradation": "preserve_subtitle",
            "adapters": ["fixture", "command", "whisper-cpp"],
            "warning_codes": sorted(ALIGNMENT_WARNING_MESSAGES),
        },
        "rich_resources": {
            "sense_groups": _rich_stage_capability("sense_groups"),
            "acoustics": _rich_stage_capability("acoustics"),
            "prosody": _rich_stage_capability("prosody"),
            "phone": {
                "optional": True,
                "degradation": "preserve_upstream",
                "adapters": ["fixture", "command", "wav2vec2-ctc"],
                "warning_codes": sorted(
                    code for code in RICH_WARNING_MESSAGES if code.startswith("phone_")
                ),
            },
        },
        "phone": {
            "production": "optional_audio_backed",
            "unselected": "abstain",
            "text_derived": False,
        },
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
        alignment: dict[str, object] | None = None,
        rich_resources: dict[str, object] | None = None,
    ) -> None:
        payload: dict[str, object] = dict(
            package_sha256=package_sha256,
            media_fingerprint=media_fingerprint,
            resources=resources,
            warnings=warnings,
        )
        if alignment is not None:
            payload["alignment"] = alignment
        if rich_resources is not None:
            payload["rich_resources"] = rich_resources
        self._emit("completed", **payload)

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
    whisper_invalid_arguments = (
        "whisper.cpp model must be a regular file",
        "whisper.cpp model id must be non-empty",
        "whisper.cpp language must be a valid language tag",
        "whisper.cpp timeout must be positive",
        "whisper.cpp executable must be non-empty",
        "whisper.cpp aligner model must be a regular file",
        "whisper.cpp aligner model id must be non-empty",
        "whisper.cpp aligner language must be a valid language tag",
        "whisper.cpp aligner timeout must be positive",
        "whisper.cpp aligner executable must be non-empty",
        "alignment fixture must be a regular file",
        "alignment command executable must be non-empty",
        "alignment command arguments must contain exactly one {media} "
        "and one {transcript} placeholder",
        "alignment command timeout must be positive",
        "sense group fixture must be a regular file",
        "sense group command executable must be non-empty",
        "sense group command arguments must contain exactly one {input} placeholder",
        "sense group command timeout must be positive",
        "acoustics fixture must be a regular file",
        "acoustics command executable must be non-empty",
        "acoustics command arguments must contain exactly one {media} "
        "and one {timeline} placeholder",
        "acoustics command timeout must be positive",
        "prosody fixture must be a regular file",
        "prosody command executable must be non-empty",
        "prosody command arguments must contain exactly one {input} placeholder",
        "prosody command timeout must be positive",
        "phone fixture must be a regular file",
        "phone command executable must be non-empty",
        "phone command arguments must contain exactly one {media} placeholder",
        "phone command timeout must be positive",
        "wav2vec2 phone runtime inputs must exist",
        "wav2vec2 phone arguments are invalid",
        "wav2vec2 phone analysis requires python, sidecar, model directory, id and revision",
    )
    if message in whisper_invalid_arguments:
        return "invalid_arguments"
    if message == "whisper.cpp provider could not be started":
        return "provider_start_failed"
    if message == "whisper.cpp provider timed out":
        return "provider_timeout"
    if message.startswith("whisper.cpp provider failed with exit status"):
        return "provider_failed"
    if message == "whisper.cpp provider runtime or model changed during transcription":
        return "provider_failed"
    if message in {
        "whisper.cpp provider produced no json output",
        "whisper.cpp provider returned invalid json",
        "whisper.cpp provider returned an invalid result",
        "asr transcript must provide word timings for every segment or none",
    }:
        return "provider_output_invalid"
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
