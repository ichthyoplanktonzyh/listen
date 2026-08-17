# Complete App Local Testing

This runbook starts the Flutter desktop client together with the local
`listen-core` HTTP sidecar on macOS Apple Silicon.

An identical copy lives in both `listen-core` and `listen-app`. Changes to this
runbook must be made in coordinated PRs so the two copies remain identical.

## What “complete app” means

The complete local app consists of:

- the Flutter macOS client from `listen-app`;
- one `api-http` sidecar from `listen-core`;
- the contract and runtime versions pinned by `listen-app/backend.lock.json`;
- local loopback communication authenticated with the sidecar's one-time token.

The client normally starts and stops the sidecar automatically. Do not start a
second backend manually for the pinned-release workflow.

## Prerequisites

- macOS on Apple Silicon;
- Flutter with macOS desktop support and a working Xcode toolchain;
- Python 3;
- GitHub CLI authenticated with access to the private repositories;
- local `listen-app` and `listen-core` checkouts.

Check the environment:

```sh
flutter doctor -v
flutter devices
gh auth status
```

`flutter devices` must list `macOS (desktop)`.

The examples below use the owner's current checkout paths. Change them if the
repositories live elsewhere:

```sh
listen_app_repo=/Users/shadow/listen-app
listen_core_repo=/Users/shadow/listen-core
```

## Recommended: test the pinned release

This is the reproducible product test. It uses the exact contract and runtime
declared in `backend.lock.json`.

### First setup or lock-file update

```sh
cd "$listen_app_repo"
flutter pub get
GITHUB_TOKEN="$(gh auth token)" \
  python3 tool/backend_artifacts.py install
python3 tool/backend_artifacts.py verify
```

The GitHub token is passed only to the installer process; it is not exported,
written to the repository, or stored by the script.

### Start the app

Always run from the `listen-app` root so sidecar discovery can find
`.backend/runtime/bin/api-http`:

```sh
cd "$listen_app_repo"
flutter run -d macos
```

On startup the client:

1. finds the pinned sidecar under `.backend/runtime/bin/api-http`;
2. starts it on a random loopback port;
3. reads and validates the API, contract, and runtime handshake;
4. uses the returned one-time bearer token for local API requests;
5. terminates the child sidecar when the app closes.

### Later runs

The artifact download is not required again while `backend.lock.json` and the
installed `.backend/` contents remain unchanged:

```sh
cd "$listen_app_repo"
python3 tool/backend_artifacts.py verify
flutter run -d macos
```

## Test unreleased local backend code

Use this workflow when changing `listen-core` before publishing a new immutable
runtime release:

```sh
cd "$listen_core_repo"
./scripts/validate-contracts.sh
cargo build -p api-http

cd "$listen_app_repo"
LLPLAYERNEXT_API_BINARY="$listen_core_repo/target/debug/api-http" \
  flutter run -d macos
```

The app still validates the startup versions. If local core introduces an
incompatible contract major, the existing app must reject it; coordinate the
contract and app migration instead of bypassing that check.

### Test the pinned local generator bundle

The package journey runs exactly one generator: the `listen-gen` release
bundle pinned by the committed `listen_gen.lock.json`. The App does **not**
accept a source checkout, a `PYTHONPATH`, or an arbitrary `listen-gen`
executable. It automatically resolves the exact hash-pinned release from the
app bundle, `.listen-gen`, or the standard sibling repository release folder:

```sh
python3 tool/listen_gen_artifacts.py verify
flutter run -d macos
```

Requirements and behavior:

- the `.release.json` manifest and its `.pyz` artifact must live in the **same
  directory**; the App resolves the artifact beside the manifest;
- before every run the App verifies the committed lock, the manifest's file
  hash, and the artifact's size and hash against the lock — any mismatch fails
  the run with a stable, non-retryable code and never launches anything;
- the `.pyz` still requires Python 3.11+ on the machine; the App probes fixed
  local locations and launches the compatible interpreter by absolute path so
  Finder's system-only `PATH` cannot select macOS Python 3.9;
- tool and provider arguments are resolved by the App and are never stored in
  `backend.lock.json`;
- without a connected Core, pinned Gen bundle, complete local media toolchain,
  and a local media path, the UI names the one missing prerequisite;
- cleanup of descendants during a valid cancellation remains part of the
  generator contract.

To produce the bundle locally, build it from the pinned `listen-gen` source:

```sh
cd /path/to/listen-gen
python3 tools/release_bundle.py build \
  --source-commit c05369770d7f4af98d62d0407f67767c905bbb9d \
  --output-parent dist

cd /path/to/listen-app
python3 tool/listen_gen_artifacts.py verify
```

When the repositories are not siblings, install the built bundle into the
App's ignored local artifact directory once:

```sh
python3 tool/listen_gen_artifacts.py install \
  --manifest /path/to/listen-gen-0.5.0.release.json
```

### Real ASR with the whisper.cpp command provider

Real ASR uses the whisper.cpp provider through the same pinned bundle. The App
resolves `whisper-cli`, `ffmpeg`, and `ffprobe` from the bundled pinned runtime
or standard local tool locations, and selects the largest installed Whisper
model from `~/Library/Application Support/listen/models/whisper/`:

```sh
python3 tool/backend_artifacts.py verify
python3 tool/listen_gen_artifacts.py verify
flutter run -d macos
```

The model file is a whisper.cpp GGML model such as `ggml-base.bin`.

### R1 tool ownership: whisper-cli, ffmpeg, ffprobe

At R1 none of these three tools belongs to a single repository, so none of them
is "Gen-only":

- `backend.lock.json` verifies the pinned Core runtime artifact, and that
  artifact bundles `whisper-cli`, `ffmpeg`, and `ffprobe` beside `api-http`
  (see `.backend/runtime/manifest.json`, `tool/build-macos-release.sh`, and
  `tool/verify-macos-release.sh`). Core still needs `whisper-cli` for
  learner-recording transcription, and `ffmpeg`/`ffprobe` for the sound-line
  and other Core media paths.
- The app uses `ffmpeg`/`ffprobe` directly through its own helpers
  (`ExternalTools`, `FfprobeMediaProbe`, the practice file service) for media
  probing, embedded-text subtitle extraction, and online acquisition —
  independent of the generator.
- `listen-gen` *declares* the tool roles its providers require in the release
  manifest (`provider_requirements`, e.g. `whisper-cpp` requires `ffprobe`,
  `ffmpeg`, `whisper-cli`, `whisper-model`). The app only hands resolved tool
  paths to it (`--whisper-cli`, `--ffprobe-command`, `--ffmpeg-command`) after
  both the pinned Gen bundle and the pinned Core artifact verify byte-for-byte.

The verification claims stop exactly at those full-artifact SHA-256 checks
(Core runtime archive via `backend.lock.json`, Gen bundle plus manifest via
`listen_gen.lock.json`). Nothing here asserts a repository-exclusive role for
any tool; "shared, verified bytes" is the whole claim.

### Local three-repository round trip

To exercise the full `pinned .pyz -> .listenpkg -> Core import` path against a
real Core, use the dedicated script. It builds both external repositories at
their pinned commits in a throwaway directory, runs the focused integration
test, and cleans up after itself. Both checkouts must be clean and exactly at
the commits recorded by App. The script resolves App dependencies offline from
the caller's existing `PUB_CACHE`, while runtime `HOME` remains isolated. A
missing cached package is therefore an early setup failure rather than an
implicit network fetch.

```sh
LISTEN_CORE_REPO=/absolute/path/to/listen-core \
LISTEN_GEN_REPO=/absolute/path/to/listen-gen \
  ./tool/verify_local_content_package_roundtrip.sh
```

Success is reported only after Flutter's JSON event report proves the named
roundtrip test executed once, was not skipped, passed, and the runner finished
successfully. Gen build/verify, Core build, dependency setup, test execution,
report validation, and post-run external-checkout cleanliness are fail-closed.
This command uses fixture media/provider data only and never a live model or
credential.

Inspect the same three-repository locks without building anything:

```sh
python3 tool/repo_status.py --strict

# Explicit paths override worktree-aware discovery. LISTEN_APP_REPO,
# LISTEN_CORE_REPO, and LISTEN_GEN_REPO provide equivalent env overrides.
python3 tool/repo_status.py --strict \
  --app-repo /absolute/path/to/listen-app \
  --core-repo /absolute/path/to/listen-core \
  --gen-repo /absolute/path/to/listen-gen
```

## Manual smoke checklist

After the main window opens:

1. Confirm startup completes without a sidecar or compatibility error.
2. Open a local supported media file.
3. Load or drop the primary subtitle; add a secondary subtitle when relevant.
4. Confirm play, pause, seek, subtitle synchronization, offset, and sentence
   loop behavior.
5. Exercise one backend-backed path relevant to the change, such as subtitle
   import, vocabulary persistence, dictionary lookup, diagnosis, or job
   progress/cancellation.
6. Exercise loading, empty, failure, retry, cancellation, and degraded states
   affected by the change.
7. Close the app normally and confirm no newly launched `api-http` process is
   left behind.

Use focused journey checks in addition to this baseline when the changed
feature has its own phase or acceptance document.

## Logs and diagnostics

Backend logs:

```sh
tail -f "$HOME/Library/Logs/listen/core.log"
```

Flutter and client logs remain visible in the terminal running `flutter run`.
For a clean rerun, close the app and start the command again; do not delete user
data unless the test explicitly requires a clean-state scenario.

## Common failures

### `Local API sidecar not found`

Run the pinned artifact installer from the app repository, or set
`LLPLAYERNEXT_API_BINARY` to a built local `api-http` binary.

### Private release download returns 404 or 403

Confirm `gh auth status` uses an account with repository access, then run the
installer with the process-local `GITHUB_TOKEN` command shown above.

### Installed artifact or SHA-256 mismatch

Do not edit `.backend/`. Run the installer again. If verification still fails,
inspect `backend.lock.json` and the immutable release assets rather than
weakening the verifier.

### Incompatible API, contract, or runtime version

Use the release pinned by `backend.lock.json`, or update the app and lock file
through the cross-repository contract workflow. Do not bypass startup version
negotiation.

### macOS is not listed by Flutter

Run:

```sh
flutter config --enable-macos-desktop
flutter doctor -v
```

Resolve the reported Flutter/Xcode issue before testing the product.

## Pre-review automated checks

App-side changes:

```sh
cd "$listen_app_repo"
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'
```

Core-side changes:

```sh
cd "$listen_core_repo"
./scripts/test.sh --rust --strict
./scripts/validate-contracts.sh
python3 -m unittest scripts/test_release_artifacts.py
```

Run only the checks relevant to the changed boundary while iterating, then
record the exact completed checks in the PR. Paid/live-model tests remain
explicit opt-in.
