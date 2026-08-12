"""listen-gen CLI: the capability production command.

The v1 media-package commands and machine protocol were removed in the Slice
3 cutover; ``package from-capability`` is the only command and the v2
machine protocol the only machine exchange.
"""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import signal
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Callable, Iterator

from .asr import (
    CommandAsrAdapter,
    FixtureAsrAdapter,
    PreprocessingAsrAdapter,
)
from .capability import CapabilityRequest
from .document import FixtureOcrProvider
from .media import FfmpegAudioPreprocessor
from .package import ConversionError
from .plan import UnsupportedCapability
from .produce import ProduceConfig, ProductionFailure, produce
from .protocol_v2 import (
    MachineEventV2Emitter,
    protocol_capabilities_v2,
)
from .tts import FakeTtsAdapter, FixtureTtsAdapter, SayTtsAdapter
from .whisper_cpp import WhisperCppAsrAdapter


class CancellationRequested(BaseException):
    """Raised when the process is asked to stop while a machine run is active."""

    def __init__(self, signal_number: int):
        super().__init__(signal_number)
        self.signal_number = signal_number


class ArgumentParsingFailed(Exception):
    """Argparse rejected the invocation without printing usage or exiting."""


class MachineArgumentParser(argparse.ArgumentParser):
    """ArgumentParser that reports machine-mode failures as exceptions."""

    def error(self, message: str) -> None:
        raise ArgumentParsingFailed(message)


class _CancellationState:
    def __init__(self) -> None:
        self.signal_number: int | None = None
        self.terminal_commit = False

    def requested(self) -> bool:
        return self.signal_number is not None


@contextlib.contextmanager
def _cancellation_signals(state: _CancellationState) -> Iterator[None]:
    """Install handlers that flag cancellation and interrupt the current call."""

    previous: dict[int, Any] = {}

    def request(signum: int, _frame: Any) -> None:
        state.signal_number = signum
        if not state.terminal_commit:
            raise CancellationRequested(signum)

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous[signum] = signal.signal(signum, request)
    try:
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


@contextlib.contextmanager
def _terminal_commit(state: _CancellationState) -> Iterator[None]:
    """Make the final replace + completed event uninterruptible as a unit."""

    if state.requested():
        raise CancellationRequested(state.signal_number or signal.SIGINT)
    state.terminal_commit = True
    try:
        yield
    finally:
        state.terminal_commit = False


def parser(
    *,
    parser_class: type[argparse.ArgumentParser] = argparse.ArgumentParser,
) -> argparse.ArgumentParser:
    root = parser_class(prog="listen-gen")
    commands = root.add_subparsers(dest="command", required=True)
    package = commands.add_parser("package", help="build a Listen content package")
    package_commands = package.add_subparsers(dest="package_command", required=True)
    produce = package_commands.add_parser(
        "from-capability",
        help="produce a Content Package v3 from a capability request",
    )
    produce.add_argument("request", type=Path, help="capability request JSON document")
    produce.add_argument("--output", required=True, type=Path)
    produce.add_argument(
        "--tts-provider",
        default="none",
        choices=["none", "fixture", "say", "fake"],
        help="TTS provider for document-to-listen derivations (say is the macOS local adapter)",
    )
    produce.add_argument("--tts-fixture", type=Path, help="audio fixture for the fixture TTS provider")
    produce.add_argument(
        "--tts-alignment-fixture",
        type=Path,
        help="committed anchor alignment JSON for the fixture TTS provider",
    )
    produce.add_argument("--tts-voice", help="macOS say voice name for the say TTS provider")
    produce.add_argument("--tts-timeout-seconds", type=float, default=600.0)
    produce.add_argument(
        "--ocr-provider",
        default="none",
        choices=["none", "fixture"],
        help="optional OCR path for scanned PDFs; absence is an honest capability result",
    )
    produce.add_argument("--ocr-fixture", type=Path, help="committed OCR text for the fixture OCR provider")
    produce.add_argument(
        "--provider",
        default="none",
        choices=["none", "fixture", "command", "whisper-cpp"],
        help="ASR provider for media-to-read derivations",
    )
    produce.add_argument("--fixture", type=Path, help="normalized JSON for the fixture ASR provider")
    produce.add_argument("--command", help="external ASR wrapper executable; no shell is used")
    produce.add_argument(
        "--command-arg",
        action="append",
        default=[],
        help="one argv item for the command ASR provider; include {media} exactly once",
    )
    produce.add_argument("--command-timeout-seconds", type=float, default=3600.0)
    produce.add_argument("--whisper-cli", default="whisper-cli")
    produce.add_argument("--whisper-model", type=Path)
    produce.add_argument("--whisper-model-id")
    produce.add_argument("--whisper-language", default="auto")
    produce.add_argument("--whisper-translate-to-english", action="store_true")
    produce.add_argument("--whisper-timeout-seconds", type=float, default=3600.0)
    produce.add_argument(
        "--audio-stream-index",
        type=int,
        help="container stream index; required when the media has multiple audio streams",
    )
    produce.add_argument("--ffprobe-command", default="ffprobe")
    produce.add_argument("--ffmpeg-command", default="ffmpeg")
    produce.add_argument("--media-command-timeout-seconds", type=float, default=300.0)
    produce.add_argument(
        "--machine-events",
        action="store_true",
        help="write the machine-event protocol as NDJSON to stdout",
    )
    return root


def _build_asr(args: argparse.Namespace, progress=None) -> Any | None:
    """Resolve the optional ASR adapter for capability derivations."""
    if getattr(args, "provider", "none") == "none":
        return None
    if args.provider == "fixture":
        if args.fixture is None:
            raise ConversionError("--fixture is required for the fixture ASR provider")
        return FixtureAsrAdapter(args.fixture, progress=progress)
    preprocessor = FfmpegAudioPreprocessor(
        ffprobe_executable=args.ffprobe_command,
        ffmpeg_executable=args.ffmpeg_command,
        timeout_seconds=args.media_command_timeout_seconds,
        progress=progress,
    )
    if args.provider == "command":
        if args.command is None:
            raise ConversionError("--command is required for the command ASR provider")
        return PreprocessingAsrAdapter(
            CommandAsrAdapter(
                args.command,
                args.command_arg,
                args.command_timeout_seconds,
                progress=progress,
            ),
            preprocessor,
            audio_stream_index=args.audio_stream_index,
            progress=progress,
        )
    return PreprocessingAsrAdapter(
        WhisperCppAsrAdapter(
            args.whisper_cli,
            args.whisper_model,
            args.whisper_model_id,
            args.whisper_language,
            args.whisper_translate_to_english,
            args.whisper_timeout_seconds,
        ),
        preprocessor,
        audio_stream_index=args.audio_stream_index,
        progress=progress,
    )


def _build_tts(args: argparse.Namespace) -> Any | None:
    selected = args.tts_provider
    if selected == "none":
        return None
    if selected == "fake":
        return FakeTtsAdapter()
    if selected == "say":
        return SayTtsAdapter(
            voice=args.tts_voice,
            timeout_seconds=args.tts_timeout_seconds,
        )
    if args.tts_fixture is None:
        raise ConversionError("--tts-fixture is required for the fixture TTS provider")
    return FixtureTtsAdapter(args.tts_fixture, args.tts_alignment_fixture)


def _build_ocr(args: argparse.Namespace) -> Any | None:
    if args.ocr_provider == "none":
        return None
    if args.ocr_fixture is None:
        raise ConversionError("--ocr-fixture is required for the fixture OCR provider")
    return FixtureOcrProvider(args.ocr_fixture)


def _default_attempt_id(request: CapabilityRequest) -> str:
    identity = "|".join(
        (
            request.material.material_id,
            request.material.material_revision_id,
            request.requested_capability,
            str(request.created_at_ms),
        )
    )
    return "attempt-" + hashlib.sha256(identity.encode("utf-8")).hexdigest()[:16]


def _run(
    args: argparse.Namespace,
    state: _CancellationState,
    writer: MachineEventV2Emitter | None,
) -> dict[str, Any]:
    request = CapabilityRequest.from_json_file(args.request)
    if writer is not None:
        writer.accepted(request.attempt_id or _default_attempt_id(request))

        def check_cancelled() -> None:
            if state.requested():
                raise CancellationRequested(state.signal_number or signal.SIGINT)

        def progress(stage: str) -> None:
            check_cancelled()
            writer.running(stage)

        from .plan import plan as plan_request

        production_plan = plan_request(request)
        writer.planned(production_plan.describe())
    else:
        check_cancelled = None
        progress = None
    config = ProduceConfig(
        tts=_build_tts(args),
        ocr=_build_ocr(args),
        asr=_build_asr(args, progress=progress),
    )
    outcome = produce(
        request,
        Path(args.output),
        config=config,
        progress=progress,
        check_cancelled=check_cancelled,
    )
    for warning in outcome.warnings:
        if writer is not None:
            writer.warning(warning["code"], warning["message"])
    if outcome.release is None:
        return {
            "status": "completed",
            "package_sha256": None,
            "warnings": list(outcome.warnings),
            "document_renditions": [],
            "media_renditions": [],
            "resources": [],
        }
    release = outcome.release
    return {
        "status": "completed",
        "package_sha256": (
            f"sha256:{outcome.package_sha256}" if outcome.package_sha256 else None
        ),
        "warnings": list(outcome.warnings),
        "document_renditions": [
            {"rendition_id": entry.rendition_id, "origin": entry.origin}
            for entry in release.document_renditions
        ],
        "media_renditions": [
            {"rendition_id": entry.rendition_id, "origin": entry.origin}
            for entry in release.media_renditions
        ],
        "resources": [
            {"resource_id": entry.resource_id, "kind": entry.kind}
            for entry in release.resources
        ],
    }


def _classify_error(error: BaseException) -> tuple[str, str]:
    """Map a capability-run exception to a stable v2 failure code."""
    if isinstance(error, UnsupportedCapability):
        return ("unsupported_capability", str(error))
    if isinstance(error, ProductionFailure):
        return (error.code, str(error))
    if isinstance(error, (ConversionError, OSError, json.JSONDecodeError)):
        return ("invalid_request", str(error))
    return ("internal_error", "generation failed because of an internal error")


def _create_machine_staging_path(output_path: Path) -> Path:
    """Reserve a unique same-directory staging name for the final package."""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(
        dir=output_path.parent,
        prefix=f".{output_path.name}.",
        suffix=".machine.tmp",
    )
    os.close(descriptor)
    path = Path(name)
    path.unlink()
    return path


def _main_machine(
    args: argparse.Namespace,
    *,
    writer: MachineEventV2Emitter,
    state: _CancellationState,
) -> int:
    with _cancellation_signals(state):
        try:
            staging_path = _create_machine_staging_path(args.output)
            try:
                machine_args = argparse.Namespace(**vars(args))
                machine_args.output = staging_path
                result = _run(machine_args, state, writer)
                if (
                    os.environ.get("LISTEN_GEN_TEST_PAUSE_BEFORE_TERMINAL_COMMIT")
                    == "1"
                ):
                    marker = os.environ.get("LISTEN_GEN_TEST_BEFORE_COMMIT_MARKER")
                    if marker:
                        Path(marker).write_text("ready", encoding="utf-8")
                    while not state.requested():
                        time.sleep(0.01)
                if state.requested():
                    raise CancellationRequested(
                        state.signal_number or signal.SIGINT
                    )
                with _terminal_commit(state):
                    if result["package_sha256"] is not None:
                        os.replace(staging_path, args.output)
                    writer.completed(
                        package_sha256=result["package_sha256"],
                        document_renditions=result["document_renditions"],
                        media_renditions=result["media_renditions"],
                        resources=result["resources"],
                        warnings=result["warnings"],
                    )
                return 0
            finally:
                staging_path.unlink(missing_ok=True)
        except CancellationRequested:
            if writer.terminal_emitted:
                return 0 if writer.terminal_event == "completed" else 2
            writer.cancelled()
            return 130
        except (ConversionError, OSError, json.JSONDecodeError) as error:
            code, message = _classify_error(error)
            writer.failed(code=code, message=message)
            return 2
        except Exception:
            writer.failed(
                code="internal_error",
                message="generation failed because of an internal error",
            )
            return 2


def _main_ordinary(args: argparse.Namespace) -> int:
    state = _CancellationState()
    try:
        result = _run(args, state, None)
    except (ConversionError, OSError, json.JSONDecodeError) as error:
        code, message = _classify_error(error)
        print(
            json.dumps(
                {"status": "failed", "code": code, "error": message},
                ensure_ascii=False,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    help_requested = "-h" in raw_argv or "--help" in raw_argv
    machine_requested = "--machine-events" in raw_argv and not help_requested
    if not machine_requested:
        args = parser().parse_args(raw_argv)
        return _main_ordinary(args)
    writer = MachineEventV2Emitter()
    state = _CancellationState()
    writer.protocol(protocol_capabilities_v2())
    try:
        args = parser(parser_class=MachineArgumentParser).parse_args(raw_argv)
    except ArgumentParsingFailed:
        writer.failed(
            code="invalid_arguments",
            message="Generation arguments are invalid.",
        )
        return 2
    return _main_machine(args, writer=writer, state=state)
