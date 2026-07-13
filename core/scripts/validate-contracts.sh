#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m py_compile \
  "$root/scripts/benchmark-datasets.py" \
  "$root/scripts/evaluate-word-timelines.py" \
  "$root/scripts/forced-align/mfa-align-cli.py" \
  "$root/scripts/lltimeline_common.py" \
  "$root/scripts/lltimeline-resource.py" \
  "$root/scripts/syntactic-analysis/syntax-sidecar.py" \
  "$root/scripts/syntactic-analysis/evaluate_provider.py" \
  "$root/scripts/syntactic-analysis/real_media_qa.py" \
  "$root/scripts/syntactic-analysis/test_real_media_qa.py" \
  "$root/scripts/syntactic-analysis/test_evaluate_provider.py" \
  "$root/scripts/syntactic-analysis/test_syntax_sidecar_contract.py" \
  "$root/scripts/validate-syntactic-fixtures.py" \
  "$root/scripts/timeline-production/production_pipeline.py" \
  "$root/scripts/timeline-production/whisperx-align-request.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/test_lltimeline_common.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/forced-align/test_align_cli_contract.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/forced-align/test_mfa_align_cli_contract.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/syntactic-analysis/test_syntax_sidecar_contract.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/syntactic-analysis/test_evaluate_provider.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/syntactic-analysis/test_real_media_qa.py"
PYTHONPYCACHEPREFIX="$tmp/pycache" python3 "$root/scripts/validate-syntactic-fixtures.py"
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
production_output="$tmp/whisperx-sample.lltimeline.json"
media_input="$tmp/input.wav"
media_out="$tmp/media"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i sine=frequency=440:duration=0.25 \
  -ac 1 -ar 16000 -sample_fmt s16 "$media_input"
prepare_report="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" prepare-media \
    --input "$media_input" \
    --output-dir "$media_out"
)"
whisperx_dry_run="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" run-whisperx \
    --input "$media_out/audio-16k-mono.wav" \
    --output-dir "$tmp/whisperx" \
    --whisperx-command 'whisperx {input} --model {model} --output_dir {output_dir} --output_format json --language {language}' \
    --dry-run
)"
produce_dry_run="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" produce-whisperx \
    --input "$media_input" \
    --output-dir "$tmp/produce" \
    --media-fingerprint "timeline-production-smoke" \
    --media-title "Timeline Production Smoke" \
    --whisperx-command 'whisperx {input} --model {model} --output_dir {output_dir} --output_format json --language {language}' \
    --dry-run
)"
produce_mfa_dry_run="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" produce-whisperx \
    --input "$media_input" \
    --output-dir "$tmp/produce-mfa" \
    --media-fingerprint "timeline-production-smoke" \
    --media-title "Timeline Production Smoke" \
    --whisperx-command 'whisperx {input} --model {model} --output_dir {output_dir} --output_format json --language {language}' \
    --post-aligner mfa \
    --dry-run
)"
apply_mfa_dry_run="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" apply-mfa-alignment \
    --input "$production_output" \
    --audio "$media_out/audio-16k-mono.wav" \
    --output-dir "$tmp/apply-mfa" \
    --dry-run
)"
apply_mms_fa_dry_run="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" apply-mms-fa-alignment \
    --input "$production_output" \
    --audio "$media_out/audio-16k-mono.wav" \
    --output-dir "$tmp/apply-mms-fa" \
    --dry-run
)"
production_report="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" from-whisperx-json \
    --input "$root/testdata/timeline-production/whisperx-sample.json" \
    --output "$production_output" \
    --media-fingerprint "timeline-production-smoke" \
    --media-title "Timeline Production Smoke" \
    --preprocessing-artifacts "$media_out/preprocessing-artifacts.json"
)"
production_validation="$(
  python3 "$root/scripts/lltimeline-resource.py" validate "$production_output"
)"
production_quality_report="$tmp/production-report.json"
production_quality="$(
  python3 "$root/scripts/timeline-production/production_pipeline.py" report \
    --input "$production_output" \
    --output "$production_quality_report"
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

node -e '
const fs = require("fs");
const prepare = JSON.parse(process.argv[1]);
const whisperx = JSON.parse(process.argv[2]);
const produce = JSON.parse(process.argv[3]);
const produceMfa = JSON.parse(process.argv[4]);
const applyMfa = JSON.parse(process.argv[5]);
const applyMmsFa = JSON.parse(process.argv[6]);
const production = JSON.parse(process.argv[7]);
const validation = JSON.parse(process.argv[8]);
const quality = JSON.parse(process.argv[9]);
const qualityFile = JSON.parse(fs.readFileSync(process.argv[10], "utf8"));
if (!prepare.artifacts_path.endsWith("preprocessing-artifacts.json")) throw new Error("prepare-media artifact missing");
if (prepare.vocal_isolation !== false) throw new Error("prepare-media vocal isolation default failed");
if (!whisperx.command.includes("whisperx")) throw new Error("run-whisperx dry run command missing");
if (!whisperx.command.includes("--output_format json")) throw new Error("run-whisperx output format missing");
if (!produce.run_whisperx.command.includes("whisperx")) throw new Error("produce-whisperx dry run command missing");
if (produce.convert.media_fingerprint !== "timeline-production-smoke") throw new Error("produce-whisperx convert plan failed");
if (produceMfa.post_align.policy !== "ordered-fallback") throw new Error("produce-whisperx MFA fallback policy missing");
if (produceMfa.post_align.chain.join(",") !== "mfa,mms-fa") throw new Error("produce-whisperx MFA fallback chain failed");
if (!produceMfa.post_align.plans[0].command.includes("mfa-align-cli.py")) throw new Error("produce-whisperx MFA dry run command missing");
if (!produceMfa.post_align.plans[0].command.includes("--strategy align")) throw new Error("produce-whisperx MFA strategy missing");
if (!produceMfa.post_align.plans[1].command.includes("align-cli.py")) throw new Error("produce-whisperx MMS_FA fallback command missing");
if (!applyMfa.command.includes("mfa-align-cli.py")) throw new Error("apply-mfa dry run command missing");
if (!applyMfa.command.includes("english_us_arpa")) throw new Error("apply-mfa default ARPA model missing");
if (!applyMmsFa.command.includes("align-cli.py")) throw new Error("apply-mms-fa dry run command missing");
if (production.segments !== 2) throw new Error("production converter segment count failed");
if (production.words !== 5) throw new Error("production converter word count failed");
if (validation.schema !== "llplayer.timeline.v1") throw new Error("production LLTimeline schema failed");
if (validation.segments !== 2) throw new Error("production LLTimeline validation segments failed");
if (validation.word_timelines !== 1) throw new Error("production LLTimeline validation timelines failed");
if (!quality.output.endsWith("production-report.json")) throw new Error("production quality output missing");
if (quality.segments !== 2) throw new Error("production quality segment count failed");
if (quality.words !== 5) throw new Error("production quality word count failed");
if (quality.ready_for_manual_review !== true) throw new Error("production quality readiness failed");
if (qualityFile.report_version !== 1) throw new Error("production quality report version failed");
if (qualityFile.word_coverage !== 1) throw new Error("production quality coverage failed");
if (qualityFile.quality.valid !== true) throw new Error("production quality validity failed");
' "$prepare_report" "$whisperx_dry_run" "$produce_dry_run" "$produce_mfa_dry_run" "$apply_mfa_dry_run" "$apply_mms_fa_dry_run" "$production_report" "$production_validation" "$production_quality" "$production_quality_report"

node -e '
const fs = require("fs");
const schema = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const examples = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const events = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const openapi = fs.readFileSync(process.argv[4], "utf8");
const client = fs.readFileSync(process.argv[5], "utf8");
const routerSource = fs.readFileSync(process.argv[6], "utf8");
if (schema.$defs.command.properties.version.const !== 1) throw new Error("command version missing");
if (schema.$defs.event.properties.version.const !== 1) throw new Error("event version missing");
if (!Array.isArray(examples) || examples.length === 0) throw new Error("examples missing");
if (events.properties.version.const !== 1) throw new Error("event schema version missing");
for (const path of ["/v1/health", "/v1/media", "/v1/lltimeline/import", "/v1/media/{media_id}/lltimeline/import", "/v1/media/{media_id}/progress", "/v1/media/{media_id}/subtitles", "/v1/subtitles/{track_id}", "/v1/subtitles/{track_id}/archive", "/v1/subtitles/{track_id}/restore", "/v1/subtitles/{track_id}/language", "/v1/subtitles/{track_id}/export", "/v1/pronunciation/providers", "/v1/pronunciation/lookup", "/v1/pronunciation/analyze-sentence", "/v1/pronunciation/rules", "/v1/subtitles/{track_id}/pronunciation", "/v1/subtitles/{track_id}/pronunciation-analysis", "/v1/subtitles/{track_id}/word-timings", "/v1/subtitles/{track_id}/word-timelines", "/v1/subtitles/{track_id}/word-timelines/summary", "/v1/subtitles/{track_id}/lltimeline/export", "/v1/word-timelines/{timeline_id}", "/v1/word-timelines/{timeline_id}/activate", "/v1/word-timelines/{timeline_id}/publish", "/v1/word-timelines/{timeline_id}/archive", "/v1/word-timelines/{timeline_id}/export", "/v1/subtitles/{track_id}/phone-timelines", "/v1/subtitles/{track_id}/phone-timelines/summary", "/v1/phone-timelines/{timeline_id}", "/v1/phone-timelines/{timeline_id}/activate", "/v1/phone-timelines/{timeline_id}/archive", "/v1/phone-timelines/{timeline_id}/export", "/v1/speech/jobs", "/v1/speech/jobs/{job_id}", "/v1/speech/jobs/{job_id}/cancel", "/v1/speech/jobs/{job_id}/retry", "/v1/lexical-entries/batch", "/v1/lexical-entries", "/v1/lexical-entries/{id}", "/v1/lexical-entries/{id}/learning-content", "/v1/lexical-observations", "/v1/lexical-normalization", "/v1/sentences/{sentence_id}/phrase-candidates", "/v1/practice/sessions", "/v1/practice/items", "/v1/practice/attempts", "/v1/practice/attempts/{id}", "/v1/listening/sessions/{id}/complete", "/v1/review/items", "/v1/review/items/{id}", "/v1/review/attempts", "/v1/learning-resources", "/v1/subtitle-search", "/v1/vocabulary", "/v1/vocabulary/export", "/v1/vocabulary/import", "/v1/vocabulary/import-external", "/v1/media/{media_id}/availability", "/v1/events", "/v1/dictionary", "/v1/languages", "/v1/languages/{code}/profile", "/v1/sentences/{sentence_id}/diagnosis", "/v1/transcription/providers", "/v1/transcription/models", "/v1/transcription/jobs", "/v1/transcription/jobs/{job_id}", "/v1/transcription/jobs/{job_id}/cancel", "/v1/transcription/jobs/{job_id}/retry", "/v1/transcription/jobs/{job_id}/archive", "/v1/phonetic-analysis/providers", "/v1/phonetic-analysis/models", "/v1/phonetic-analysis/jobs", "/v1/phonetic-analysis/jobs/clear", "/v1/subtitles/{track_id}/phonetic-analyses", "/v1/phonetic-analysis/{analysis_id}/findings", "/v1/phonetic-analysis/findings/{finding_id}/feedback"]) {
  if (!openapi.includes(path + ":")) throw new Error(`OpenAPI missing ${path}`);
}
const implementedPaths = [...new Set([...routerSource.matchAll(/"((?:\/v1\/)[^"]+)"/g)].map(match => match[1]))].sort();
const documentedPaths = [...new Set([...openapi.matchAll(/^  (\/v1\/[^:]+):/gm)].map(match => match[1]))].sort();
const undocumented = implementedPaths.filter(path => !documentedPaths.includes(path));
const unimplemented = documentedPaths.filter(path => !implementedPaths.includes(path));
if (undocumented.length || unimplemented.length) {
  throw new Error(`OpenAPI route drift\nimplemented but undocumented: ${JSON.stringify(undocumented)}\ndocumented but unimplemented: ${JSON.stringify(unimplemented)}`);
}
for (const operation of ["health()", "registerMedia(", "importLLTimeline(", "importLLTimelineForMedia(", "updateProgress(", "importSubtitle(", "mediaSubtitles(", "readSubtitle(", "archiveSubtitle(", "restoreSubtitle(", "updateTrackLanguage(", "deleteSubtitle(", "exportSubtitle(", "pronunciationProviders(", "pronunciationLookup(", "analyzeSentencePronunciation(", "pronunciationRules(", "trackPronunciation(", "generateTrackPronunciation(", "trackWordTimings(", "generateTrackWordTimings(", "trackWordTimelines(", "trackWordTimelineSummaries(", "createTrackWordTimeline(", "exportTrackLLTimeline(", "wordTimeline(", "activateWordTimeline(", "publishWordTimeline(", "archiveWordTimeline(", "exportWordTimeline(", "deleteWordTimeline(", "trackPhoneTimelines(", "trackPhoneTimelineSummaries(", "phoneTimeline(", "activatePhoneTimeline(", "archivePhoneTimeline(", "exportPhoneTimeline(", "deletePhoneTimeline(", "speechBatchJobs(", "createSpeechBatchJob(", "speechBatchJob(", "cancelSpeechBatchJob(", "retrySpeechBatchJob(", "listLexicalEntries(", "upsertLexicalEntry(", "normalizeLexical(", "correctLemma(", "phraseCandidates(", "createPracticeSession(", "createPracticeItem(", "submitPracticeAttempt(", "practiceAttempt(", "completeListeningSession(", "createReviewItem(", "listDueReviewItems(", "submitReviewAttempt(", "listUpgradeSuggestions(", "upgradeSuggestionHistory(", "confirmUpgradeSuggestion(", "rejectUpgradeSuggestion(", "reviewItem(", "learningResources(", "installLearningResource(", "removeLearningResource(", "searchSubtitles(", "downloadSubtitle(", "transcriptionProviders(", "transcriptionModels(", "installTranscriptionModel(", "registerCustomTranscriptionModel(", "transcriptionJobs(", "createTranscriptionJob(", "transcriptionJob(", "cancelTranscriptionJob(", "retryTranscriptionJob(", "archiveTranscriptionJob(", "phoneticAnalysisProviders(", "phoneticAnalysisModels(", "installPhoneticAnalysisModel(", "registerCustomPhoneticAnalysisModel(", "cancelPhoneticAnalysisModelInstall(", "deletePhoneticAnalysisModel(", "phoneticAnalysisJobs(", "createPhoneticAnalysisJob(", "clearTerminalPhoneticAnalysisJobs(", "phoneticAnalysisJob(", "cancelPhoneticAnalysisJob(", "retryPhoneticAnalysisJob(", "trackPhoneticAnalyses(", "phoneticAnalysisFindings(", "updatePhoneticFindingFeedback(", "readLexicalEntries(", "lexicalEntryDetails(", "updateLexicalLearningContent(", "createLexicalObservation(", "listVocabulary(", "exportVocabulary(", "importVocabulary(", "importExternalVocabulary(", "updateMediaAvailability(", "dictionaryLookup(", "listLanguages(", "languageProfile(", "diagnoseSentence("]) {
  if (!client.includes(operation)) throw new Error(`client experiment missing ${operation}`);
}
for (const schema of ["WordTiming", "WordTimeline", "WordTimelineSummary", "CreateWordTimeline", "LLTimelineDocument", "PhoneTimeline", "PhoneTimelineSummary", "DetectedPhone", "PhoneAlignment", "PhoneticFinding", "LexicalEntry", "LexicalEntryDetails", "LexicalNormalization", "ReviewSchedule", "ReviewAttempt", "ReviewCardKind", "ReviewCard", "ReviewQueueEntry", "ReviewSubmission", "UpgradeSuggestionStatus", "UpgradeSuggestion", "LearningResource", "SubtitleSearchRequest", "SubtitleSearchResult"]) {
  if (!openapi.includes(`    ${schema}:`)) throw new Error(`missing OpenAPI schema ${schema}`);
}
if (!openapi.includes("version: { enum: [5, 6, 7] }")) throw new Error("vocabulary asset versions v5-v7 missing");
if (!openapi.includes("phonetic_finding_feedback:")) throw new Error("phonetic feedback backup missing");
if (!openapi.includes("audio_url: { type: [string, \"null\"] }")) throw new Error("provider pronunciation audio missing");
for (const item of examples) {
  if (item.version !== 1 || (!item.command && !item.event)) throw new Error("invalid example");
}
console.log(`Validated player, event, and OpenAPI contracts with ${examples.length} examples.`);
' "$root/contracts/player-adapter/player-contract.schema.json" \
  "$root/contracts/player-adapter/examples.json" \
  "$root/contracts/events/v1.schema.json" \
  "$root/contracts/openapi/v1.yaml" \
  "$root/contracts/generated/local-api-v1.ts" \
  "$root/crates/api-http/src/lib.rs"
