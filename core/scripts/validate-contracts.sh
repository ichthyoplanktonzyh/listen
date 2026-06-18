#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

PYTHONPYCACHEPREFIX="$tmp/pycache" python3 -m py_compile \
  "$root/scripts/evaluate-word-timelines.py" \
  "$root/scripts/lltimeline-resource.py"
word_report="$(
  python3 "$root/scripts/evaluate-word-timelines.py" compare \
    --baseline "$root/testdata/word-timelines/baseline-v1.json" \
    --candidate "$root/testdata/word-timelines/candidate-v1.json" \
    --gold "$root/testdata/word-timelines/gold-v1.json" \
    --markdown-output "$tmp/word-timeline-report.md"
)"
lltimeline_report="$(
  python3 "$root/scripts/lltimeline-resource.py" validate \
    "$root/testdata/lltimeline/v1-minimal.lltimeline.json"
)"
node -e '
const fs = require("fs");
const report = JSON.parse(process.argv[1]);
const md = fs.readFileSync(process.argv[2], "utf8");
if (report.report_version !== 1) throw new Error("word timeline report version missing");
if (report.weak_metrics.matched_word_count !== 2) throw new Error("word timeline match count failed");
if (report.weak_metrics.offsets.start_offset_ms.mean !== -5) throw new Error("start offset mean failed");
if (report.gold_metrics.start_mae_ms !== 5) throw new Error("gold start MAE failed");
if (!md.includes("Word Timeline Evaluation")) throw new Error("word timeline markdown missing");
' "$word_report" "$tmp/word-timeline-report.md"

node -e '
const report = JSON.parse(process.argv[1]);
if (report.schema !== "llplayer.timeline.v1") throw new Error("LLTimeline schema missing");
if (report.segments !== 1) throw new Error("LLTimeline segment fixture failed");
if (report.word_timelines !== 1) throw new Error("LLTimeline word timeline fixture failed");
if (report.active_word_timeline_id !== "timeline-fixture") throw new Error("LLTimeline active timeline fixture failed");
' "$lltimeline_report"

node -e '
const fs = require("fs");
const schema = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const examples = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const events = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
const openapi = fs.readFileSync(process.argv[4], "utf8");
const client = fs.readFileSync(process.argv[5], "utf8");
if (schema.$defs.command.properties.version.const !== 1) throw new Error("command version missing");
if (schema.$defs.event.properties.version.const !== 1) throw new Error("event version missing");
if (!Array.isArray(examples) || examples.length === 0) throw new Error("examples missing");
if (events.properties.version.const !== 1) throw new Error("event schema version missing");
for (const path of ["/v1/health", "/v1/media", "/v1/lltimeline/import", "/v1/media/{media_id}/progress", "/v1/media/{media_id}/subtitles", "/v1/subtitles/{track_id}", "/v1/subtitles/{track_id}/export", "/v1/pronunciation/providers", "/v1/pronunciation/lookup", "/v1/pronunciation/analyze-sentence", "/v1/pronunciation/rules", "/v1/subtitles/{track_id}/pronunciation", "/v1/subtitles/{track_id}/pronunciation-analysis", "/v1/subtitles/{track_id}/word-timings", "/v1/subtitles/{track_id}/word-timelines", "/v1/subtitles/{track_id}/word-timelines/summary", "/v1/subtitles/{track_id}/lltimeline/export", "/v1/word-timelines/{timeline_id}", "/v1/word-timelines/{timeline_id}/activate", "/v1/word-timelines/{timeline_id}/publish", "/v1/word-timelines/{timeline_id}/archive", "/v1/word-timelines/{timeline_id}/export", "/v1/speech/jobs", "/v1/speech/jobs/{job_id}", "/v1/speech/jobs/{job_id}/cancel", "/v1/speech/jobs/{job_id}/retry", "/v1/lexical-entries", "/v1/lexical-normalization", "/v1/sentences/{sentence_id}/phrase-candidates", "/v1/learning-resources", "/v1/subtitle-search", "/v1/word-profiles", "/v1/word-profiles/batch", "/v1/word-observations", "/v1/vocabulary", "/v1/vocabulary/export", "/v1/vocabulary/import", "/v1/vocabulary/import-external", "/v1/word-profiles/{profile_id}/details", "/v1/word-profiles/{profile_id}/learning-content", "/v1/media/{media_id}/availability", "/v1/events", "/v1/dictionary", "/v1/sentences/{sentence_id}/diagnosis", "/v1/transcription/providers", "/v1/transcription/models", "/v1/transcription/jobs", "/v1/transcription/jobs/{job_id}", "/v1/transcription/jobs/{job_id}/cancel", "/v1/transcription/jobs/{job_id}/retry", "/v1/transcription/jobs/{job_id}/archive", "/v1/phonetic-analysis/providers", "/v1/phonetic-analysis/models", "/v1/phonetic-analysis/jobs", "/v1/subtitles/{track_id}/phonetic-analyses", "/v1/phonetic-analysis/{analysis_id}/findings", "/v1/phonetic-analysis/findings/{finding_id}/feedback"]) {
  if (!openapi.includes(path + ":")) throw new Error(`OpenAPI missing ${path}`);
}
for (const operation of ["health()", "registerMedia(", "importLLTimeline(", "updateProgress(", "importSubtitle(", "readSubtitle(", "exportSubtitle(", "pronunciationProviders(", "pronunciationLookup(", "analyzeSentencePronunciation(", "pronunciationRules(", "trackPronunciation(", "generateTrackPronunciation(", "trackWordTimings(", "generateTrackWordTimings(", "trackWordTimelines(", "trackWordTimelineSummaries(", "createTrackWordTimeline(", "exportTrackLLTimeline(", "wordTimeline(", "activateWordTimeline(", "publishWordTimeline(", "archiveWordTimeline(", "exportWordTimeline(", "deleteWordTimeline(", "speechBatchJobs(", "createSpeechBatchJob(", "speechBatchJob(", "cancelSpeechBatchJob(", "retrySpeechBatchJob(", "listLexicalEntries(", "upsertLexicalEntry(", "normalizeLexical(", "correctLemma(", "phraseCandidates(", "learningResources(", "installLearningResource(", "removeLearningResource(", "searchSubtitles(", "downloadSubtitle(", "transcriptionProviders(", "transcriptionModels(", "installTranscriptionModel(", "registerCustomTranscriptionModel(", "transcriptionJobs(", "createTranscriptionJob(", "transcriptionJob(", "cancelTranscriptionJob(", "retryTranscriptionJob(", "archiveTranscriptionJob(", "phoneticAnalysisProviders(", "phoneticAnalysisModels(", "installPhoneticAnalysisModel(", "registerCustomPhoneticAnalysisModel(", "cancelPhoneticAnalysisModelInstall(", "deletePhoneticAnalysisModel(", "phoneticAnalysisJobs(", "createPhoneticAnalysisJob(", "phoneticAnalysisJob(", "cancelPhoneticAnalysisJob(", "retryPhoneticAnalysisJob(", "trackPhoneticAnalyses(", "phoneticAnalysisFindings(", "updatePhoneticFindingFeedback(", "updateWordProfile(", "readWordProfiles(", "createWordObservation(", "listVocabulary(", "wordDetails(", "updateWordLearningContent(", "exportVocabulary(", "importVocabulary(", "importExternalVocabulary(", "updateMediaAvailability(", "dictionaryLookup(", "diagnoseSentence("]) {
  if (!client.includes(operation)) throw new Error(`client experiment missing ${operation}`);
}
for (const schema of ["WordTiming", "WordTimeline", "WordTimelineSummary", "CreateWordTimeline", "LLTimelineDocument", "LexicalEntry", "LexicalEntryDetails", "LexicalNormalization", "LearningResource", "SubtitleSearchRequest", "SubtitleSearchResult"]) {
  if (!openapi.includes(`    ${schema}:`)) throw new Error(`missing OpenAPI schema ${schema}`);
}
if (!openapi.includes("version: { enum: [1, 2, 3, 4] }")) throw new Error("vocabulary asset v4 missing");
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
  "$root/contracts/generated/local-api-v1.ts"
