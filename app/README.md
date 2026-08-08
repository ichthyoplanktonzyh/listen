# listen-app

Formal macOS Apple Silicon desktop client using Flutter and fvp/libmdk.

The UI repository is independently versioned from `listen-core`. Its exact API
contract and backend runtime are pinned in `backend.lock.json`; no sibling
checkout or moving backend branch is read during build.

## Run the complete app locally

The complete setup, local-core workflow, smoke checklist, logs, and
troubleshooting guide lives in
[`docs/development/full-app-local-testing.md`](docs/development/full-app-local-testing.md).

Run from the `listen-app` repository root so the app can find the pinned
sidecar under `.backend/`.

First setup, or after `backend.lock.json` changes:

```sh
flutter pub get
GITHUB_TOKEN="$(gh auth token)" python3 tool/backend_artifacts.py install
python3 tool/backend_artifacts.py verify
```

The token is passed only to the installer process. Then start the complete
desktop app:

```sh
flutter run -d macos
```

The Flutter client automatically starts the installed `api-http` sidecar,
reads its loopback address and one-time token from the startup handshake, and
stops it when the app closes. Backend logs are written to
`~/Library/Logs/listen/core.log`.

For later runs, verify and start:

```sh
python3 tool/backend_artifacts.py verify
flutter run -d macos
```

To test current, unreleased local backend code instead of the pinned release:

```sh
cd /Users/shadow/listen-core
cargo build -p api-http
cd /Users/shadow/listen-app
LLPLAYERNEXT_API_BINARY=/Users/shadow/listen-core/target/debug/api-http \
  flutter run -d macos
```

For private core releases, provide a read token as `GITHUB_TOKEN`, or pass
explicit local archives with `--contract-archive` and `--runtime-archive`.

The player adapter, position events, subtitle cursor, seeking, offset, and
sentence loop all run locally in the client. The loopback sidecar owns subtitle
import, persistence, progress, word state, dictionary, and diagnosis services.

## Enhanced desktop workflow

- Use **Primary subtitle** for the interactive learning track.
- Use **Secondary subtitle** for the second independently synchronized text
  track.
- Drop a media file plus up to two SRT/VTT files onto the window to open them
  together.
- Use the overflow menu to import a supported embedded text subtitle, configure
  subtitle appearance/layout, or export logs.
- Use **Open URL** to resolve and play, or explicitly download, a legally
  accessible page URL with an installed `yt-dlp`. Downloads continue in the
  background while the player remains usable; the bundled `ffmpeg` merges
  separate video and audio streams into one final MP4.

Embedded text-subtitle extraction requires installed `ffprobe` and `ffmpeg`.
The application auto-detects Homebrew paths, or explicit paths can be entered
in **Settings**. OpenSubtitles and bitmap subtitle display/OCR interaction are
deferred.

Verification:

```sh
flutter analyze --fatal-infos --fatal-warnings
flutter test
python3 -m unittest discover -s tool -p 'test_*.py'
tool/build-macos-release.sh
tool/verify-macos-release.sh
```

The discovery command is the single Python verification entry point; it
includes backend artifact, cross-repository status, and roundtrip report/gate
regressions. The real three-repository rebuild remains explicit:

```sh
LISTEN_CORE_REPO=/absolute/path/to/listen-core \
LISTEN_GEN_REPO=/absolute/path/to/listen-gen \
  tool/verify_local_content_package_roundtrip.sh
```
