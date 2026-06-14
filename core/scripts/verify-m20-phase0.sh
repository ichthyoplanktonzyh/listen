#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
evaluator="$root/scripts/phonetic-eval.py"
adapter="$root/scripts/phonetic-research-adapter.py"
zipa_adapter="$root/scripts/zipa-ctc-onnx-research.py"
zipa_setup="$root/scripts/setup-zipa-research.sh"
fixtures="$root/testdata/phonetic-analysis"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

catalog="$(python3 "$evaluator" validate-catalog "$fixtures/evaluation-catalog-v1.tsv")"
inputs="$(python3 "$evaluator" validate-inputs \
  "$fixtures/input-manifest-smoke-v1.jsonl" \
  --catalog "$fixtures/evaluation-catalog-v1.tsv" \
  --minimum-cases 1)"
template="$(python3 "$evaluator" create-input-template \
  "$fixtures/evaluation-catalog-v1.tsv" \
  --case-ids m20-001,m20-002,m20-004,m20-011,m20-013,m20-015,m20-021,m20-022,m20-023,m20-024)"
score="$(python3 "$evaluator" score "$fixtures/reference-smoke-v1.jsonl" "$fixtures/prediction-smoke-v1.jsonl")"
error_score="$(python3 "$evaluator" score "$fixtures/reference-smoke-v1.jsonl" "$fixtures/prediction-smoke-errors-v1.jsonl")"
candidates="$(cat "$fixtures/candidates-v1.json")"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m py_compile \
  "$evaluator" "$adapter" "$zipa_adapter"
bash -n "$zipa_setup"

adapter_output="$tmp/adapter-smoke.jsonl"
adapter_metrics="$tmp/adapter-metrics.jsonl"
timeline="$(python3 "$adapter" derive-ctc-timeline \
  --frames "$fixtures/zipa-ctc-frames-smoke-v1.json" \
  --tokens "$fixtures/zipa-tokens-smoke-v1.txt" \
  --audio-start-ms 100 \
  --audio-end-ms 300 \
  --phone-set test)"
python3 "$adapter" run \
  --case-id adapter-smoke \
  --audio "$fixtures/reference-smoke-v1.jsonl" \
  --audio-start-ms 100 \
  --audio-end-ms 300 \
  --license-id repository-test-fixture \
  --provider-id adapter-smoke \
  --model "$fixtures/reference-smoke-v1.jsonl" \
  --model-revision smoke \
  --phone-set test \
  --output "$adapter_output" \
  --metrics "$adapter_metrics" \
  -- node -e 'process.stdout.write(JSON.stringify({time_base:"relative",phones:[{symbol:"A",start_ms:0,end_ms:100,token_index:0},{symbol:"B",start_ms:100,end_ms:200,token_index:0}]}))' \
  >/dev/null
adapter_score="$(python3 "$evaluator" score "$adapter_output" "$adapter_output")"

node -e '
const catalog = JSON.parse(process.argv[1]);
const inputs = JSON.parse(process.argv[2]);
const score = JSON.parse(process.argv[3]);
const errorScore = JSON.parse(process.argv[4]);
const candidates = JSON.parse(process.argv[5]);
const adapterScore = JSON.parse(process.argv[6]);
const template = process.argv[7].trim().split("\n").map(JSON.parse);
const timeline = JSON.parse(process.argv[8]);
if (catalog.case_count !== 60) throw new Error("Phase 0 catalog must contain 60 fixed slots");
if (catalog.reference_status.planned !== 60) throw new Error("Phase 0 slots must remain explicitly planned until human references exist");
if (inputs.case_count !== 1 || inputs.ready_for_candidate_development_run) throw new Error("input-manifest smoke should validate without claiming development readiness");
if (score.phone_error_rate !== 0) throw new Error("scorer smoke fixture should have zero PER");
if (!score.release_gates.timeline_valid_ratio_at_least_0_95) throw new Error("timeline gate calculation failed");
if (!score.release_gates.token_association_coverage_at_least_0_85) throw new Error("association gate calculation failed");
if (errorScore.phone_error_rate !== 0.285714) throw new Error("PER error calculation failed");
if (errorScore.timeline_valid_ratio !== 0.5) throw new Error("invalid timeline calculation failed");
if (errorScore.release_gates.timeline_valid_ratio_at_least_0_95) throw new Error("invalid timeline incorrectly passed");
if (errorScore.release_gates.token_association_coverage_at_least_0_85) throw new Error("unassociated phones incorrectly passed");
if (candidates.release_provider_selected) throw new Error("Phase 0 must not claim a release provider");
if (!candidates.candidates.some(x => x.id === "allosaurus" && x.status === "not_eligible_for_default_distribution")) throw new Error("Allosaurus distribution boundary missing");
if (!candidates.candidates.some(x => x.id === "zipa-small-crctc-300k" && !x.license_verified)) throw new Error("ZIPA exact license must remain pending");
if (!candidates.candidates.some(x => x.id === "vosk-kaldi-alignment" && x.status === "eligible_for_research_not_yet_a_phone_recognition_candidate")) throw new Error("Vosk/Kaldi research-baseline boundary missing");
if (adapterScore.timeline_valid_ratio !== 1 || adapterScore.token_association_coverage !== 1) throw new Error("candidate adapter normalized timeline smoke failed");
if (template.length !== 10 || template.some(x => x.review_status !== "draft")) throw new Error("first development input template generation failed");
if (timeline.phones.length !== 2 || timeline.phones[0].start_ms !== 25 || timeline.phones[1].end_ms !== 175) throw new Error("experimental ZIPA CTC frame projection failed");
' "$catalog" "$inputs" "$score" "$error_score" "$candidates" "$adapter_score" "$template" "$timeline"

if python3 "$adapter" run \
  --case-id sequence-only \
  --audio "$fixtures/reference-smoke-v1.jsonl" \
  --audio-start-ms 100 \
  --audio-end-ms 300 \
  --license-id repository-test-fixture \
  --provider-id adapter-smoke \
  --model "$fixtures/reference-smoke-v1.jsonl" \
  --model-revision smoke \
  --phone-set test \
  --output "$tmp/sequence-only.jsonl" \
  --metrics "$tmp/sequence-only-metrics.jsonl" \
  -- node -e 'process.stdout.write(JSON.stringify({phones:[{symbol:"A"}]}))' \
  >/dev/null 2>&1; then
  echo "Candidate output without per-phone timestamps must be rejected." >&2
  exit 1
fi
node -e '
const fs = require("fs");
const rows = fs.readFileSync(process.argv[1], "utf8").trim().split("\n").map(JSON.parse);
if (rows.length !== 1 || !rows[0].failure.includes("without per-phone integer timestamps")) {
  throw new Error("candidate adapter failure metrics missing");
}
' "$tmp/sequence-only-metrics.jsonl"

node -e '
const fs = require("fs");
const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
value.audio_sha256 = "0".repeat(64);
value.audio_path = process.argv[3];
fs.writeFileSync(process.argv[2], JSON.stringify(value) + "\n");
' "$fixtures/input-manifest-smoke-v1.jsonl" "$tmp/bad-input-manifest.jsonl" \
  "$fixtures/reference-smoke-v1.jsonl"
if python3 "$evaluator" validate-inputs "$tmp/bad-input-manifest.jsonl" \
  --catalog "$fixtures/evaluation-catalog-v1.tsv" --minimum-cases 1 \
  >/dev/null 2>&1; then
  echo "Input manifest checksum mismatch must be rejected." >&2
  exit 1
fi

cat "$fixtures/reference-smoke-v1.jsonl" "$fixtures/reference-smoke-v1.jsonl" >"$tmp/duplicate.jsonl"
if python3 "$evaluator" score "$tmp/duplicate.jsonl" "$fixtures/prediction-smoke-v1.jsonl" >/dev/null 2>&1; then
  echo "Duplicate case IDs must be rejected." >&2
  exit 1
fi

echo "Milestone 2.0 Phase 0 research infrastructure verification passed."
