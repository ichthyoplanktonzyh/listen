"""listen-gen machine event protocol v2.

The v2 protocol is the capability-oriented exchange between Listen App and
Listen Gen. Events carry typed request acceptance, the derivation plan, run
progress, honest warnings, and one terminal outcome; ``completed`` names the
exact produced artifact, ``cancelled`` and ``failed`` carry no artifact.

Event sequence: ``protocol``, ``accepted``, ``planned``, zero or more
``running``/``warning`` pairs, then exactly one terminal event
(``completed`` | ``cancelled`` | ``failed``).
"""

from __future__ import annotations

import json
import sys
from typing import Any, TextIO

from . import __version__ as TOOL_VERSION

MACHINE_EVENT_SCHEMA_V2 = "listen_gen.machine-event.v2"
MACHINE_PROTOCOL_VERSION = 2
TOOL_ID = "listen-gen"

EVENT_TYPES = (
    "protocol",
    "accepted",
    "planned",
    "running",
    "warning",
    "completed",
    "cancelled",
    "failed",
)
TERMINAL_EVENTS = frozenset({"completed", "cancelled", "failed"})


def protocol_capabilities_v2() -> dict[str, object]:
    return {
        "package_schemas": ["listen.content-package.release.v3"],
        "machine_protocol_version": MACHINE_PROTOCOL_VERSION,
        "events": list(EVENT_TYPES),
        "capabilities": ["read", "listen", "watch", "synchronized_read_listen"],
        "derivations": [
            "document_to_structured_reading",
            "document_to_listen",
            "media_to_structured_reading",
        ],
    }


class MachineEventV2Emitter:
    """Emit the v2 machine protocol as strict NDJSON on stdout."""

    def __init__(self, stream: TextIO | None = None) -> None:
        self.sequence = 0
        self.terminal_emitted = False
        self.terminal_event: str | None = None
        self._stream = sys.stdout if stream is None else stream
        self._protocol_emitted = False
        self._accepted_emitted = False
        self._planned_emitted = False

    def protocol(self, capabilities: dict[str, object]) -> None:
        self._emit("protocol", capabilities=capabilities)

    def accepted(self, attempt_id: str) -> None:
        self._emit("accepted", attempt_id=attempt_id)

    def planned(self, plan: dict[str, object]) -> None:
        self._emit("planned", plan=plan)

    def running(self, stage: str, message: str = "") -> None:
        payload: dict[str, object] = {"stage": stage}
        if message:
            payload["message"] = message
        self._emit("running", **payload)

    def warning(self, code: str, message: str) -> None:
        self._emit("warning", code=code, message=message)

    def completed(
        self,
        *,
        package_sha256: str | None,
        document_renditions: list[dict[str, object]],
        media_renditions: list[dict[str, object]],
        resources: list[dict[str, object]],
        warnings: list[dict[str, object]],
    ) -> None:
        payload: dict[str, object] = {
            "package_sha256": package_sha256,
            "document_renditions": document_renditions,
            "media_renditions": media_renditions,
            "resources": resources,
            "warnings": warnings,
        }
        self._emit("completed", **payload)

    def cancelled(self) -> None:
        self._emit("cancelled")

    def failed(self, *, code: str, message: str) -> None:
        self._emit("failed", code=code, message=message)

    def _emit(self, event: str, **payload: Any) -> None:
        if self.terminal_emitted:
            raise RuntimeError(
                "v2 machine event emitter cannot emit after a terminal event"
            )
        if event == "protocol":
            if self.sequence != 0 or self._protocol_emitted:
                raise RuntimeError(
                    "protocol must be the first and only emitted event"
                )
            self._protocol_emitted = True
        elif event == "accepted":
            if not self._protocol_emitted:
                raise RuntimeError("accepted must follow the protocol event")
            if self._accepted_emitted:
                raise RuntimeError("accepted may only be emitted once")
            self._accepted_emitted = True
        elif event == "planned":
            if not self._accepted_emitted:
                raise RuntimeError("planned must follow the accepted event")
            if self._planned_emitted:
                raise RuntimeError("planned may only be emitted once")
            self._planned_emitted = True
        elif event in ("running", "warning"):
            if not self._planned_emitted:
                raise RuntimeError(f"{event} must follow the planned event")
        elif event == "failed":
            if not self._protocol_emitted:
                raise RuntimeError("failed must follow the protocol event")
        elif event in TERMINAL_EVENTS:
            if not self._accepted_emitted:
                raise RuntimeError(
                    f"{event} must follow the accepted event"
                )
        else:
            raise RuntimeError(f"unknown v2 machine event: {event!r}")
        document: dict[str, object] = {
            "schema": MACHINE_EVENT_SCHEMA_V2,
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
