# Listen Development

Listen is one repository with Flutter `app/`, Rust `core/`, Python `gen/`, and
project documentation. A feature, its contract changes, and its adapters ship
through one branch and review. See [decision 0005](decisions/0005-single-repository-development.md).

## Prerequisites and setup

The supported desktop release target is macOS Apple Silicon. Install Flutter
with macOS desktop support, Xcode, Rust matching `core/Cargo.toml`, and Python
3.11 or newer for Gen. The root launcher resolves the Python runtime rather
than relying on macOS's older system Python. Use `./dev --help` for command and
configuration details.

From the repository root:

```sh
./dev setup
./dev status
./dev run
```

Setup resolves Flutter dependencies and prepares an independent Python
environment under `gen/.venv`. The small root test dependency set in `tools/requirements-dev.txt` is installed
in that environment too (including Chinese tokenization for Core checks).
Heavy model/provider extras are opt-in; ordinary
setup and fixture tests do not download models or call paid providers. Native
commands still run from their module directory.

After setup, run/check/test/release use the prepared dependencies without
implicit pip installs. The source-development launcher builds Core and a Gen bundle from the same
identified source snapshot, prepares a matching development lock, and starts
Flutter. Tracked edits and untracked source are supported; ignored build output
and private environment files are excluded from the snapshot. This workflow
needs no component release, old repository checkout, or manually edited pin.

Core runs as an authenticated loopback sidecar. App owns startup/exit and checks
the API/contract handshake. Gen remains an independent process with bounded
progress/cancellation. Debug builds accept explicitly supplied current-source
artifacts; release builds use their embedded generated lock and bundled bytes.

## Verification

```sh
./dev check
./dev test integration
```

The shared entry points run native gates with the correct module working
directories. Use focused module commands while iterating:

| Module | Checks |
|---|---|
| App | `flutter analyze --fatal-infos --fatal-warnings`; `flutter test`; `python3 -m unittest discover -s tool -p 'test_*.py'` |
| Core | `./scripts/test.sh --rust --strict`; `./scripts/validate-contracts.sh`; `python3 -m unittest scripts/test_release_artifacts.py` |
| Gen | `.venv/bin/python -m unittest discover -s tests -v` |

Run the Gen command from `gen/` and the other native commands from their module
root. For direct Core shell scripts, first activate `gen/.venv` from the root
(`source gen/.venv/bin/activate`) so their internal `python3` is Python 3.11+. Contract, persistence and packaging changes retain their focused tests.
The integration gate builds one source snapshot and proves fixture-based
production, package installation/adoption, and App consumption. Named tests
must actually execute and pass; skipped tests or failed build stages do not
count as success. No live model credentials are needed.

There is currently no checked-in GitHub Actions workflow running these checks.
Record the exact local commands and outcomes in the PR. A job that never starts
is not validation. Live/paid/ignored model tests require explicit authorization.

## Product releases

```sh
./dev release
```

Release starts from a clean Git commit and builds all product modules from an
isolated export of that committed tree, excluding ignored local files. Core contracts/runtime and the Gen bundle receive source and
hash manifests; generated App product locks identify these exact outputs.
Locks and manifests are emitted under ignored output directories and shipped
with the product as needed. Do not commit an internal pin update after building
or mutate a published artifact to reuse a version/tag.

The macOS runtime needs the prepared third-party tool bundle under
`core/third_party/runtime/macos-arm64/`, matching
`core/third_party/runtime/manifest.json`, plus its license notices. These local
binary inputs are not Git source and are never committed. The preparation
scripts and notices under `core/third_party/runtime/` remain the authority for
those inputs. Release verification must include the packaged runtime and the
App outside the checkout; a successful compile alone is insufficient.

The old committed `app/backend.lock.json` and `app/listen_gen.lock.json` retain
the split-release baseline for historical diagnostics. They do not determine
current-source development or the new product release. Do not substitute
unverified binaries or disable handshake/hash verification to make a build pass.

## Manual desktop smoke

After launching the app:

1. Check startup and the absence of sidecar/compatibility errors.
2. Open a local supported document or media fixture; verify reading or
   playback, pause, seek, subtitle timing and sentence looping as applicable.
3. Exercise the changed Core-backed operation and its loading/empty/error/
   retry/cancel states. For generation changes, run a fixture request and check
   progress, package adoption and the resulting composition.
4. Close the app and verify its sidecar/child processes exit.
5. Repeat the relevant flow using the packaged application outside the source
   tree when changing runtime assembly or release scripts.

Core logs remain in `~/Library/Logs/listen/core.log`; Flutter logs are visible
in the launcher terminal. Do not delete learner data to repair a development
setup. Use isolated test data for fixtures and migration proofs.

## Documentation and Git

Root model/glossary/context/journey documents own product semantics. Root
`STATE.md` and `ROADMAP.md` own active project coordination. Module codebase
notes describe local implementation; old phase plans, ADRs and repository
handoffs are historical evidence. This migration does not implement the newer
Complete Learning Material product model.

Use one branch/PR per coherent change, including all affected modules. Preserve
existing user changes, use focused Conventional Commits, and update changelogs
only during a release. Do not merge a PR or archive the former repositories
without the owner's authorization. Their issues, releases, PR links and local
worktrees remain valid history. Import provenance and validation are recorded
in [the migration record](docs/development/monorepo-migration.md).
