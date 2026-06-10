#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
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
for (const path of ["/v1/health", "/v1/media", "/v1/media/{media_id}/progress", "/v1/media/{media_id}/subtitles", "/v1/subtitles/{track_id}", "/v1/subtitles/{track_id}/export", "/v1/word-profiles", "/v1/word-profiles/batch", "/v1/word-observations", "/v1/vocabulary", "/v1/vocabulary/export", "/v1/vocabulary/import", "/v1/vocabulary/import-external", "/v1/word-profiles/{profile_id}/details", "/v1/word-profiles/{profile_id}/learning-content", "/v1/media/{media_id}/availability", "/v1/events", "/v1/dictionary", "/v1/sentences/{sentence_id}/diagnosis", "/v1/transcription/providers", "/v1/transcription/models", "/v1/transcription/jobs"]) {
  if (!openapi.includes(path + ":")) throw new Error(`OpenAPI missing ${path}`);
}
for (const operation of ["health()", "registerMedia(", "updateProgress(", "importSubtitle(", "readSubtitle(", "exportSubtitle(", "transcriptionProviders(", "transcriptionModels(", "installTranscriptionModel(", "registerCustomTranscriptionModel(", "transcriptionJobs(", "createTranscriptionJob(", "updateWordProfile(", "readWordProfiles(", "createWordObservation(", "listVocabulary(", "wordDetails(", "updateWordLearningContent(", "exportVocabulary(", "importVocabulary(", "importExternalVocabulary(", "updateMediaAvailability(", "dictionaryLookup(", "diagnoseSentence("]) {
  if (!client.includes(operation)) throw new Error(`client experiment missing ${operation}`);
}
for (const item of examples) {
  if (item.version !== 1 || (!item.command && !item.event)) throw new Error("invalid example");
}
console.log(`Validated player, event, and OpenAPI contracts with ${examples.length} examples.`);
' "$root/contracts/player-adapter/player-contract.schema.json" \
  "$root/contracts/player-adapter/examples.json" \
  "$root/contracts/events/v1.schema.json" \
  "$root/contracts/openapi/v1.yaml" \
  "$root/contracts/generated/local-api-v1.ts"
