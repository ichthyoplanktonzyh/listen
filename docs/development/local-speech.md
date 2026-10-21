# Optional local speech service

The implemented `local_cascade_realtime` provider connects Core to a local
VAD/STT/LLM/TTS service over loopback. Gen does not participate in realtime
voice. This is optional existing functionality; its main-branch scope will be
reviewed under the [current roadmap](../../ROADMAP.md).

## Setup

Run from the repository root. Inspect the current launcher's options first:

```sh
python3 app/tool/run_local_speech_to_speech.py --help
python3 app/tool/run_local_speech_to_speech.py --check
```

Installation and startup are explicit opt-ins. They install a separate service
environment and may download several GB of model weights. They are not part
of ordinary development setup or automated tests.

```sh
python3 app/tool/run_local_speech_to_speech.py --install --pinned
python3 app/tool/run_local_speech_to_speech.py
```

Use the launcher's pinned service revision for compatibility with Core's
managed-process flags. The revision and arguments are implemented in
[the launcher](../../app/tool/run_local_speech_to_speech.py) and
[Core local runtime](../../core/crates/local-runtime/).

The launcher supports explicit provider/model choices and a `--models-dir`
for pre-downloaded weights. Inspect `--help` and local configuration rather
than assuming that models or runtimes are bundled with the application.

## App connection

The service exposes:

- `ws://127.0.0.1:8765/v1/realtime` for voice sessions;
- `http://127.0.0.1:8765/v1/pool` for readiness.

In App settings, select the local speech protocol and loopback endpoint, save
the profile, then select it when starting a conversation. No provider API key
is required for this local adapter. A ready pool reports an initialized
available pipeline; a full spoken turn still needs a separate manual check.

The launcher also supports `--managed --app /absolute/path/to/app-binary`.
Core then owns service spawn, readiness probing, and shutdown. Use an actual
App executable path, not a bundle directory. Keep the service loopback-only;
it is not an authenticated hosted endpoint.

## Troubleshooting

- Unreachable endpoint: start the service and check its address.
- Empty/busy pool: inspect service stderr and model initialization.
- Managed startup failure: verify the pinned revision and accepted CLI flags.
- Slow startup or memory failure: inspect model paths and service requirements.

Do not run installation, model download, or live inference as a documentation
check. The current [distribution guide](dev-preview-distribution.md) describes
which runtimes are included in the desktop preview.
