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

readonly CORE_PIN="b980a20666f746685db1fd06bfa425d762d7a678"
readonly GEN_PIN="41a53336fd893522abf7ef168fd2ace9fa6ac678"

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "verify-roundtrip: $*" >&2
  exit 1
}

: "${LISTEN_CORE_REPO:?set LISTEN_CORE_REPO to an absolute listen-core path}"
: "${LISTEN_GEN_REPO:?set LISTEN_GEN_REPO to an absolute listen-gen path}"

[ -d "$LISTEN_CORE_REPO" ] || fail "LISTEN_CORE_REPO does not exist: $LISTEN_CORE_REPO"
[ -d "$LISTEN_GEN_REPO" ] || fail "LISTEN_GEN_REPO does not exist: $LISTEN_GEN_REPO"

check_repo() {
  local repo="$1" expected="$2" name="$3"
  local head
  head="$(git -C "$repo" rev-parse HEAD)"
  [ "$head" = "$expected" ] || fail "$name HEAD is $head, expected $expected"
  [ -z "$(git -C "$repo" status --porcelain)" ] || fail "$name working tree is not clean"
}

check_repo "$LISTEN_CORE_REPO" "$CORE_PIN" "listen-core"
check_repo "$LISTEN_GEN_REPO" "$GEN_PIN" "listen-gen"

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

# PYTHONDONTWRITEBYTECODE keeps the Gen build/verify from leaving __pycache__
# behind inside the Gen checkout.
echo "verify-roundtrip: building pinned Gen bundle"
( cd "$LISTEN_GEN_REPO" &&
  PYTHONDONTWRITEBYTECODE=1 python3 tools/release_bundle.py build \
    --source-commit "$GEN_PIN" \
    --output-parent "$tmp/gen" )

echo "verify-roundtrip: verifying Gen bundle"
( cd "$LISTEN_GEN_REPO" &&
  PYTHONDONTWRITEBYTECODE=1 python3 tools/release_bundle.py verify \
    "$tmp/gen/listen-gen-0.1.0/listen-gen-0.1.0.release.json" )

# Build Core into a temporary target so nothing is written into the checkout.
echo "verify-roundtrip: building pinned Core api-http"
CARGO_TARGET_DIR="$tmp/core-target" \
  cargo build \
  --locked \
  --manifest-path "$LISTEN_CORE_REPO/Cargo.toml" \
  -p api-http

mkdir -p "$tmp/home"

echo "verify-roundtrip: running focused integration test"
( cd "$app_root" &&
  HOME="$tmp/home" \
  LLPLAYERNEXT_API_BINARY="$tmp/core-target/debug/api-http" \
  LISTEN_GEN_RELEASE_MANIFEST="$tmp/gen/listen-gen-0.1.0/listen-gen-0.1.0.release.json" \
  LISTEN_GEN_PROVIDER_ARGUMENTS="[\"--provider\",\"fixture\",\"--fixture\",\"$app_root/test/fixtures/content-package-roundtrip/sample.asr.json\"]" \
  LISTEN_PACKAGE_E2E=1 \
  flutter test test/integration/listen_gen_core_roundtrip_test.dart )

# The run must leave both external checkouts untouched.
[ -z "$(git -C "$LISTEN_CORE_REPO" status --porcelain)" ] ||
  fail "listen-core working tree changed during the round trip"
[ -z "$(git -C "$LISTEN_GEN_REPO" status --porcelain)" ] ||
  fail "listen-gen working tree changed during the round trip"

echo "verify-roundtrip: OK"
