# Development preview distribution

The current preview is `v0.7.0-dev.1`, for macOS on Apple Silicon. Build it
from a clean committed source tree with the prepared third-party runtime inputs:

```sh
./dev release --output-dir /path/to/an-empty/output-directory
```

The command builds Core, Gen and App from one isolated export of the commit,
then runs the packaged-app smoke checks. It writes internal build outputs under
`core/`, `gen/`, `locks/` and `app/`. Only upload the three files in
`distribution/`:

- `Listen-v0.7.0-dev.1-macos-arm64.zip`
- `Listen-v0.7.0-dev.1-macos-arm64.release.json`
- `SHA256SUMS`

`SHA256SUMS` covers the zip and its release manifest. Verify it from the
distribution directory before installation:

```sh
shasum -a 256 -c SHA256SUMS
```

The smoke test extracts and launches the package outside the source tree, with
an isolated temporary home/support directory and a minimal system `PATH`. It
uses copied fixture media and a temporary database; the App process cannot
resolve development binaries or locks from the checkout.

The App bundle uses numeric macOS version metadata `0.7.0` and build `9`; the
development suffix remains in the GitHub tag, asset name and embedded
`ListenReleaseVersion` value. The release manifest records the exact source
commit, artifact digest, signing status, host used for packaged smoke testing,
and minimum OS computed from the bundled arm64 Mach-O files. The current
third-party Whisper and FFmpeg executables require macOS 26.0, so this package
does not support earlier macOS versions even though some Flutter frameworks
declare older minimums. This preview was packaged and smoke-tested on macOS
26.6.2 arm64.

The app is ad-hoc signed and not notarized. After checking the downloaded
checksum, extract the zip and move `listen.app` to Applications. If macOS blocks
the first open, go to **System Settings → Privacy & Security → Open Anyway** for
Listen and confirm. See [Apple's instructions](https://support.apple.com/en-us/102445).
Do not disable Gatekeeper or remove quarantine attributes.

No Whisper model weights are included. Starting a free or anchored realtime
conversation prompts only when no compatible local model is installed. The
offered `base` model (`whisper.cpp:base@main`) is 147,951,465 bytes (about 148 MB
decimal), downloaded from
`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin` and
checked against SHA-256
`60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe`.
Nothing downloads until the user chooses **Download** in the confirmation
prompt. Canceling leaves the conversation unopened; the original request
continues after Core verifies that the model is installed. The model is public
and does not require a paid provider account.

The Gen zipapp is bundled, but its Python 3.11-or-newer interpreter and required
`pypdf` dependency are not. Install those separately to use Gen content
workflows; PDF text extraction needs `pypdf`. Optional local TTS, OCR and
speech-generation dependencies or their models are separate opt-ins. Ordinary
listening and playback do not require Python or a Whisper model. Hosted
generation providers may need their own credentials and are optional. The app
stores its managed data in the user's Application Support directory; installing
the preview does not require deleting existing Listen data.
