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
from .alignment import (
    CommandAlignerAdapter,
    FixtureAlignerAdapter,
    WhisperCppAlignerAdapter,
)
from .media import FfmpegAudioPreprocessor
from .package import ConversionError, package_from_lltimeline
from .phone import (
    CommandPhoneAdapter,
    FixturePhoneAdapter,
    Wav2Vec2CtcPhoneAdapter,
)
from .protocol import (
    MACHINE_ERROR_MESSAGES,
    MachineEventEmitter,
    machine_error,
    protocol_capabilities,
)
from .rich import (
    CommandAcousticsAdapter,
    CommandProsodyAdapter,
    CommandSenseGroupAdapter,
    FixtureAcousticsAdapter,
    FixtureProsodyAdapter,
    FixtureSenseGroupAdapter,
)
from .rich_baselines import (
    AcousticProsodyBaseline,
    PunctuationSenseGroupBaseline,
    WavWordAcousticsBaseline,
)
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
    native = package_commands.add_parser(
        "from-media", help="transcribe media and emit native v1 resources"
    )
    native.add_argument("input", type=Path)
    native.add_argument("--output", required=True, type=Path)
    native.add_argument(
        "--provider",
        required=True,
        choices=["fixture", "command", "whisper-cpp"],
    )
    native.add_argument("--fixture", type=Path, help="normalized JSON for the fixture provider")
    native.add_argument("--command", help="external ASR wrapper executable; no shell is used")
    native.add_argument(
        "--command-arg",
        action="append",
        default=[],
        help="one argv item for the command provider; include {media} exactly once",
    )
    native.add_argument("--command-timeout-seconds", type=float, default=3600.0)
    native.add_argument("--whisper-cli", default="whisper-cli")
    native.add_argument("--whisper-model", type=Path)
    native.add_argument("--whisper-model-id")
    native.add_argument("--whisper-language", default="auto")
    native.add_argument("--whisper-translate-to-english", action="store_true")
    native.add_argument("--whisper-timeout-seconds", type=float, default=3600.0)
    native.add_argument(
        "--audio-stream-index",
        type=int,
        help="container stream index; required when the media has multiple audio streams",
    )
    native.add_argument("--ffprobe-command", default="ffprobe")
    native.add_argument("--ffmpeg-command", default="ffmpeg")
    native.add_argument("--media-command-timeout-seconds", type=float, default=300.0)
    native.add_argument(
        "--aligner",
        default="none",
        choices=["none", "fixture", "command", "whisper-cpp"],
        help="optional word-alignment adapter; alignment is always optional",
    )
    native.add_argument(
        "--alignment-fixture",
        type=Path,
        help="normalized align-result JSON for the fixture aligner",
    )
    native.add_argument(
        "--alignment-command",
        help="external word-aligner executable; no shell is used",
    )
    native.add_argument(
        "--alignment-command-arg",
        action="append",
        default=[],
        help=(
            "one argv item for the command aligner; include {media} and "
            "{transcript} exactly once each"
        ),
    )
    native.add_argument(
        "--alignment-command-timeout-seconds", type=float, default=3600.0
    )
    native.add_argument(
        "--sense-groups",
        default="none",
        choices=["none", "fixture", "command", "baseline"],
        help=(
            "optional sense-group stage adapter; the stage is always optional "
            "(baseline is the built-in deterministic punctuation/length producer)"
        ),
    )
    native.add_argument(
        "--sense-groups-fixture",
        type=Path,
        help="normalized sense-group-result JSON for the fixture adapter",
    )
    native.add_argument(
        "--sense-groups-command",
        help="external sense-group analyzer; no shell is used",
    )
    native.add_argument(
        "--sense-groups-command-arg",
        action="append",
        default=[],
        help=(
            "one argv item for the sense-group analyzer; include {input} "
            "exactly once"
        ),
    )
    native.add_argument(
        "--sense-groups-command-timeout-seconds", type=float, default=3600.0
    )
    native.add_argument(
        "--acoustics",
        default="none",
        choices=["none", "fixture", "command", "baseline"],
        help=(
            "optional word-acoustics stage adapter; requires a word timeline "
            "(baseline measures the normalized 16 kHz mono PCM WAV in-process)"
        ),
    )
    native.add_argument(
        "--acoustics-fixture",
        type=Path,
        help="normalized acoustics-result JSON for the fixture adapter",
    )
    native.add_argument(
        "--acoustics-command",
        help="external acoustics extractor; no shell is used",
    )
    native.add_argument(
        "--acoustics-command-arg",
        action="append",
        default=[],
        help=(
            "one argv item for the acoustics extractor; include {media} and "
            "{timeline} exactly once each"
        ),
    )
    native.add_argument(
        "--acoustics-command-timeout-seconds", type=float, default=3600.0
    )
    native.add_argument(
        "--prosody",
        default="none",
        choices=["none", "fixture", "command", "baseline"],
        help=(
            "optional prosody stage adapter; requires a word timeline and acoustics "
            "(baseline is the built-in acoustic-rule producer)"
        ),
    )
    native.add_argument(
        "--prosody-fixture",
        type=Path,
        help="normalized prosody-result JSON for the fixture adapter",
    )
    native.add_argument(
        "--prosody-command",
        help="external prosody analyzer; no shell is used",
    )
    native.add_argument(
        "--prosody-command-arg",
        action="append",
        default=[],
        help=(
            "one argv item for the prosody analyzer; include {input} exactly once"
        ),
    )
    native.add_argument(
        "--prosody-command-timeout-seconds", type=float, default=3600.0
    )
    native.add_argument(
        "--phone",
        default="none",
        choices=["none", "fixture", "command", "wav2vec2-ctc"],
        help="optional audio-backed phone analysis; unselected means explicit abstention",
    )
    native.add_argument("--phone-fixture", type=Path)
    native.add_argument("--phone-command")
    native.add_argument("--phone-command-arg", action="append", default=[])
    native.add_argument("--phone-command-timeout-seconds", type=float, default=3600.0)
    native.add_argument("--phone-python", type=Path)
    native.add_argument("--phone-sidecar", type=Path)
    native.add_argument("--phone-model-dir", type=Path)
    native.add_argument("--phone-model-id")
    native.add_argument("--phone-model-revision")
    native.add_argument("--phone-timeout-seconds", type=float, default=3600.0)
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
        elif args.provider == "command":
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
        else:
            whisper_adapter = WhisperCppAsrAdapter(
                args.whisper_cli,
                args.whisper_model,
                args.whisper_model_id,
                args.whisper_language,
                args.whisper_translate_to_english,
                args.whisper_timeout_seconds,
            )
            adapter = PreprocessingAsrAdapter(
                whisper_adapter,
                FfmpegAudioPreprocessor(
                    ffprobe_executable=args.ffprobe_command,
                    ffmpeg_executable=args.ffmpeg_command,
                    timeout_seconds=args.media_command_timeout_seconds,
                    progress=progress,
                ),
                audio_stream_index=args.audio_stream_index,
                progress=progress,
            )
        aligner, aligner_preprocessor = _build_aligner(args)
        (
            sense_analyzer,
            acoustics_extractor,
            acoustics_preprocessor,
            prosody_analyzer,
        ) = _build_rich(args)
        phone_analyzer, phone_preprocessor = _build_phone(args)
        return package_media(
            args.input,
            args.output,
            adapter,
            title=args.title,
            media_kind=args.media_kind,
            duration_ms=args.duration_ms,
            created_at_ms=args.created_at_ms,
            progress=progress,
            aligner=aligner,
            aligner_preprocessor=aligner_preprocessor,
            aligner_audio_stream_index=args.audio_stream_index,
            sense_analyzer=sense_analyzer,
            acoustics_extractor=acoustics_extractor,
            acoustics_preprocessor=acoustics_preprocessor,
            acoustics_audio_stream_index=args.audio_stream_index,
            prosody_analyzer=prosody_analyzer,
            phone_analyzer=phone_analyzer,
            phone_preprocessor=phone_preprocessor,
            phone_audio_stream_index=args.audio_stream_index,
        )
    return package_from_lltimeline(args.input, args.output)


def _build_aligner(
    args: argparse.Namespace,
) -> tuple[Any | None, FfmpegAudioPreprocessor | None]:
    """Resolve the optional alignment adapter and its audio preprocessor.

    The whisper-cpp aligner reuses the whisper provider arguments so the
    first-class whisper.cpp path can select it directly
    (``--provider whisper-cpp --aligner whisper-cpp``). The alignment
    preprocessor never emits machine phases; ``aligning`` covers the whole
    stage.
    """
    if args.aligner == "none":
        return None, None
    preprocessor = FfmpegAudioPreprocessor(
        ffprobe_executable=args.ffprobe_command,
        ffmpeg_executable=args.ffmpeg_command,
        timeout_seconds=args.media_command_timeout_seconds,
    )
    if args.aligner == "fixture":
        if args.alignment_fixture is None:
            raise ConversionError(
                "--alignment-fixture is required for the fixture aligner"
            )
        return FixtureAlignerAdapter(args.alignment_fixture), None
    if args.aligner == "command":
        if args.alignment_command is None:
            raise ConversionError(
                "--alignment-command is required for the command aligner"
            )
        aligner = CommandAlignerAdapter(
            args.alignment_command,
            args.alignment_command_arg,
            args.alignment_command_timeout_seconds,
        )
        return aligner, preprocessor
    whisper_aligner = WhisperCppAlignerAdapter(
        args.whisper_cli,
        args.whisper_model,
        args.whisper_model_id,
        args.whisper_language,
        args.whisper_translate_to_english,
        args.whisper_timeout_seconds,
    )
    return whisper_aligner, preprocessor


def _rich_command(
    args: argparse.Namespace,
    *,
    stage: str,
    fixture: str,
    command: str,
    command_args: str,
    timeout: str,
) -> Any:
    """Resolve one optional rich-stage adapter from the CLI arguments.

    The ``baseline`` choice selects the built-in deterministic, credential-free
    producer for the stage; it needs no fixture, command, or timeout and is
    never selected implicitly.
    """
    selected = getattr(args, stage)
    fixture_path = getattr(args, fixture)
    executable = getattr(args, command)
    arguments = getattr(args, command_args)
    timeout_seconds = getattr(args, timeout)
    if selected == "baseline":
        if stage == "sense_groups":
            return PunctuationSenseGroupBaseline()
        if stage == "acoustics":
            return WavWordAcousticsBaseline()
        return AcousticProsodyBaseline()
    if selected == "fixture":
        if fixture_path is None:
            flag = fixture.replace("_", "-")
            raise ConversionError(f"--{flag} is required for the {stage} fixture adapter")
        if stage == "sense_groups":
            return FixtureSenseGroupAdapter(fixture_path)
        if stage == "acoustics":
            return FixtureAcousticsAdapter(fixture_path)
        return FixtureProsodyAdapter(fixture_path)
    if selected == "command":
        if executable is None:
            flag = command.replace("_", "-")
            raise ConversionError(f"--{flag} is required for the {stage} command adapter")
        if stage == "sense_groups":
            return CommandSenseGroupAdapter(executable, arguments, timeout_seconds)
        if stage == "acoustics":
            return CommandAcousticsAdapter(executable, arguments, timeout_seconds)
        return CommandProsodyAdapter(executable, arguments, timeout_seconds)
    return None


def _build_rich(
    args: argparse.Namespace,
) -> tuple[Any | None, Any | None, FfmpegAudioPreprocessor | None, Any | None]:
    """Resolve the optional sense-group, acoustics, and prosody adapters.

    The acoustics stage receives the same temporary 16 kHz mono PCM WAV as the
    ASR stage when a command adapter is selected; the fixture adapters replay
    committed results and need no media commands. The acoustics preprocessor
    never emits machine phases; the ``measuring_acoustics`` phase covers the
    whole stage.
    """
    sense_analyzer = _rich_command(
        args,
        stage="sense_groups",
        fixture="sense_groups_fixture",
        command="sense_groups_command",
        command_args="sense_groups_command_arg",
        timeout="sense_groups_command_timeout_seconds",
    )
    acoustics_extractor = _rich_command(
        args,
        stage="acoustics",
        fixture="acoustics_fixture",
        command="acoustics_command",
        command_args="acoustics_command_arg",
        timeout="acoustics_command_timeout_seconds",
    )
    prosody_analyzer = _rich_command(
        args,
        stage="prosody",
        fixture="prosody_fixture",
        command="prosody_command",
        command_args="prosody_command_arg",
        timeout="prosody_command_timeout_seconds",
    )
    acoustics_preprocessor: FfmpegAudioPreprocessor | None = None
    if getattr(args, "acoustics") in {"command", "baseline"}:
        acoustics_preprocessor = FfmpegAudioPreprocessor(
            ffprobe_executable=args.ffprobe_command,
            ffmpeg_executable=args.ffmpeg_command,
            timeout_seconds=args.media_command_timeout_seconds,
        )
    return (
        sense_analyzer,
        acoustics_extractor,
        acoustics_preprocessor,
        prosody_analyzer,
    )


def _build_phone(
    args: argparse.Namespace,
) -> tuple[Any | None, FfmpegAudioPreprocessor | None]:
    if args.phone == "none":
        return None, None
    if args.phone == "fixture":
        if args.phone_fixture is None:
            raise ConversionError("--phone-fixture is required for the fixture adapter")
        try:
            return FixturePhoneAdapter(args.phone_fixture), None
        except ValueError as error:
            raise ConversionError(str(error)) from error
    preprocessor = FfmpegAudioPreprocessor(
        ffprobe_executable=args.ffprobe_command,
        ffmpeg_executable=args.ffmpeg_command,
        timeout_seconds=args.media_command_timeout_seconds,
    )
    if args.phone == "command":
        if args.phone_command is None:
            raise ConversionError("--phone-command is required for the command adapter")
        try:
            adapter = CommandPhoneAdapter(
                args.phone_command,
                args.phone_command_arg,
                args.phone_command_timeout_seconds,
            )
        except ValueError as error:
            raise ConversionError(str(error)) from error
        return adapter, preprocessor
    required = (
        args.phone_python,
        args.phone_sidecar,
        args.phone_model_dir,
        args.phone_model_id,
        args.phone_model_revision,
    )
    if any(value is None for value in required):
        raise ConversionError(
            "wav2vec2 phone analysis requires python, sidecar, model directory, id and revision"
        )
    try:
        adapter = Wav2Vec2CtcPhoneAdapter(
            args.phone_python,
            args.phone_sidecar,
            args.phone_model_dir,
            args.phone_model_id,
            args.phone_model_revision,
            args.phone_timeout_seconds,
        )
    except ValueError as error:
        raise ConversionError(str(error)) from error
    return adapter, preprocessor


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
                        alignment=result.get("alignment"),
                        rich_resources=result.get("rich_resources"),
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
