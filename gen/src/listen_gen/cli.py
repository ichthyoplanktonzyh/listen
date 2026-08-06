from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import signal
import sys
import zipfile
from pathlib import Path
from typing import Any, Callable, Iterator

from .asr import (
    CommandAsrAdapter,
    FixtureAsrAdapter,
    PreprocessingAsrAdapter,
    package_media,
)
from .media import FfmpegAudioPreprocessor
from .package import ConversionError, package_from_lltimeline
from .protocol import (
    MACHINE_ERROR_MESSAGES,
    MachineEventEmitter,
    machine_error,
    protocol_capabilities,
)


class CancellationRequested(BaseException):
    """Raised when the process is asked to stop while a machine run is active."""

    def __init__(self, signal_number: int):
        super().__init__(signal_number)
        self.signal_number = signal_number


class _CancellationState:
    def __init__(self) -> None:
        self.signal_number: int | None = None

    def requested(self) -> bool:
        return self.signal_number is not None


@contextlib.contextmanager
def _cancellation_signals(state: _CancellationState) -> Iterator[None]:
    """Install handlers that flag cancellation and interrupt the current call."""

    previous: dict[int, Any] = {}

    def request(signum: int, _frame: Any) -> None:
        state.signal_number = signum
        raise CancellationRequested(signum)

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous[signum] = signal.signal(signum, request)
    try:
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="listen-gen")
    commands = root.add_subparsers(dest="command", required=True)
    package = commands.add_parser("package", help="build a Listen content package")
    package_commands = package.add_subparsers(dest="package_command", required=True)
    native = package_commands.add_parser(
        "from-media", help="transcribe media and emit native v1 resources"
    )
    native.add_argument("input", type=Path)
    native.add_argument("--output", required=True, type=Path)
    native.add_argument("--provider", required=True, choices=["fixture", "command"])
    native.add_argument("--fixture", type=Path, help="normalized JSON for the fixture provider")
    native.add_argument("--command", help="external ASR wrapper executable; no shell is used")
    native.add_argument(
        "--command-arg",
        action="append",
        default=[],
        help="one argv item for the command provider; include {media} exactly once",
    )
    native.add_argument("--command-timeout-seconds", type=float, default=3600.0)
    native.add_argument(
        "--audio-stream-index",
        type=int,
        help="container stream index; required when the media has multiple audio streams",
    )
    native.add_argument("--ffprobe-command", default="ffprobe")
    native.add_argument("--ffmpeg-command", default="ffmpeg")
    native.add_argument("--media-command-timeout-seconds", type=float, default=300.0)
    native.add_argument("--title", required=True)
    native.add_argument("--media-kind", required=True, choices=["audio", "video"])
    native.add_argument("--duration-ms", required=True, type=int)
    native.add_argument("--created-at-ms", required=True, type=int)
    native.add_argument(
        "--machine-events",
        action="store_true",
        help="write the machine-event protocol as NDJSON to stdout",
    )
    legacy = package_commands.add_parser(
        "from-lltimeline", help="convert an LLTimeline v1 document"
    )
    legacy.add_argument("input", type=Path)
    legacy.add_argument("--output", required=True, type=Path)
    return root


def _run(
    args: argparse.Namespace,
    state: _CancellationState,
    writer: MachineEventEmitter | None,
) -> dict[str, Any]:
    progress: Callable[[str], None] | None = None
    if writer is not None:

        def progress(phase: str) -> None:
            if state.requested():
                raise CancellationRequested(state.signal_number or signal.SIGINT)
            writer.phase(phase)

    if args.package_command == "from-media":
        if args.provider == "fixture":
            if args.fixture is None:
                raise ConversionError("--fixture is required for the fixture provider")
            adapter = FixtureAsrAdapter(args.fixture, progress=progress)
        else:
            if args.command is None:
                raise ConversionError("--command is required for the command provider")
            command_adapter = CommandAsrAdapter(
                args.command,
                args.command_arg,
                args.command_timeout_seconds,
                progress=progress,
            )
            adapter = PreprocessingAsrAdapter(
                command_adapter,
                FfmpegAudioPreprocessor(
                    ffprobe_executable=args.ffprobe_command,
                    ffmpeg_executable=args.ffmpeg_command,
                    timeout_seconds=args.media_command_timeout_seconds,
                    progress=progress,
                ),
                audio_stream_index=args.audio_stream_index,
                progress=progress,
            )
        return package_media(
            args.input,
            args.output,
            adapter,
            title=args.title,
            media_kind=args.media_kind,
            duration_ms=args.duration_ms,
            created_at_ms=args.created_at_ms,
            progress=progress,
        )
    return package_from_lltimeline(args.input, args.output)


def _completed_details(package_path: Path) -> tuple[str, str, list[dict[str, object]]]:
    """Read the final package for the completed event, without guessing."""
    digest = hashlib.sha256()
    with package_path.open("rb") as package:
        for chunk in iter(lambda: package.read(1024 * 1024), b""):
            digest.update(chunk)
    with zipfile.ZipFile(package_path) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        resources: list[dict[str, object]] = []
        for entry in manifest["resources"]:
            document = json.loads(archive.read(entry["path"]))
            resources.append(
                {
                    "resource_id": entry["resource_id"],
                    "kind": entry["kind"],
                    "review_status": document["quality"]["review_status"],
                }
            )
    return (
        f"sha256:{digest.hexdigest()}",
        manifest["content_document"]["media_fingerprint"],
        resources,
    )


def _emit_success(
    writer: MachineEventEmitter, output_path: Path, result: dict[str, Any]
) -> None:
    package_sha256, media_fingerprint, resources = _completed_details(output_path)
    writer.completed(
        package_sha256=package_sha256,
        media_fingerprint=media_fingerprint,
        resources=resources,
        warnings=result["warnings"],
    )


def _main_machine(args: argparse.Namespace) -> int:
    writer = MachineEventEmitter()
    state = _CancellationState()
    writer.protocol(protocol_capabilities())
    writer.started()
    with _cancellation_signals(state):
        try:
            result = _run(args, state, writer)
            _emit_success(writer, args.output, result)
            return 0
        except CancellationRequested:
            if writer.terminal_emitted:
                return 0 if writer.terminal_event == "completed" else 2
            writer.cancelled()
            return 130
        except (ConversionError, OSError, json.JSONDecodeError) as error:
            code, message = machine_error(error)
            writer.failed(code=code, message=message)
            return 2
        except Exception:
            writer.failed(
                code="internal_error",
                message=MACHINE_ERROR_MESSAGES["internal_error"],
            )
            return 2


def _main_ordinary(args: argparse.Namespace) -> int:
    state = _CancellationState()
    try:
        result = _run(args, state, None)
    except (ConversionError, OSError, json.JSONDecodeError) as error:
        print(
            json.dumps(
                {"status": "failed", "error": str(error)},
                ensure_ascii=False,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    if getattr(args, "machine_events", False):
        return _main_machine(args)
    return _main_ordinary(args)
