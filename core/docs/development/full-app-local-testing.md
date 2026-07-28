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
python3 -m unittest tool/test_backend_artifacts.py
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
