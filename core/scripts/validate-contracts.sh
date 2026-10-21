#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

python3 -m unittest "$root/scripts/test_release_artifacts.py"
cargo test --manifest-path "$root/Cargo.toml" -p content-package --locked
# Content Package v2: JSON syntax over the v2 contract tree, then the v2 suite.
while IFS= read -r -d '' v2_json; do
  python3 -m json.tool "$v2_json" >/dev/null
done < <(find "$root/contracts/content-package/v2" -name '*.json' -print0)
cargo test --manifest-path "$root/Cargo.toml" -p content-package --locked v2::
# Content Package v3: JSON syntax over the v3 contract tree, the v3 suite,
# then real JSON Schema validation of the examples and package bodies.
while IFS= read -r -d '' v3_json; do
  python3 -m json.tool "$v3_json" >/dev/null
done < <(find "$root/contracts/content-package/v3" -name '*.json' -print0)
cargo test --manifest-path "$root/Cargo.toml" -p content-package --locked v3::
python3 "$root/scripts/validate_content_package_schemas.py" "$root/contracts/content-package"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m unittest \
  "$root/scripts/test_content_package_schemas.py"
python3 "$root/scripts/openapi_contract.py" check
if command -v openapi-generator >/dev/null 2>&1; then
  openapi-generator validate -i "$root/contracts/openapi/v1.yaml"
fi

PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m py_compile \
  "$root/scripts/check-architecture-coupling.py" \
  "$root/scripts/generate_local_api_surface.py" \
  "$root/scripts/test_architecture_coupling.py" \
  "$root/scripts/benchmark-datasets.py" \
  "$root/scripts/evaluate-word-timelines.py" \
  "$root/scripts/forced-align/mfa-align-cli.py" \
  "$root/scripts/lltimeline_common.py" \
  "$root/scripts/lltimeline-resource.py" \
  "$root/scripts/syntactic-analysis/syntax-sidecar.py" \
  "$root/scripts/syntactic-analysis/evaluate_provider.py" \
  "$root/scripts/syntactic-analysis/evaluate_provider_v2.py" \
  "$root/scripts/syntactic-analysis/real_media_qa.py" \
  "$root/scripts/syntactic-analysis/real_media_qa_v2.py" \
  "$root/scripts/syntactic-analysis/test_real_media_qa.py" \
  "$root/scripts/syntactic-analysis/test_evaluate_provider.py" \
  "$root/scripts/syntactic-analysis/test_evaluate_provider_v2.py" \
  "$root/scripts/syntactic-analysis/test_syntax_sidecar_contract.py" \
  "$root/scripts/validate-syntactic-fixtures.py" \
  "$root/scripts/validate-syntactic-fixtures-v2.py" \
  "$root/scripts/lltimeline-resource.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/check-architecture-coupling.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m unittest \
  "$root/scripts/test_architecture_coupling.py"
bash -n "$root/scripts/syntactic-analysis/setup-spacy-product.sh"
python3 -m json.tool "$root/scripts/syntactic-analysis/product-assets-v2.json" >/dev/null
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/test_lltimeline_common.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/forced-align/test_align_cli_contract.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/forced-align/test_mfa_align_cli_contract.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/syntactic-analysis/test_syntax_sidecar_contract.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/syntactic-analysis/test_evaluate_provider.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/syntactic-analysis/test_evaluate_provider_v2.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/syntactic-analysis/test_real_media_qa.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/validate-syntactic-fixtures.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/validate-syntactic-fixtures-v2.py"
word_report="$(
  python3 "$root/scripts/evaluate-word-timelines.py" compare \
    --baseline "$root/testdata/word-timelines/baseline-v1.json" \
    --candidate "$root/testdata/word-timelines/candidate-v1.json" \
    --gold "$root/testdata/word-timelines/gold-v1.json" \
    --markdown-output "$tmp/word-timeline-report.md"
)"
lltimeline_evaluation_report="$(
  python3 "$root/scripts/evaluate-word-timelines.py" compare-lltimeline \
    --input "$root/testdata/lltimeline/v1-evaluation-candidates.lltimeline.json" \
    --baseline-timeline dtw-baseline \
    --candidate-timeline whisperx-candidate \
    --gold-timeline manual-gold \
    --markdown-output "$tmp/lltimeline-evaluation-report.md"
)"
lltimeline_report="$(
  python3 "$root/scripts/lltimeline-resource.py" validate \
    "$root/testdata/lltimeline/v1-minimal.lltimeline.json"
)"
lltimeline_evaluation_validation="$(
  python3 "$root/scripts/lltimeline-resource.py" validate \
    "$root/testdata/lltimeline/v1-evaluation-candidates.lltimeline.json"
)"
timit_fixture="$tmp/timit-smoke"
mkdir -p "$timit_fixture"
cp -R "$root/testdata/benchmark-datasets/timit-smoke/." "$timit_fixture/"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i sine=frequency=660:duration=1.25 \
  -ac 1 -ar 16000 -sample_fmt s16 "$timit_fixture/DR1/FAKE0/SX000.WAV"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i sine=frequency=880:duration=1.0 \
  -ac 1 -ar 16000 -sample_fmt s16 "$timit_fixture/DR1/FAKE0/SX001.WAV"
timit_output="$tmp/timit-smoke.lltimeline.json"
timit_report="$(
  python3 "$root/scripts/benchmark-datasets.py" timit-to-lltimeline \
    --input-dir "$timit_fixture" \
    --output "$timit_output" \
    --media-title "TIMIT Smoke"
)"
timit_validation="$(
  python3 "$root/scripts/lltimeline-resource.py" validate "$timit_output"
)"
timit_bundle_report="$(
  python3 "$root/scripts/benchmark-datasets.py" prepare-alignment-bundle \
    --input "$timit_output" \
    --output-dir "$tmp/timit-bundle"
)"
timit_aligned="$tmp/timit-aligned.json"
node -e '
const fs = require("fs");
const doc = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const timeline = doc.word_timelines[0];
const bySentence = new Map();
for (const word of timeline.words) {
  if (!bySentence.has(word.sentence_id)) bySentence.set(word.sentence_id, []);
  bySentence.get(word.sentence_id).push(word);
}
const timings = [];
for (const segment of doc.segments) {
  const words = (bySentence.get(segment.id) || []).sort((a, b) => a.token_index - b.token_index);
  words.forEach((word, wordIndex) => timings.push({
    segment_index: segment.index,
    word_index: wordIndex,
    text: word.text,
    start_ms: word.start_ms,
    end_ms: word.end_ms,
    score: 1
  }));
}
fs.writeFileSync(process.argv[2], JSON.stringify({timings}, null, 2) + "\n");
' "$timit_output" "$timit_aligned"
timit_candidate_output="$tmp/timit-candidate.lltimeline.json"
timit_candidate_report="$(
  python3 "$root/scripts/benchmark-datasets.py" add-alignment-candidate \
    --input "$timit_output" \
    --aligned-json "$timit_aligned" \
    --output "$timit_candidate_output" \
    --timeline-id timit-smoke-candidate
)"
timit_candidate_validation="$(
  python3 "$root/scripts/lltimeline-resource.py" validate "$timit_candidate_output"
)"
timit_candidate_evaluation="$(
  python3 "$root/scripts/evaluate-word-timelines.py" compare-lltimeline \
    --input "$timit_candidate_output" \
    --baseline-timeline @active \
    --candidate-timeline timit-smoke-candidate
)"

node -e '
const fs = require("fs");
const report = JSON.parse(process.argv[1]);
const md = fs.readFileSync(process.argv[2], "utf8");
const lltimelineReport = JSON.parse(process.argv[3]);
const lltimelineMd = fs.readFileSync(process.argv[4], "utf8");
if (report.report_version !== 1) throw new Error("word timeline report version missing");
if (report.weak_metrics.matched_word_count !== 2) throw new Error("word timeline match count failed");
if (report.weak_metrics.offsets.start_offset_ms.mean !== -5) throw new Error("start offset mean failed");
if (report.gold_metrics.start_mae_ms !== 5) throw new Error("gold start MAE failed");
if (!md.includes("Word Timeline Evaluation")) throw new Error("word timeline markdown missing");
if (lltimelineReport.source_document.baseline_timeline_id !== "dtw-baseline") throw new Error("LLTimeline baseline id missing");
if (lltimelineReport.source_document.candidate_timeline_id !== "whisperx-candidate") throw new Error("LLTimeline candidate id missing");
if (lltimelineReport.gold_metrics.coverage !== 1) throw new Error("LLTimeline gold coverage failed");
if (lltimelineReport.weak_metrics.offsets.tail_lag_ms.sentence_count !== 2) throw new Error("LLTimeline tail lag metric failed");
if (lltimelineReport.weak_metrics.offsets.end_offset_ms.p95_abs !== 182) throw new Error("LLTimeline p95 metric failed");
if (!lltimelineMd.includes("Gold Metrics")) throw new Error("LLTimeline evaluation markdown missing");
' "$word_report" "$tmp/word-timeline-report.md" "$lltimeline_evaluation_report" "$tmp/lltimeline-evaluation-report.md"

node -e '
const fs = require("fs");
const report = JSON.parse(process.argv[1]);
const evaluation = JSON.parse(process.argv[2]);
const timit = JSON.parse(process.argv[3]);
const timitValidation = JSON.parse(process.argv[4]);
const timitDocument = JSON.parse(fs.readFileSync(process.argv[5], "utf8"));
const timitBundle = JSON.parse(process.argv[6]);
const timitCandidate = JSON.parse(process.argv[7]);
const timitCandidateValidation = JSON.parse(process.argv[8]);
const timitCandidateEvaluation = JSON.parse(process.argv[9]);
const timitManifest = timitDocument.artifacts.find((artifact) => artifact.kind === "benchmark_dataset_manifest").payload;
if (report.schema !== "llplayer.timeline.v1") throw new Error("LLTimeline schema missing");
if (report.segments !== 1) throw new Error("LLTimeline segment fixture failed");
if (report.word_timelines !== 1) throw new Error("LLTimeline word timeline fixture failed");
if (report.active_word_timeline_id !== "timeline-fixture") throw new Error("LLTimeline active timeline fixture failed");
if (evaluation.segments !== 2) throw new Error("LLTimeline evaluation fixture segments failed");
if (evaluation.word_timelines !== 3) throw new Error("LLTimeline evaluation fixture timelines failed");
if (evaluation.active_word_timeline_id !== "whisperx-candidate") throw new Error("LLTimeline evaluation active timeline failed");
if (timit.segments !== 2) throw new Error("TIMIT converter segment count failed");
if (timit.words !== 9) throw new Error("TIMIT converter word count failed");
if (timit.phones !== 15) throw new Error("TIMIT converter phone count failed");
if (timitValidation.schema !== "llplayer.timeline.v1") throw new Error("TIMIT LLTimeline schema failed");
if (timitValidation.word_timelines !== 1) throw new Error("TIMIT LLTimeline word timeline failed");
if (timitManifest.boundary_adjustment_count !== 1) throw new Error("TIMIT overlap repair count failed");
if (timitManifest.skipped_word_row_count !== 1) throw new Error("TIMIT skipped word count failed");
if (timitBundle.segment_count !== 2) throw new Error("TIMIT bundle segment count failed");
if (timitBundle.word_count !== 9) throw new Error("TIMIT bundle word count failed");
if (!fs.existsSync(timitBundle.audio_path)) throw new Error("TIMIT bundle audio missing");
if (timitCandidate.timeline_id !== "timit-smoke-candidate") throw new Error("TIMIT candidate timeline id failed");
if (timitCandidate.words !== 9) throw new Error("TIMIT candidate word count failed");
if (timitCandidateValidation.word_timelines !== 2) throw new Error("TIMIT candidate validation failed");
if (timitCandidateEvaluation.weak_metrics.matched_word_count !== 9) throw new Error("TIMIT candidate evaluation match failed");
if (timitCandidateEvaluation.weak_metrics.offsets.start_offset_ms.mean_abs !== 0) throw new Error("TIMIT candidate evaluation offset failed");
' "$lltimeline_report" "$lltimeline_evaluation_validation" "$timit_report" "$timit_validation" "$timit_output" "$timit_bundle_report" "$timit_candidate_report" "$timit_candidate_validation" "$timit_candidate_evaluation"

python3 "$root/scripts/generate_local_api_surface.py" --check

node -e '
const fs = require("fs");
const schema = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const examples = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const events = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const openapi = fs.readFileSync(process.argv[4], "utf8");
const client = fs.readFileSync(process.argv[5], "utf8");
const routerSource = process.argv.slice(6).map(path => fs.readFileSync(path, "utf8")).join("\n");
const generatedArray = name => {
  const match = client.match(new RegExp(`export const ${name} = \\[([\\s\\S]*?)\\] as const;`));
  if (!match) throw new Error(`generated API inventory is missing ${name}`);
  return [...match[1].matchAll(/"([^"]+)"/g)].map(value => value[1]);
};
const sortedUnique = values => [...new Set(values)].sort();
const assertEqual = (actual, expected, label) => {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`${label} differs from canonical OpenAPI`);
  }
};
if (schema.$defs.command.properties.version.const !== 1) throw new Error("player command version missing");
if (schema.$defs.event.properties.version.const !== 1) throw new Error("player event version missing");
if (!Array.isArray(examples) || examples.length === 0) throw new Error("player examples missing");
if (events.properties.version.const !== 1) throw new Error("event schema version missing");

const version = openapi.match(/^  version: ([0-9]+\.[0-9]+\.[0-9]+)$/m)?.[1];
if (version !== "5.1.0") throw new Error(`OpenAPI contract version is ${version}, expected 5.1.0`);
if (!openapi.includes("openapi: 3.1.0")) throw new Error("OpenAPI specification version must remain 3.1.0");
if (!client.includes(`localApiV1ContractVersion = "${version}"`)) throw new Error("generated contract version differs from OpenAPI");

const paths = sortedUnique([...openapi.matchAll(/^  (\/v1\/[^:\n]+):\s*$/gm)].map(match => match[1]));
const operationIds = sortedUnique([...openapi.matchAll(/\boperationId:\s*([A-Za-z][A-Za-z0-9_]*)/g)].map(match => match[1]));
const schemaStart = openapi.split("\n").findIndex(line => line === "  schemas:");
if (schemaStart < 0) throw new Error("OpenAPI components.schemas section missing");
const schemaLines = openapi.split("\n").slice(schemaStart + 1);
const schemaBlock = [];
for (const line of schemaLines) {
  if (line && line.startsWith("  ") && !line.startsWith("    ")) break;
  schemaBlock.push(line);
}
const schemas = sortedUnique([...schemaBlock.join("\n").matchAll(/^    ([A-Za-z][A-Za-z0-9_]*):\s*$/gm)].map(match => match[1]));
assertEqual(generatedArray("localApiV1Paths"), paths, "generated path inventory");
assertEqual(generatedArray("localApiV1OperationIds"), operationIds, "generated operation inventory");
assertEqual(generatedArray("localApiV1ComponentSchemas"), schemas, "generated schema inventory");

const implementedPaths = sortedUnique([...routerSource.matchAll(/"((?:\/v1\/)[^"]+)"/g)].map(match => match[1]));
assertEqual(implementedPaths, paths, "implemented router paths");
for (const required of [
  "/v1/media",
  "/v1/media/{media_id}/material",
  "/v1/materials",
  "/v1/materials/{material_id}/capabilities",
  "/v1/materials/{material_id}/package-installations",
  "/v1/materials/{material_id}/editions",
  "/v1/materials/{material_id}/edition-adoption",
  "/v1/materials/{material_id}/composition",
  "/v1/materials/{material_id}/composition/resources/{resource_id}/payload",
  "/v1/materials/{material_id}/composition/renditions/{rendition_id}/blob",
  "/v1/source-identities/mappings",
  "/v1/speech-synthesis",
  "/v1/semantic-search",
  "/v1/review/items",
  "/v1/listening-inbox/items",
]) {
  if (!paths.includes(required)) throw new Error(`active listening path missing: ${required}`);
}
for (const prefix of [
  "/v1/coach",
  "/v1/realtime",
  "/v1/production-corpus",
  "/v1/production-gap",
  "/v1/personal-expression",
  "/v1/reading",
  "/v1/speaking",
  "/v1/writing",
  "/v1/recordings",
  "/v1/recording-transcriptions",
  "/v1/shadowing",
  "/v1/anki",
]) {
  if (paths.some(path => path === prefix || path.startsWith(`${prefix}/`))) {
    throw new Error(`retired product path remains in OpenAPI: ${prefix}`);
  }
}
for (const retired of [
  "HuntingCandidate",
  "UpgradeSuggestion",
  "RecordingAsset",
  "ShadowingComparison",
  "SemanticTask",
  "CoachDashboard",
  "ContentDifficultyProfile",
  "ProductionCorpus",
  "PersonalExpression",
  "RealtimeConversation",
]) {
  if (schemas.includes(retired)) throw new Error(`retired schema remains in OpenAPI: ${retired}`);
}
const lines = openapi.split("\n");
const llmUseStart = lines.indexOf("    LlmUse:");
if (llmUseStart < 0) throw new Error("retained LlmUse schema missing");
let llmUseEnd = llmUseStart + 1;
while (llmUseEnd < lines.length && !/^    [A-Za-z][A-Za-z0-9_]*:\s*$/.test(lines[llmUseEnd])) llmUseEnd++;
const llmUseBlock = lines.slice(llmUseStart, llmUseEnd).join("\n");
if (!llmUseBlock.includes("enum: [sense_group_partition]") || /rubric_generation|semantic_judgment/.test(llmUseBlock)) {
  throw new Error("LlmUse must contain only the retained sense_group_partition use");
}
const learningObservationStart = lines.indexOf("    LearningObservation:");
if (learningObservationStart < 0) throw new Error("retained LearningObservation schema missing");
let learningObservationEnd = learningObservationStart + 1;
while (learningObservationEnd < lines.length && !/^    [A-Za-z][A-Za-z0-9_]*:\s*$/.test(lines[learningObservationEnd])) learningObservationEnd++;
const learningObservationBlock = lines.slice(learningObservationStart, learningObservationEnd).join("\n");
const taskTypeEnum = learningObservationBlock.match(/^        task_type: \{ enum: \[([^\]]+)\] \}$/m)?.[1]
  .split(",")
  .map(value => value.trim());
assertEqual(taskTypeEnum, ["context_marking", "cloze", "dictation", "subtitle_fade", "review_recall"], "listening task type enum");
if (!openapi.includes("Content Package v3 carrier") || openapi.includes("Content Package v2 carrier")) {
  throw new Error("package installation must describe the active Content Package v3 carrier");
}
if (/^\s+(familiar_material|fit):/m.test(openapi)) {
  throw new Error("retired derived-coaching fields remain in the wire contract");
}
for (const active of ["/v1/speech-synthesis/capability", "/v1/speech-synthesis/cache", "/v1/semantic-embedding/capability", "/v1/corpus/search"]) {
  if (!paths.includes(active)) throw new Error(`retained listening foundation missing: ${active}`);
}

for (const operation of ["installMaterialPackage", "listLearningEditions", "deleteLearningEdition", "adoptLearningEdition"]) {
  if (!operationIds.includes(operation)) throw new Error(`package lifecycle operation missing: ${operation}`);
  if (!client.includes(`${operation}(`)) throw new Error(`generated package client method missing: ${operation}`);
}
for (const component of ["InstallMaterialPackageRequest", "AdoptLearningEditionRequest", "LearningEditionDetails", "LearningEditionResource", "LearningEditionRendition"]) {
  if (!schemas.includes(component)) throw new Error(`package lifecycle schema missing: ${component}`);
}
for (const component of ["DocumentRendition", "DocumentRenditionInput"]) {
  if (!schemas.includes(component)) throw new Error(`document material schema missing: ${component}`);
}
if (!schemas.includes("MaterialCapability")) throw new Error("MaterialCapability enum schema missing");
const componentSchemaBlock = name => {
  const heading = lines.indexOf(`    ${name}:`);
  if (heading < 0) throw new Error(`OpenAPI schema not found: ${name}`);
  let end = heading + 1;
  while (end < lines.length && !/^    [A-Za-z][A-Za-z0-9_]*:\s*$/.test(lines[end])) end++;
  return lines.slice(heading, end);
};
const schemaProperties = name => {
  const block = componentSchemaBlock(name);
  const properties = block.findIndex(line => line === "      properties:");
  if (properties < 0) return [];
  return sortedUnique(block.slice(properties + 1).flatMap(line => {
    const match = line.match(/^        ([A-Za-z][A-Za-z0-9_]*):/);
    return match ? [match[1]] : [];
  }));
};
const typescriptProperties = name => {
  const match = client.match(new RegExp(`export interface ${name} \\{([\\s\\S]*?)\\n\\}`));
  if (!match) throw new Error(`generated TypeScript interface missing: ${name}`);
  return sortedUnique([...match[1].matchAll(/^  ([A-Za-z][A-Za-z0-9_]*)\??:/gm)].map(value => value[1]));
};
for (const component of ["InstallMaterialPackageRequest", "AdoptLearningEditionRequest", "LearningEditionDetails", "LearningEditionResource", "LearningEditionRendition"]) {
  assertEqual(typescriptProperties(component), schemaProperties(component), `${component} properties`);
}
const materialCapabilityValues = componentSchemaBlock("MaterialCapability")
  .join("\n")
  .match(/enum:\s*\[([^\]]+)\]/)?.[1]
  .split(",")
  .map(value => value.trim());
const generatedMaterialCapability = client.match(/export type MaterialCapability = ([^;]+);/)?.[1];
const generatedMaterialCapabilityValues = generatedMaterialCapability == null
  ? []
  : [...generatedMaterialCapability.matchAll(/"([^"]+)"/g)].map(value => value[1]);
assertEqual(generatedMaterialCapabilityValues, materialCapabilityValues ?? [], "MaterialCapability enum");
const editionSchema = componentSchemaBlock("LearningEditionDetails");
if (!editionSchema.some(line => line.trim() === "- available_capabilities" || /required:\s*\[[^\]]*available_capabilities/.test(line))) {
  throw new Error("LearningEditionDetails.available_capabilities must be required");
}
const availableCapabilitiesIndex = editionSchema.indexOf("        available_capabilities:");
if (availableCapabilitiesIndex < 0) throw new Error("LearningEditionDetails.available_capabilities missing");
let availableCapabilitiesEnd = availableCapabilitiesIndex + 1;
while (availableCapabilitiesEnd < editionSchema.length && !(editionSchema[availableCapabilitiesEnd].startsWith("        ") && !editionSchema[availableCapabilitiesEnd].startsWith("          "))) availableCapabilitiesEnd++;
const availableCapabilitiesSchema = editionSchema.slice(availableCapabilitiesIndex, availableCapabilitiesEnd).join("\n");
if (!availableCapabilitiesSchema.includes("type: array") || !availableCapabilitiesSchema.includes("#/components/schemas/MaterialCapability")) {
  throw new Error("LearningEditionDetails.available_capabilities must be an array of MaterialCapability values");
}
if (!client.includes("available_capabilities: MaterialCapability[];")) {
  throw new Error("generated LearningEditionDetails must expose available_capabilities as a typed array");
}
for (const field of ["adopted_at_ms", "content_language"]) {
  if (!new RegExp(`^  ${field}: [^\\n]*\\| null;$`, "m").test(client)) {
    throw new Error(`generated package DTO must preserve nullable ${field}`);
  }
}
const responseTypes = client.slice(client.indexOf("export interface LearningEditionResource"), client.indexOf("export interface LocalPackageLifecycleApi"));
if (/^\s*(package_path|media_path|file_path|local_path|manifest|release_json|payload|payload_bytes|payload_blob|bytes|blob|blob_path|digest|size|size_bytes|dependency|dependencies|provenance|tool_id|model_id|provider_id):/m.test(responseTypes)) {
  throw new Error("package lifecycle response types must not expose private artifact details");
}
for (const item of examples) {
  if (item.version !== 1 || (!item.command && !item.event)) throw new Error("invalid player example");
}
console.log(`Validated player, event, and Core ${version} contracts: ${paths.length} paths, ${operationIds.length} operations, ${schemas.length} schemas, ${examples.length} examples.`);
' "$root/contracts/player-adapter/player-contract.schema.json" \
  "$root/contracts/player-adapter/examples.json" \
  "$root/contracts/events/v1.schema.json" \
  "$root/contracts/openapi/v1.yaml" \
  "$root/contracts/generated/local-api-v1.ts" \
  "$root/crates/api-http/src/lib.rs" \
  "$root/crates/api-http/src/routes/router.rs"
