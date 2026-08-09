#!/usr/bin/env bash
#
# Real three-repository round trip for the pinned listen-gen release bundle.
#
# Builds the pinned Gen bundle and the pinned Core `api-http` in a throwaway
# directory, then runs the focused integration test that drives:
#
#   pinned .pyz  ->  .listenpkg  ->  Core content-package import (candidate)
#
# It mutates neither external repository, downloads no model, runs no Whisper,
# touches no network, and updates no lock. Every generated artifact lives under
# a temporary directory that is removed on exit.
#
# Required environment:
#   LISTEN_CORE_REPO   absolute path to a clean listen-core checkout
#   LISTEN_GEN_REPO    absolute path to a clean listen-gen checkout
#
set -euo pipefail

readonly CORE_PIN="${VERIFY_ROUNDTRIP_CORE_PIN:-b0b0dc81a212ae5e5c97e2234439eb0d6a53ab5d}"
readonly GEN_PIN="${VERIFY_ROUNDTRIP_GEN_PIN:-24e07d37da07dc9be88b5e8d514b2d298579d9a6}"
readonly EXPECTED_TEST="pinned Gen bundle to Core import round trips as a candidate"

# Tests prove the gate defaults stay in lockstep with backend.lock.json /
# listen_gen.lock.json by parsing this script's text
# (test_verify_local_content_package_roundtrip.py::DefaultPinTests). There is
# deliberately no execution hook here: an environment-driven early exit would
# let an accidentally-set variable turn the production gate into a no-op
# success, which is not acceptable.
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
  local repo="$1" expected="$2" name="$3"
  local head status
  if ! head="$(git -C "$repo" rev-parse HEAD)"; then
    fail "$name is not a readable Git checkout: $repo"
  fi
  [ "$head" = "$expected" ] || fail "$name HEAD is $head, expected $expected"
  if ! status="$(git -C "$repo" status --porcelain)"; then
    fail "cannot inspect $name working tree: $repo"
  fi
  [ -z "$status" ] || fail "$name working tree is not clean"
}

check_repo "$LISTEN_CORE_REPO" "$CORE_PIN" "listen-core"
check_repo "$LISTEN_GEN_REPO" "$GEN_PIN" "listen-gen"

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
echo "verify-roundtrip: building pinned Gen bundle"
( cd "$LISTEN_GEN_REPO" &&
  run_stage gen-build env PYTHONDONTWRITEBYTECODE=1 python3 tools/release_bundle.py build \
    --source-commit "$GEN_PIN" \
    --output-parent "$tmp/gen" )

echo "verify-roundtrip: verifying Gen bundle"
( cd "$LISTEN_GEN_REPO" &&
  run_stage gen-verify env PYTHONDONTWRITEBYTECODE=1 python3 tools/release_bundle.py verify \
    "$tmp/gen/listen-gen-0.4.0/listen-gen-0.4.0.release.json" )

# Build Core into a temporary target so nothing is written into the checkout.
echo "verify-roundtrip: building pinned Core api-http"
run_stage core-build env CARGO_TARGET_DIR="$tmp/core-target" \
  cargo build \
  --locked \
  --offline \
  --manifest-path "$LISTEN_CORE_REPO/Cargo.toml" \
  -p api-http

echo "verify-roundtrip: running focused integration test"
( cd "$app_root" &&
  VERIFY_ROUNDTRIP_REPORT_PATH="$tmp/flutter-report.jsonl" \
  run_stage flutter-test env \
    HOME="$tmp/home" \
    PUB_CACHE="$pub_cache" \
    LLPLAYERNEXT_API_BINARY="$tmp/core-target/debug/api-http" \
    LISTEN_GEN_RELEASE_MANIFEST="$tmp/gen/listen-gen-0.4.0/listen-gen-0.4.0.release.json" \
    LISTEN_GEN_PROVIDER_ARGUMENTS="[\"--provider\",\"fixture\",\"--fixture\",\"$app_root/test/fixtures/content-package-roundtrip/sample.asr.json\",\"--aligner\",\"fixture\",\"--alignment-fixture\",\"$app_root/test/fixtures/content-package-roundtrip/alignment-result.json\",\"--sense-groups\",\"fixture\",\"--sense-groups-fixture\",\"$app_root/test/fixtures/content-package-roundtrip/sense-group-result.json\",\"--acoustics\",\"fixture\",\"--acoustics-fixture\",\"$app_root/test/fixtures/content-package-roundtrip/acoustics-result.json\",\"--prosody\",\"fixture\",\"--prosody-fixture\",\"$app_root/test/fixtures/content-package-roundtrip/prosody-result.json\",\"--phone\",\"fixture\",\"--phone-fixture\",\"$app_root/test/fixtures/content-package-roundtrip/phone-result.json\"]" \
    LISTEN_PACKAGE_E2E=1 \
    flutter test test/integration/listen_gen_core_roundtrip_test.dart \
      --reporter expanded \
      --file-reporter "json:$tmp/flutter-report.jsonl" )

python3 "$app_root/tool/verify_flutter_test_report.py" \
  "$tmp/flutter-report.jsonl" "$EXPECTED_TEST"

# The run must leave both external checkouts untouched. Reusing check_repo also
# fails closed if Git itself becomes unreadable during the run.
check_repo "$LISTEN_CORE_REPO" "$CORE_PIN" "listen-core"
check_repo "$LISTEN_GEN_REPO" "$GEN_PIN" "listen-gen"

echo "verify-roundtrip: OK"
