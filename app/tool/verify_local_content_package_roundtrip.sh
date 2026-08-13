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
#   LISTEN_CORE_REPO   absolute path to a clean listen-core checkout
#   LISTEN_GEN_REPO    absolute path to a clean listen-gen checkout
#
set -euo pipefail

readonly EXPECTED_TEST="local Gen bundle to local Core round trips through capability production, installation, and adoption"

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
  [ -z "$status" ] || fail "$name working tree is not clean"
}

check_repo "$LISTEN_CORE_REPO" "listen-core"
check_repo "$LISTEN_GEN_REPO" "listen-gen"
readonly CORE_HEAD="$(git -C "$LISTEN_CORE_REPO" rev-parse HEAD)"
readonly GEN_HEAD="$(git -C "$LISTEN_GEN_REPO" rev-parse HEAD)"

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT
mkdir -p "$tmp/home"

# Preserve the caller's populated cache while isolating runtime HOME. Offline
# dependency resolution makes a missing cache entry an immediate setup error,
# never a surprise network dependency midway through the gate.
pub_cache="${PUB_CACHE:-${HOME}/.pub-cache}"
[ -d "$pub_cache" ] || fail "PUB_CACHE does not exist: $pub_cache"
echo "verify-roundtrip: resolving App dependencies from existing PUB_CACHE (offline)"
( cd "$app_root" &&
  run_stage dependency-setup \
    env HOME="$tmp/home" PUB_CACHE="$pub_cache" flutter pub get --offline )

# PYTHONDONTWRITEBYTECODE keeps the Gen build/verify from leaving __pycache__
# behind inside the Gen checkout.
echo "verify-roundtrip: building local Gen bundle at $GEN_HEAD"
( cd "$LISTEN_GEN_REPO" &&
  run_stage gen-build env PYTHONDONTWRITEBYTECODE=1 python3 tools/release_bundle.py build \
    --source-commit "$GEN_HEAD" \
    --output-parent "$tmp/gen" )

echo "verify-roundtrip: verifying Gen bundle"
( cd "$LISTEN_GEN_REPO" &&
  run_stage gen-verify env PYTHONDONTWRITEBYTECODE=1 python3 tools/release_bundle.py verify \
    "$tmp/gen/listen-gen-0.5.0/listen-gen-0.5.0.release.json" )

# Build Core into a temporary target so nothing is written into the checkout.
echo "verify-roundtrip: building local Core api-http at $CORE_HEAD"
run_stage core-build env CARGO_TARGET_DIR="$tmp/core-target" \
  cargo build \
  --locked \
  --offline \
  --manifest-path "$LISTEN_CORE_REPO/Cargo.toml" \
  -p api-http

echo "verify-roundtrip: running focused integration tests"
( cd "$app_root" &&
  VERIFY_ROUNDTRIP_REPORT_PATH="$tmp/flutter-report.jsonl" \
  run_stage flutter-test env \
    HOME="$tmp/home" \
    PUB_CACHE="$pub_cache" \
    LLPLAYERNEXT_API_BINARY="$tmp/core-target/debug/api-http" \
    LLPLAYERNEXT_DB="$tmp/db.sqlite" \
    LISTEN_GEN_RELEASE_MANIFEST="$tmp/gen/listen-gen-0.5.0/listen-gen-0.5.0.release.json" \
    LISTEN_GEN_PROVIDER_ARGUMENTS="[\"--provider\",\"fixture\",\"--fixture\",\"$app_root/test/fixtures/content-package-roundtrip/sample.asr.json\"]" \
    LISTEN_PACKAGE_E2E=1 \
    flutter test \
      test/integration/listen_gen_core_roundtrip_test.dart \
      test/integration/material_failure_injection_test.dart \
      test/integration/discovery_feed_roundtrip_test.dart \
      --concurrency 1 \
      --reporter expanded \
      --file-reporter "json:$tmp/flutter-report.jsonl" )

python3 "$app_root/tool/verify_flutter_test_report.py" \
  "$tmp/flutter-report.jsonl" "$EXPECTED_TEST"

# The run must leave both external checkouts untouched. Reusing check_repo also
# fails closed if Git itself becomes unreadable during the run.
check_repo "$LISTEN_CORE_REPO" "listen-core"
check_repo "$LISTEN_GEN_REPO" "listen-gen"

echo "verify-roundtrip: OK"
