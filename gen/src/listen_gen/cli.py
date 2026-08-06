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
    writer: MachineEventEmitter,
    state: _CancellationState,
) -> int:
    with _cancellation_signals(state):
        try:
            staging_path = _create_machine_staging_path(args.output)
            try:
                machine_args = argparse.Namespace(**vars(args))
                machine_args.output = staging_path
                result = _run(machine_args, state, writer)
                package_sha256, media_fingerprint, resources = _completed_details(
                    staging_path
                )
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
                    os.replace(staging_path, args.output)
                    writer.completed(
                        package_sha256=package_sha256,
                        media_fingerprint=media_fingerprint,
                        resources=resources,
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
    raw_argv = list(sys.argv[1:] if argv is None else argv)
    help_requested = "-h" in raw_argv or "--help" in raw_argv
    machine_requested = "--machine-events" in raw_argv and not help_requested
    if not machine_requested:
        args = parser().parse_args(raw_argv)
        return _main_ordinary(args)
    writer = MachineEventEmitter()
    state = _CancellationState()
    writer.protocol(protocol_capabilities())
    writer.started()
    writer.phase("validating")
    try:
        args = parser(parser_class=MachineArgumentParser).parse_args(raw_argv)
    except ArgumentParsingFailed:
        writer.failed(
            code="invalid_arguments",
            message=MACHINE_ERROR_MESSAGES["invalid_arguments"],
        )
        return 2
    return _main_machine(args, writer=writer, state=state)
