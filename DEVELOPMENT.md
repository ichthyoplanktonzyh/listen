# Listen Development

Run shared commands from the repository root. App, Core, and Gen are built
from the same source snapshot and integrated through one branch and review.

## Setup and run

Install Flutter with macOS desktop support, Xcode, Rust matching
`core/Cargo.toml`, and Python 3.11+. The desktop release target is Apple Silicon;
the bundled native tools currently require macOS 26+.

```sh
./dev setup
./dev status
./dev run
```

Setup resolves Flutter dependencies and prepares `gen/.venv`, including the
small shared test dependencies. Heavy providers and models are opt-in. Later
run/check/test/release commands use the prepared environment without implicit
pip installation. Use `./dev --help` for command options and environment overrides.

Development builds Core and Gen from the current working-tree snapshot,
generates matching App locks, and launches Flutter. Tracked changes and
untracked source are included; ignored build output, environments, and private
files are excluded. See [runtime architecture](docs/architecture/runtime.md).

## Verification

```sh
./dev check
./dev test integration
```

Focused checks run from their module directory:

| Module | Commands |
|---|---|
| App | `flutter analyze --fatal-infos --fatal-warnings`; `flutter test`; `python3 -m unittest discover -s tool -p 'test_*.py'` |
| Core | `./scripts/test.sh --rust --strict`; `./scripts/validate-contracts.sh`; `python3 -m unittest scripts/test_release_artifacts.py` |
| Gen | `.venv/bin/python -m unittest discover -s tests -v` |
| Root tooling | `gen/.venv/bin/python -m unittest tools.test_dev` from the root |

For direct Core scripts, activate `gen/.venv` from the root first so internal
`python3` calls use Python 3.11+. Use deterministic providers and isolated data;
live/paid inference and model downloads require explicit authorization.

Interface changes run the model-free integration gate. It exercises Gen
production, Core package installation/adoption, and App consumption from one
source snapshot. A skipped journey or failed prerequisite is not a pass.
There is no checked-in GitHub Actions workflow running these gates; report
actual local commands and results.

[App UI checks](docs/development/app-ui.md) and
[Gen development](docs/development/gen.md) cover focused workflows.

## Product packaging

```sh
./dev release --output-dir /path/to/an-empty/output-directory
```

Release requires a clean committed tree and builds from an isolated export.
Core contracts/runtime and Gen bundles carry the same source identity and
artifact hashes. App locks are generated for those outputs and verified at
startup. Existing committed component locks are compatibility inputs; do not
hand-edit them to assemble a current-source product.

Prepare native tools under `core/third_party/runtime/macos-arm64/` using its
build scripts and `manifest.json`. Keep binary inputs out of Git. Preserve
[third-party notices](core/third_party/runtime/THIRD_PARTY_NOTICES.md).

The release command checks script syntax, builds the modules, signs the app,
verifies the extracted package, audits Mach-O architecture/minimum OS, and
creates the distribution assets. Compilation alone is insufficient. Published
artifacts are immutable. See [distribution](docs/development/dev-preview-distribution.md)
for asset names, installation, and runtime limitations.

## Manual smoke

Use isolated fixtures and a temporary database; do not delete learner data.

1. Launch with a fresh isolated store and check the authenticated Core
   startup/compatibility handshake. This scope-reduction stage does not
   support upgrading databases from the broader implementation.
2. Open a supported audio/video fixture. Check playback, subtitles, seeking,
   contextual help, and the operation changed by the task.
3. Exercise loading, empty, unavailable, error, retry, and cancellation states.
   For production changes, verify progress, package adoption, and reopening.
4. Close the app and confirm child processes exit.
5. For packaging changes, repeat using the extracted product outside source.

Core logs are in `~/Library/Logs/listen/core.log`; Flutter logs appear in the
launcher terminal. Preserve unrelated work. Use a `codex/` branch, focused
commits, and a coherent PR; merging requires owner authorization.
