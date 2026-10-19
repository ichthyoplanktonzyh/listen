#!/usr/bin/env bash
# Build Core and Gen from one isolated monorepo snapshot, then exercise the
# generated package through the app's real Gen -> Core adoption path.
set -euo pipefail

readonly EXPECTED_MEDIA_TEST="local Gen bundle to local Core round trips through capability production, installation, and adoption"
readonly EXPECTED_DOCUMENT_TEST="a document material produces listen through the fake TTS provider and its derived audio resolves from the adopted composition through Core"
readonly EXPECTED_MATRIX_TEST="the Gen/Core/App matrix keeps one adopted package shape across document and media families"
readonly EXPECTED_RICH_TEST="a video subtitle with fragmented cues lands as one complete sentence with every rich timeline"
readonly EXPECTED_RENDER_TEST="Core-adopted compositions render honest audio and text surfaces for document, audio, and video"

app_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_root=""
while (($#)); do
  case "$1" in
    --source-root)
      (($# >= 2)) || { echo "--source-root requires a path" >&2; exit 2; }
      source_root="$2"
      shift 2
      ;;
    *)
      echo "unknown option: $1" >&2
      exit 2
      ;;
  esac
done
if [[ -z "$source_root" ]]; then
  source_root="$(git -C "$app_root" rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -n "$source_root" && -d "$source_root" ]] || {
  echo "verify-roundtrip: pass --source-root with a monorepo root containing app/, core/, and gen/" >&2
  exit 2
}
source_root="$(cd "$source_root" && pwd)"

fail() {
  echo "verify-roundtrip: $*" >&2
  exit 1
}

run_stage() {
  local stage="$1"
  shift
  if [[ -n "${VERIFY_ROUNDTRIP_STAGE_RUNNER:-}" ]]; then
    "$VERIFY_ROUNDTRIP_STAGE_RUNNER" "$stage" "$@"
  else
    "$@"
  fi
}

for tree in app core gen; do
  [[ -d "$source_root/$tree" ]] || fail "source root has no $tree/ directory: $source_root"
done

tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

# Use a clean caller-provided snapshot as-is so every artifact keeps its
# source commit. Dirty inputs are copied once as a whole monorepo and receive a
# synthetic commit representing the exact source content tested.
snapshot="$source_root"
git_root="$(git -C "$source_root" rev-parse --show-toplevel 2>/dev/null || true)"
source_head=""
initial_status=""
if [[ -n "$git_root" && "$git_root" == "$source_root" ]]; then
  source_head="$(git -C "$source_root" rev-parse HEAD)"
  initial_status="$(git -C "$source_root" status --porcelain)"
fi
if [[ -n "$source_head" && -z "$initial_status" ]]; then
  readonly SOURCE_COMMIT="$source_head"
else
  snapshot="$tmp/source"
  mkdir -p "$snapshot"
  if [[ -n "$source_head" ]]; then
  git -C "$source_root" archive HEAD | tar -x -C "$snapshot"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if [[ -e "$source_root/$path" || -L "$source_root/$path" ]]; then
      mkdir -p "$snapshot/$(dirname "$path")"
      cp -pPR "$source_root/$path" "$snapshot/$path"
    else
      rm -f "$snapshot/$path"
    fi
  done < <(git -C "$source_root" diff --name-only HEAD)
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      app/build/*|app/.dart_tool/*|core/target/*|gen/dist/*|gen/.venv/*|*.pyc|*/__pycache__/*)
        continue
        ;;
    esac
    mkdir -p "$snapshot/$(dirname "$path")"
    cp -pPR "$source_root/$path" "$snapshot/$path"
  done < <(git -C "$source_root" ls-files --others --exclude-standard)
  else
  for tree in app core gen; do
    cp -R "$source_root/$tree" "$snapshot/$tree"
  done
  fi
  git -C "$snapshot" init -q
  git -C "$snapshot" config user.email "roundtrip@localhost"
  git -C "$snapshot" config user.name "listen roundtrip"
  git -C "$snapshot" add -A
  git -C "$snapshot" commit -q -m "isolated monorepo source snapshot"
  readonly SOURCE_COMMIT="$(git -C "$snapshot" rev-parse HEAD)"
fi
readonly APP_SOURCE="$snapshot/app"
readonly CORE_SOURCE="$snapshot/core"
readonly GEN_SOURCE="$snapshot/gen"
readonly GEN_PYTHON="${LISTEN_GEN_PYTHON:-$source_root/gen/.venv/bin/python}"
 cargo_target="${CARGO_TARGET_DIR:-$tmp/core-target}"
if [[ "$cargo_target" == /* ]]; then
  mkdir -p "$cargo_target"
else
  cargo_target="$(mkdir -p "$cargo_target" && cd "$cargo_target" && pwd)"
fi
readonly CARGO_TARGET="$cargo_target"
echo "verify-roundtrip: building app/core/gen from one snapshot ($SOURCE_COMMIT)"

if [[ -z "${VERIFY_ROUNDTRIP_STAGE_RUNNER:-}" ]]; then
  [[ -x "$GEN_PYTHON" ]] || fail "LISTEN_GEN_PYTHON is not an executable Python >=3.11 runtime: $GEN_PYTHON"
  if ! "$GEN_PYTHON" - <<'PY'
import sys
if sys.version_info < (3, 11):
    raise SystemExit("listen-gen E2E requires Python >=3.11")
try:
    import pypdf  # noqa: F401
except ImportError as error:
    raise SystemExit("listen-gen E2E requires the Gen PDF dependency pypdf") from error
PY
  then
    fail "Gen PDF fixture dependencies are unavailable in $GEN_PYTHON"
  fi
fi

pub_cache="${PUB_CACHE:-${HOME}/.pub-cache}"
[[ -d "$pub_cache" ]] || fail "PUB_CACHE does not exist: $pub_cache"
mkdir -p "$tmp/home"
echo "verify-roundtrip: resolving App dependencies from existing PUB_CACHE (offline)"
( cd "$APP_SOURCE" &&
  run_stage dependency-setup \
    env HOME="$tmp/home" PUB_CACHE="$pub_cache" flutter pub get --offline )

echo "verify-roundtrip: building Core contract artifact at $SOURCE_COMMIT"
( cd "$CORE_SOURCE" &&
  run_stage core-contract env python3 scripts/release_artifacts.py contract \
    --allow-dirty --output-dir "$tmp/contracts" )
core_contract_manifest="$(find "$tmp/contracts" -maxdepth 1 -name 'listen-contracts-*.manifest.json' -print -quit)"
[[ -n "$core_contract_manifest" ]] || fail "Core contract manifest was not produced"

echo "verify-roundtrip: building local Gen bundle at $SOURCE_COMMIT"
( cd "$GEN_SOURCE" &&
  run_stage gen-build env PYTHONDONTWRITEBYTECODE=1 "$GEN_PYTHON" tools/release_bundle.py build \
    --source-commit "$SOURCE_COMMIT" \
    --core-contract-manifest "$core_contract_manifest" \
    --output-parent "$tmp/gen" )

gen_manifest="$(find "$tmp/gen" -type f -name '*.release.json' -print -quit)"
[[ -n "$gen_manifest" ]] || fail "local Gen build did not produce a release manifest"
gen_dir="$(dirname "$gen_manifest")"
gen_version="$(basename "$gen_manifest" .release.json)"
gen_artifact="$gen_dir/$gen_version.pyz"
[[ -f "$gen_artifact" ]] || fail "local Gen build did not produce $gen_version.pyz"
case "$gen_version" in
  listen-gen-*) ;;
  *) fail "unexpected Gen release directory: $gen_version" ;;
esac
( cd "$GEN_SOURCE" &&
  run_stage gen-verify env PYTHONDONTWRITEBYTECODE=1 "$GEN_PYTHON" tools/release_bundle.py verify \
    --core-contract-manifest "$core_contract_manifest" "$gen_manifest" )

echo "verify-roundtrip: building disposable content-family fixtures"
fixture_root="$tmp/fixtures"
run_stage fixture-build env PYTHONDONTWRITEBYTECODE=1 "$GEN_PYTHON" \
  "$APP_SOURCE/tool/build_content_package_roundtrip_fixtures.py" \
  --output "$fixture_root"

echo "verify-roundtrip: building local Core api-http at $SOURCE_COMMIT"
run_stage core-build env CARGO_TARGET_DIR="$CARGO_TARGET" cargo build --locked --offline \
  --manifest-path "$CORE_SOURCE/Cargo.toml" -p api-http

echo "verify-roundtrip: running focused integration tests"
report="$tmp/flutter-report.jsonl"
( cd "$APP_SOURCE" &&
  VERIFY_ROUNDTRIP_REPORT_PATH="$report" \
  run_stage flutter-test env \
    HOME="$tmp/home" \
    PUB_CACHE="$pub_cache" \
    LLPLAYERNEXT_API_BINARY="$CARGO_TARGET/debug/api-http" \
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
      --concurrency 1 --reporter expanded --file-reporter "json:$report" )

python3 "$APP_SOURCE/tool/verify_flutter_test_report.py" "$report" "$EXPECTED_MEDIA_TEST"
python3 "$APP_SOURCE/tool/verify_flutter_test_report.py" "$report" "$EXPECTED_DOCUMENT_TEST"
python3 "$APP_SOURCE/tool/verify_flutter_test_report.py" "$report" "$EXPECTED_MATRIX_TEST"
python3 "$APP_SOURCE/tool/verify_flutter_test_report.py" "$report" "$EXPECTED_RICH_TEST"
python3 "$APP_SOURCE/tool/verify_flutter_test_report.py" "$report" "$EXPECTED_RENDER_TEST"

if [[ -n "$source_head" ]]; then
  final_head="$(git -C "$source_root" rev-parse HEAD)"
  final_status="$(git -C "$source_root" status --porcelain)"
  [[ "$final_head" == "$source_head" ]] || fail "source monorepo HEAD changed during the gate"
  [[ "$final_status" == "$initial_status" ]] || fail "source monorepo working tree changed during the gate"
fi

echo "verify-roundtrip: OK"
