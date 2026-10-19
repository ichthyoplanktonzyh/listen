#!/usr/bin/env python3
"""Thin launcher for the local Speech-to-Speech cascade service.

The listen-core `local_cascade_realtime` adapter talks the wire protocol of
`huggingface/speech-to-speech` (the same engine qwen-audio-agent integrates).
This script only *starts that service* on the loopback interface; it does not
implement any protocol, transcribe, speak, or download models by itself.

    tool/run_local_speech_to_speech.py --check      # is the service installed?
    tool/run_local_speech_to_speech.py --install    # pip install the package
    tool/run_local_speech_to_speech.py              # run the service (foreground)
    tool/run_local_speech_to_speech.py --managed --app <app-binary>
                                                    # app + core manage the service

Defaults target the listen-core handoff stack on Apple Silicon
(parakeet-tdt STT + MLX Qwen3-4B + Qwen3-TTS, everything on MPS), which is
exactly upstream's `--mac-optimal-settings` preset:

    ws://127.0.0.1:8765/v1/realtime   (service WebSocket endpoint)
    http://127.0.0.1:8765/v1/pool     (readiness pool document)

Notes:

- The service is intentionally unauthenticated; this launcher refuses any
  non-loopback `--host`, matching listen-core's loopback enforcement.
- listen-core's codec pins wire compatibility to
  `huggingface/speech-to-speech@cc37fe84...` (ADR 0034). Newer upstream
  revisions are expected to remain compatible, but if the wire drifts, the
  pinned revision is the one core was audited against.
- listen-core also has a *managed* sidecar mode (spawn + `/v1/pool` readiness
  + process-group shutdown) enabled through `LLPLAYERNEXT_LOCAL_REALTIME_*`
  environment variables at core startup. This launcher is the manual
  alternative to that managed path.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

DEFAULT_ENDPOINT = "ws://127.0.0.1:8765/v1/realtime"
DEFAULT_READINESS = "http://127.0.0.1:8765/v1/pool"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765

# The service lives in its own venv: homebrew/system Python is
# externally-managed (PEP 668) and refuses pip installs there.
VENV_DIR = Path.home() / ".listen" / "local-speech-venv"

DEFAULT_LOCAL_MODELS_DIR = Path.home() / ".listen" / "local-speech-models"

# Apple Silicon preset, mirroring listen-core's local-realtime-cascade handoff.
DEFAULT_STT = "parakeet-tdt"
DEFAULT_LLM_BACKEND = "mlx-lm"
DEFAULT_LLM_MODEL = "mlx-community/Qwen3-4B-Instruct-2507-bf16"
DEFAULT_TTS = "qwen3"

PACKAGE = "speech-to-speech[paraformer]"
EXECUTABLE = "speech-to-speech"

# listen-core pins wire compatibility to this upstream commit (ADR 0034). Its
# managed sidecar additionally spawns the service by appending the flag names
# that revision accepted (--mode/--ws_host/--ws_port); newer upstream moved to
# --host/--port. Managed mode therefore targets the pinned revision's surface.
PINNED_REVISION = "cc37fe84fe08710e888ecc2eb5b468e41df74bca"
PINNED_REPO = "https://github.com/huggingface/speech-to-speech.git"

LOOPBACK_HOSTS = {"127.0.0.1", "localhost", "::1"}


def resolve_local_model_paths(models_dir: str | Path | None) -> dict[str, str]:
    """Inspect a local models directory for pre-downloaded weights.

    Recognized layout (e.g. from ModelScope / domestic downloads):
        <models_dir>/stt/parakeet -> Parakeet-TDT STT weights
        <models_dir>/llm/qwen3-4b -> Qwen3-4B MLX weights
        <models_dir>/tts/qwen3-6bit -> Qwen3-TTS 6-bit weights
    """
    if not models_dir:
        return {}
    base = Path(models_dir).expanduser()
    if not base.is_dir():
        return {}
    found: dict[str, str] = {}
    stt_path = base / "stt" / "parakeet"
    if stt_path.is_dir():
        found["stt_parakeet"] = str(stt_path)
    llm_path = base / "llm" / "qwen3-4b"
    if llm_path.is_dir():
        found["llm_qwen3"] = str(llm_path)
    tts_path = base / "tts" / "qwen3-6bit"
    if tts_path.is_dir():
        found["tts_qwen3"] = str(tts_path)
    return found


def venv_executable() -> Path:
    """The service binary inside the dedicated venv."""
    return VENV_DIR / "bin" / EXECUTABLE


def resolve_executable() -> str:
    """Locate the `speech-to-speech` console command: the dedicated venv's
    binary when installed there, otherwise whatever is on PATH."""
    venv_binary = venv_executable()
    if venv_binary.exists():
        return str(venv_binary)
    found = shutil.which(EXECUTABLE)
    if found is None:
        raise FileNotFoundError(
            f"'{EXECUTABLE}' is not installed. Run "
            f"`{sys.argv[0]} --install` first."
        )
    return found


def assert_loopback(host: str) -> None:
    """The local service is unauthenticated: never bind it outside loopback."""
    if host not in LOOPBACK_HOSTS:
        raise ValueError(
            f"host {host!r} is not loopback; the local Speech-to-Speech "
            "service is intentionally unauthenticated and must stay on "
            "127.0.0.1 / localhost / ::1."
        )


def install_command(*, revision: str | None = None) -> list[str]:
    """pip command that installs the service into its dedicated venv.

    Defaults to the upstream git HEAD: the published PyPI releases trail the
    CLI surface this launcher (and the protocol) target, and qwen-audio-agent's
    tested stack is the merged git revision too. Pass --pinned or --revision
    to pin a specific commit instead.
    """
    spec = (
        f"{PACKAGE} @ git+{PINNED_REPO}" if revision is None else
        f"{PACKAGE} @ git+{PINNED_REPO}@{revision}"
    )
    pip = str(VENV_DIR / "bin" / "pip")
    return [pip, "install", spec]


def _venv_python() -> str:
    """An interpreter the ML stack actually supports. The upstream stack
    (torch/mlx/nemo) lags new CPython releases, so an externally-managed
    3.14/3.13 on PATH is the wrong base even when the venv would accept it."""
    for candidate in ("python3.12", "python3.11", "python3.10", sys.executable):
        path = (
            sys.executable if candidate == sys.executable else shutil.which(candidate)
        )
        if path:
            return path
    return sys.executable


def ensure_venv() -> int:
    """Create the dedicated venv when missing. Returns a process exit code."""
    if (VENV_DIR / "bin" / "python").exists():
        return 0
    python = _venv_python()
    print(f"creating venv at {VENV_DIR} with {python} ...")
    return subprocess.call([python, "-m", "venv", str(VENV_DIR)])


def build_command(
    *,
    executable: str,
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    stt: str = DEFAULT_STT,
    llm_backend: str = DEFAULT_LLM_BACKEND,
    model: str = DEFAULT_LLM_MODEL,
    tts: str = DEFAULT_TTS,
    speaker: str | None = None,
    language: str | None = None,
    instruct: str | None = None,
    mac_optimal: bool = True,
    models_dir: str | Path | None = None,
) -> list[str]:
    """Assemble the foreground service command (pure, unit-testable)."""
    assert_loopback(host)
    local_paths = resolve_local_model_paths(models_dir)
    command = [
        executable,
        "--mode",
        "realtime",
        "--host",
        host,
        "--port",
        str(port),
    ]
    if mac_optimal:
        command.append("--mac-optimal-settings")
    if stt:
        command += ["--stt", stt]
        if stt == "parakeet-tdt" and "stt_parakeet" in local_paths:
            command += ["--parakeet_tdt_model_name", local_paths["stt_parakeet"]]
    if llm_backend:
        command += ["--llm_backend", llm_backend]
    if tts:
        command += ["--tts", tts]
        if tts == "qwen3" and "tts_qwen3" in local_paths:
            command += ["--qwen3_tts_model_name", local_paths["tts_qwen3"]]
    effective_model = (
        local_paths["llm_qwen3"]
        if (model == DEFAULT_LLM_MODEL and "llm_qwen3" in local_paths)
        else model
    )
    if effective_model:
        command += ["--model_name", effective_model]
    if speaker:
        command += ["--qwen3_tts_speaker", speaker]
    if language:
        command += ["--qwen3_tts_language", language]
    if instruct:
        command += ["--qwen3_tts_instruct", instruct]
    return command


def managed_args(
    *,
    stt: str = DEFAULT_STT,
    llm_backend: str = DEFAULT_LLM_BACKEND,
    model: str = DEFAULT_LLM_MODEL,
    tts: str = DEFAULT_TTS,
    speaker: str | None = None,
    language: str | None = None,
    instruct: str | None = None,
    mac_optimal: bool = True,
    models_dir: str | Path | None = None,
) -> list[str]:
    """Component selection for core's *managed* sidecar spawn.

    Deliberately excludes --mode/--host/--port: listen-core appends those
    itself (--mode realtime --ws_host <loopback> --ws_port <port>), matching
    the pinned revision's flag surface. Passing them here would collide with
    the arguments core appends.
    """
    local_paths = resolve_local_model_paths(models_dir)
    command: list[str] = []
    if mac_optimal:
        command.append("--mac-optimal-settings")
    if stt:
        command += ["--stt", stt]
        if stt == "parakeet-tdt" and "stt_parakeet" in local_paths:
            command += ["--parakeet_tdt_model_name", local_paths["stt_parakeet"]]
    if llm_backend:
        command += ["--llm_backend", llm_backend]
    if tts:
        command += ["--tts", tts]
        if tts == "qwen3" and "tts_qwen3" in local_paths:
            command += ["--qwen3_tts_model_name", local_paths["tts_qwen3"]]
    effective_model = (
        local_paths["llm_qwen3"]
        if (model == DEFAULT_LLM_MODEL and "llm_qwen3" in local_paths)
        else model
    )
    if effective_model:
        command += ["--model_name", effective_model]
    if speaker:
        command += ["--qwen3_tts_speaker", speaker]
    if language:
        command += ["--qwen3_tts_language", language]
    if instruct:
        command += ["--qwen3_tts_instruct", instruct]
    return command


def managed_environment(
    *,
    executable: str | None = None,
    stt: str = DEFAULT_STT,
    llm_backend: str = DEFAULT_LLM_BACKEND,
    model: str = DEFAULT_LLM_MODEL,
    tts: str = DEFAULT_TTS,
    speaker: str | None = None,
    language: str | None = None,
    instruct: str | None = None,
    mac_optimal: bool = True,
    models_dir: str | Path | None = None,
) -> dict[str, str]:
    """Environment that makes listen-core spawn and manage the sidecar itself.

    The app's sidecar launcher passes the app's whole environment through, so
    a process started with these variables makes core own spawn, `/v1/pool`
    readiness, and process-group shutdown. Endpoint/readiness/timeouts keep
    core's defaults unless the caller also sets the LLPLAYERNEXT_LOCAL_REALTIME_
    override variables.
    """
    resolved = executable or resolve_executable()
    args_json = json.dumps(
        managed_args(
            stt=stt,
            llm_backend=llm_backend,
            model=model,
            tts=tts,
            speaker=speaker,
            language=language,
            instruct=instruct,
            mac_optimal=mac_optimal,
            models_dir=models_dir,
        )
    )
    return {
        "LLPLAYERNEXT_LOCAL_REALTIME_EXECUTABLE": resolved,
        "LLPLAYERNEXT_LOCAL_REALTIME_ARGS_JSON": args_json,
    }


def managed_launch_command(
    app_binary: str,
    environment: dict[str, str],
) -> list[str]:
    """Launch the app with the managed-sidecar environment prefixed.

    Uses the `env` utility so the variables are visible to the app process
    and therefore to the listen-core sidecar it spawns.
    """
    return ["env", *[f"{key}={value}" for key, value in environment.items()], app_binary]


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Start the local Speech-to-Speech cascade service "
        f"({DEFAULT_ENDPOINT}). It owns VAD/STT/LLM/TTS on this machine; the "
        "listen backend connects over loopback without any API key.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify the service is installed instead of running it.",
    )
    parser.add_argument(
        "--install",
        action="store_true",
        help="pip install the service package (with Apple Silicon extras).",
    )
    parser.add_argument(
        "--pinned",
        action="store_true",
        help=f"With --install: pin the listen-core-audited revision "
        f"({PINNED_REVISION[:12]}...). Core's managed spawn appends the flag "
        "names that revision accepts; newer upstream moved to --host/--port.",
    )
    parser.add_argument(
        "--revision",
        default=None,
        metavar="GIT_REF",
        help="With --install: pin an arbitrary git revision instead of the "
        "latest PyPI release.",
    )
    parser.add_argument(
        "--managed",
        action="store_true",
        help="Launch the app with the managed-sidecar environment so "
        "listen-core spawns, readiness-checks and shuts down the service "
        "itself. Requires --app. Component selection flags below still apply.",
    )
    parser.add_argument(
        "--app",
        default=None,
        metavar="BINARY",
        help="With --managed: path to the app binary to launch.",
    )
    parser.add_argument("--host", default=DEFAULT_HOST, help="Loopback host.")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Loopback port.")
    parser.add_argument("--stt", default=DEFAULT_STT, help="STT backend name.")
    parser.add_argument(
        "--llm_backend",
        "--llm-backend",
        default=DEFAULT_LLM_BACKEND,
        help="LLM backend name (mlx-lm, transformers, ...).",
    )
    parser.add_argument("--model", default=DEFAULT_LLM_MODEL, metavar="NAME",
                        help="LLM model name on the service side.")
    parser.add_argument("--tts", default=DEFAULT_TTS, help="TTS backend name.")
    parser.add_argument("--speaker", default=None, help="Qwen3-TTS speaker name.")
    parser.add_argument("--language", default=None, help="Qwen3-TTS language.")
    parser.add_argument(
        "--instruct",
        default=None,
        help="Qwen3-TTS speaking instruction (style prompt).",
    )
    parser.add_argument(
        "--models-dir",
        "--models_dir",
        default=str(DEFAULT_LOCAL_MODELS_DIR),
        metavar="PATH",
        help="Directory containing pre-downloaded model weights (defaults to "
        f"{DEFAULT_LOCAL_MODELS_DIR}; pass empty string to disable).",
    )
    parser.add_argument(
        "--no-mac-optimal",
        action="store_true",
        help="Do not pass --mac-optimal-settings; supply explicit flags.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)

    if args.install:
        if args.pinned and args.revision:
            print("--pinned and --revision are mutually exclusive", file=sys.stderr)
            return 2
        venv_status = ensure_venv()
        if venv_status != 0:
            return venv_status
        revision = PINNED_REVISION if args.pinned else args.revision
        command = install_command(revision=revision)
        print(f"$ {' '.join(command)}")
        return subprocess.call(command)

    try:
        executable = resolve_executable()
    except FileNotFoundError as error:
        print(str(error), file=sys.stderr)
        return 2

    models_dir = args.models_dir if args.models_dir else None

    if args.check:
        print(f"executable: {executable}")
        print(f"endpoint:   {DEFAULT_ENDPOINT}")
        print(f"readiness:  {DEFAULT_READINESS}")
        local_paths = resolve_local_model_paths(models_dir)
        if local_paths:
            print("local models:")
            for k, v in sorted(local_paths.items()):
                print(f"  {k}: {v}")
        if not args.managed:
            print("The service must be running and its /v1/pool must report a "
                  "free unit before the app can start a conversation.")
        return 0

    if args.managed:
        if not args.app:
            print("--managed requires --app <path-to-app-binary>", file=sys.stderr)
            return 2
        environment = managed_environment(
            executable=executable,
            stt=args.stt,
            llm_backend=args.llm_backend,
            model=args.model,
            tts=args.tts,
            speaker=args.speaker,
            language=args.language,
            instruct=args.instruct,
            mac_optimal=not args.no_mac_optimal,
            models_dir=models_dir,
        )
        print("Managed mode: listen-core will spawn, probe (/v1/pool) and "
              "shut down the service itself.")
        print("NOTE: core appends --ws_host/--ws_port (the pinned revision's "
              f"flag surface, {PINNED_REVISION[:12]}...). A newer "
              "speech-to-speech install that only accepts --host/--port will "
              "fail managed startup; use --install --pinned for the audited "
              "surface.")
        for key, value in environment.items():
            print(f"  {key}={value}")
        command = managed_launch_command(args.app, environment)
        print("$ " + " ".join(command))
        return subprocess.call(command)

    try:
        command = build_command(
            executable=executable,
            host=args.host,
            port=args.port,
            stt=args.stt,
            llm_backend=args.llm_backend,
            model=args.model,
            tts=args.tts,
            speaker=args.speaker,
            language=args.language,
            instruct=args.instruct,
            mac_optimal=not args.no_mac_optimal,
            models_dir=models_dir,
        )
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2

    print("$ " + " ".join(command))
    print("Press Ctrl-C to stop the service.")
    return subprocess.call(command)


if __name__ == "__main__":
    raise SystemExit(main())