#!/usr/bin/env bash
#
# Real three-repository round trip for the local listen-gen and listen-core
# checkouts.
#
# Builds the local Gen bundle and the local Core `api-http` at their current
# HEAD in a throwaway directory, then runs the focused integration test that
# drives:
#
#   local .pyz  ->  Content Package v3  ->  Core installation (candidate) -> adoption
#
# It mutates neither external repository, downloads no model, runs no Whisper,
# touches no network, and updates no lock (the production lock files keep
# their committed identities; the probe derives an equivalent lock from the
# freshly built manifest). Every generated artifact lives under a temporary
# directory that is removed on exit.
#
# Required environment:
#   LISTEN_CORE_REPO   absolute path to a listen-core checkout
#   LISTEN_GEN_REPO    absolute path to a listen-gen checkout
#
# Each checkout may be dirty. A dirty working tree is never built as if its
# HEAD were the content: the script materializes an isolated snapshot of the
# working-tree contents (tracked edits plus untracked source, minus build
# artifacts) into a throwaway git repo and builds from that snapshot commit,
# so the source commit recorded in the Gen manifest is the actual content
# that was built, never a bare dirty HEAD.
#
set -euo pipefail

readonly EXPECTED_MEDIA_TEST="local Gen bundle to local Core round trips through capability production, installation, and adoption"
readonly EXPECTED_DOCUMENT_TEST="a document material produces listen through the fake TTS provider and its derived audio resolves from the adopted composition through Core"
readonly EXPECTED_MATRIX_TEST="the Gen/Core/App matrix keeps one adopted package shape across document and media families"
readonly EXPECTED_RICH_TEST="a video subtitle with fragmented cues lands as one complete sentence with every rich timeline"
readonly EXPECTED_RENDER_TEST="Core-adopted compositions render honest audio and text surfaces for document, audio, and video"

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "verify-roundtrip: $*" >&2
  exit 1
}

# Tests inject a stage runner so failure propagation can be proven without
# rebuilding Core. Production never sets this variable.
run_stage() {
  local stage="$1"
  shift
  if [ -n "${VERIFY_ROUNDTRIP_STAGE_RUNNER:-}" ]; then
    "$VERIFY_ROUNDTRIP_STAGE_RUNNER" "$stage" "$@"
  else
    "$@"
  fi
}

: "${LISTEN_CORE_REPO:?set LISTEN_CORE_REPO to an absolute listen-core path}"
: "${LISTEN_GEN_REPO:?set LISTEN_GEN_REPO to an absolute listen-gen path}"

GEN_PYTHON="${LISTEN_GEN_PYTHON:-$LISTEN_GEN_REPO/.venv/bin/python}"
if [ -z "${VERIFY_ROUNDTRIP_STAGE_RUNNER:-}" ]; then
  [ -x "$GEN_PYTHON" ] || fail "LISTEN_GEN_PYTHON is not an executable Python >=3.11 runtime: $GEN_PYTHON"
fi
if [ -z "${VERIFY_ROUNDTRIP_STAGE_RUNNER:-}" ] && ! "$GEN_PYTHON" - <<'PY'
import sys
if sys.version_info < (3, 11):
    raise SystemExit("listen-gen E2E requires Python >=3.11")
try:
    import pypdf  # noqa: F401
except ImportError as error:
    raise SystemExit("listen-gen E2E requires the Gen PDF dependency pypdf") from error
PY
then
  fail "listen-gen PDF fixture dependencies are unavailable in $GEN_PYTHON"
fi

[ -d "$LISTEN_CORE_REPO" ] || fail "LISTEN_CORE_REPO does not exist: $LISTEN_CORE_REPO"
[ -d "$LISTEN_GEN_REPO" ] || fail "LISTEN_GEN_REPO does not exist: $LISTEN_GEN_REPO"

check_repo() {
  local repo="$1" name="$2"
  if ! head="$(git -C "$repo" rev-parse HEAD)"; then
    fail "$name is not a readable Git checkout: $repo"
  fi
  if ! status="$(git -C "$repo" status --porcelain)"; then
    fail "cannot inspect $name working tree: $repo"
  fi
}

# Materialize an isolated source snapshot of a possibly-dirty checkout.
# Prints the directory to build from and records the snapshot commit in
# $snapshot_sha (empty when the checkout was clean).
snapshot_workspace() {
  local repo="$1" name="$2" target="$3"
  local status
  if ! status="$(git -C "$repo" status --porcelain)"; then
    fail "cannot inspect $name working tree: $repo"
  fi
  if [ -z "$status" ]; then
    snapshot_sha=""
    printf '%s\n' "$repo"
    return 0
  fi
  mkdir -p "$target"
  git -C "$repo" archive HEAD | tar -x -C "$target"
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ -f "$repo/$path" ]; then
      mkdir -p "$target/$(dirname "$path")"
      cp "$repo/$path" "$target/$path"
    else
      rm -f "$target/$path"
    fi
  done < <(git -C "$repo" diff --name-only HEAD)
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      dist/*|target/*|.dart_tool/*|build/*|__pycache__/*|*.pyc) continue ;;
    esac
    mkdir -p "$target/$(dirname "$path")"
    cp "$repo/$path" "$target/$path"
  done < <(git -C "$repo" ls-files --others --exclude-standard)
  git -C "$target" init -q
  git -C "$target" config user.email "roundtrip@localhost"
  git -C "$target" config user.name "listen roundtrip"
  git -C "$target" add -A
  git -C "$target" commit -q -m "isolated snapshot of dirty $name working tree"
  snapshot_sha="$(git -C "$target" rev-parse HEAD)"
  echo "verify-roundtrip: $name working tree is dirty; building from an isolated snapshot of its contents (snapshot $snapshot_sha)" >&2
  printf '%s\n' "$target"
}

check_repo "$LISTEN_CORE_REPO" "listen-core"
check_repo "$LISTEN_GEN_REPO" "listen-gen"
readonly CORE_INITIAL_HEAD="$(git -C "$LISTEN_CORE_REPO" rev-parse HEAD)"
readonly GEN_INITIAL_HEAD="$(git -C "$LISTEN_GEN_REPO" rev-parse HEAD)"
readonly CORE_INITIAL_STATUS="$(git -C "$LISTEN_CORE_REPO" status --porcelain)"
readonly GEN_INITIAL_STATUS="$(git -C "$LISTEN_GEN_REPO" status --porcelain)"

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT
mkdir -p "$tmp/home" "$tmp/snapshots"

snapshot_sha=""
CORE_SOURCE="$(snapshot_workspace "$LISTEN_CORE_REPO" "listen-core" "$tmp/snapshots/core")"
CORE_SNAPSHOT="$snapshot_sha"
snapshot_sha=""
GEN_SOURCE="$(snapshot_workspace "$LISTEN_GEN_REPO" "listen-gen" "$tmp/snapshots/gen")"
GEN_SNAPSHOT="$snapshot_sha"
readonly CORE_HEAD="$(git -C "$CORE_SOURCE" rev-parse HEAD)"
readonly GEN_HEAD="$(git -C "$GEN_SOURCE" rev-parse HEAD)"

# Preserve the caller's populated cache while isolating runtime HOME. Offline
# dependency resolution makes a missing cache entry an immediate setup error,
# never a surprise network dependency midway through the gate.
pub_cache="${PUB_CACHE:-${HOME}/.pub-cache}"
[ -d "$pub_cache" ] || fail "PUB_CACHE does not exist: $pub_cache"
echo "verify-roundtrip: resolving App dependencies from existing PUB_CACHE (offline)"
( cd "$app_root" &&
  run_stage dependency-setup \
    env HOME="$tmp/home" PUB_CACHE="$pub_cache" flutter pub get --offline )

# Build the Core contract artifact from the Core snapshot so the Gen bundle
# records the contract identity of the exact Core checkout this gate builds
# against, never a production lock identity.
echo "verify-roundtrip: building Core contract artifact at $CORE_HEAD"
( cd "$CORE_SOURCE" &&
  run_stage core-contract env python3 scripts/release_artifacts.py contract \
    --allow-dirty \
    --output-dir "$tmp/contracts" )
core_contract_manifest="$(ls "$tmp/contracts"/listen-contracts-*.manifest.json | head -1)"
[ -n "$core_contract_manifest" ] || fail "core contract manifest was not produced"

# PYTHONDONTWRITEBYTECODE keeps the Gen build/verify from leaving __pycache__
# behind inside the Gen checkout (or its snapshot).
echo "verify-roundtrip: building local Gen bundle at $GEN_HEAD"
( cd "$GEN_SOURCE" &&
  run_stage gen-build env PYTHONDONTWRITEBYTECODE=1 "$GEN_PYTHON" tools/release_bundle.py build \
    --source-commit "$GEN_HEAD" \
    --core-contract-manifest "$core_contract_manifest" \
    --output-parent "$tmp/gen" )

echo "verify-roundtrip: verifying Gen bundle"
gen_manifest="$(find "$tmp/gen" -type f -name '*.release.json' -print | sort | head -1)"
[ -n "$gen_manifest" ] || fail "local Gen build did not produce a release manifest"
gen_dir="$(dirname "$gen_manifest")"
gen_version="$(basename "$gen_manifest" .release.json)"
gen_artifact="$gen_dir/$gen_version.pyz"
[ -f "$gen_artifact" ] || fail "local Gen build did not produce $gen_version.pyz"
case "$gen_version" in
  listen-gen-*) ;;
  *) fail "unexpected Gen release directory: $gen_version" ;;
esac
( cd "$GEN_SOURCE" &&
  run_stage gen-verify env PYTHONDONTWRITEBYTECODE=1 "$GEN_PYTHON" tools/release_bundle.py verify \
    --core-contract-manifest "$core_contract_manifest" \
    "$gen_manifest" )

echo "verify-roundtrip: building disposable content-family fixtures"
fixture_root="$tmp/fixtures"
run_stage fixture-build env PYTHONDONTWRITEBYTECODE=1 "$GEN_PYTHON" \
  "$app_root/tool/build_content_package_roundtrip_fixtures.py" \
  --output "$fixture_root"

# Build Core into a temporary target so nothing is written into the checkout
# (or its snapshot).
echo "verify-roundtrip: building local Core api-http at $CORE_HEAD"
run_stage core-build env CARGO_TARGET_DIR="$tmp/core-target" \
  cargo build \
  --locked \
  --offline \
  --manifest-path "$CORE_SOURCE/Cargo.toml" \
  -p api-http

echo "verify-roundtrip: running focused integration tests"
( cd "$app_root" &&
  VERIFY_ROUNDTRIP_REPORT_PATH="$tmp/flutter-report.jsonl" \
  run_stage flutter-test env \
    HOME="$tmp/home" \
    PUB_CACHE="$pub_cache" \
    LLPLAYERNEXT_API_BINARY="$tmp/core-target/debug/api-http" \
    LLPLAYERNEXT_DB="$tmp/db.sqlite" \
    LISTEN_GEN_RELEASE_MANIFEST="$gen_manifest" \
    LISTEN_E2E_GEN_PYTHON="$GEN_PYTHON" \
    LISTEN_E2E_FIXTURE_ROOT="$fixture_root" \
    LISTEN_GEN_PROVIDER_ARGUMENTS="[\"--provider\",\"fixture\",\"--fixture\",\"$fixture_root/sample.asr.json\"]" \
    LISTEN_PACKAGE_E2E=1 \
      flutter test \
      test/integration/listen_gen_core_roundtrip_test.dart \
      test/integration/content_package_e2e_test.dart \
      test/integration/material_failure_injection_test.dart \
      test/integration/discovery_feed_roundtrip_test.dart \
      --concurrency 1 \
      --reporter expanded \
      --file-reporter "json:$tmp/flutter-report.jsonl" )

python3 "$app_root/tool/verify_flutter_test_report.py" \
  "$tmp/flutter-report.jsonl" "$EXPECTED_MEDIA_TEST"
python3 "$app_root/tool/verify_flutter_test_report.py" \
  "$tmp/flutter-report.jsonl" "$EXPECTED_DOCUMENT_TEST"
python3 "$app_root/tool/verify_flutter_test_report.py" \
  "$tmp/flutter-report.jsonl" "$EXPECTED_MATRIX_TEST"
python3 "$app_root/tool/verify_flutter_test_report.py" \
  "$tmp/flutter-report.jsonl" "$EXPECTED_RICH_TEST"
python3 "$app_root/tool/verify_flutter_test_report.py" \
  "$tmp/flutter-report.jsonl" "$EXPECTED_RENDER_TEST"

# The run must leave both external checkouts untouched. Reusing check_repo also
# fails closed if Git itself becomes unreadable during the run.
check_repo "$LISTEN_CORE_REPO" "listen-core"
check_repo "$LISTEN_GEN_REPO" "listen-gen"

final_core_head="$(git -C "$LISTEN_CORE_REPO" rev-parse HEAD)"
final_gen_head="$(git -C "$LISTEN_GEN_REPO" rev-parse HEAD)"
final_core_status="$(git -C "$LISTEN_CORE_REPO" status --porcelain)"
final_gen_status="$(git -C "$LISTEN_GEN_REPO" status --porcelain)"
[ "$final_core_head" = "$CORE_INITIAL_HEAD" ] ||
  fail "listen-core HEAD changed during the gate"
[ "$final_gen_head" = "$GEN_INITIAL_HEAD" ] ||
  fail "listen-gen HEAD changed during the gate"
[ "$final_core_status" = "$CORE_INITIAL_STATUS" ] ||
  fail "listen-core working tree changed during the gate"
[ "$final_gen_status" = "$GEN_INITIAL_STATUS" ] ||
  fail "listen-gen working tree changed during the gate"

echo "verify-roundtrip: OK"
