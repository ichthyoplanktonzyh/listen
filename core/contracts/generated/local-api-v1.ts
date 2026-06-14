// Handwritten client generation experiment for contracts/openapi/v1.yaml.
// Replace with generated Dart output when the Flutter desktop integration begins.
export type MediaKind = "video" | "audio";
export type WordStatus =
  | "unknown_meaning"
  | "known_not_recognized"
  | "known_recognized";

export interface ErrorBody {
  code: string;
  message: string;
  correlation_id: string;
  retryable: boolean;
}

export interface RegisterMedia {
  path: string;
  fingerprint: string;
  title: string;
  kind: MediaKind;
  duration_ms?: number | null;
}

export interface Health {
  status: "ok";
  api_version: 1;
}

export interface MediaItem {
  id: string;
  path: string;
  fingerprint: string;
  title: string;
  kind: MediaKind;
  duration: number | null;
  created_at_ms: number;
  updated_at_ms: number;
  availability: "available" | "missing" | "archived";
}

export interface Progress {
  position_ms: number | null;
}

export type SubtitleTokenKind = "word" | "whitespace" | "punctuation" | "other";

export interface SubtitleToken {
  index: number;
  kind: SubtitleTokenKind;
  text: string;
  normalized: string | null;
  start_char: number;
  end_char: number;
}

export interface SubtitleSentence {
  id: string;
  index: number;
  start: number;
  end: number;
  original_text: string;
  display_text: string;
  tokens: SubtitleToken[];
}

export interface SubtitleTrack {
  id: string;
  media_id: string;
  fingerprint: string;
  language: string | null;
  source: string;
  sentences: SubtitleSentence[];
}

export type TimingSource =
  | "asr_reported"
  | "forced_aligned"
  | "estimated"
  | "user_adjusted";

export interface WordTiming {
  sentence_id: string;
  token_index: number;
  text: string;
  start_ms: number;
  end_ms: number;
  confidence: number | null;
  timing_source: TimingSource;
  provider_id: string;
  provider_version: string;
}

export interface PronunciationProviderInfo {
  id: string;
  display_name: string;
  version: string;
  languages: string[];
  accents: string[];
  phoneme_sets: string[];
  supports_context: boolean;
  supports_variants: boolean;
  supports_stress: boolean;
  supports_token_mapping: boolean;
  available: boolean;
  degraded: boolean;
  diagnostic: string | null;
}

export type SpeechBatchKind = "pronunciation_analysis" | "word_timings";
export type SpeechBatchStatus =
  | "queued"
  | "running"
  | "completed"
  | "cancelled"
  | "failed";

export interface SpeechBatchJob {
  id: string;
  track_id: string;
  kind: SpeechBatchKind;
  status: SpeechBatchStatus;
  processed: number;
  total: number;
  result_count: number;
  error: string | null;
  retry_of_job_id: string | null;
  created_at_ms: number;
  updated_at_ms: number;
}

export interface UpdateWordProfile {
  language: string;
  lemma: string;
  display_form: string;
  status?: WordStatus | null;
  source?: unknown | null;
}

export interface WordProfile extends UpdateWordProfile {
  id: string;
  normalized_lemma: string;
  status: WordStatus | null;
  updated_at_ms: number;
  user_definition: string | null;
  personal_note: string | null;
  learning_updated_at_ms: number;
}

export type LexicalEntryKind = "word" | "phrase";

export interface LexicalEntry {
  id: string;
  language: string;
  kind: LexicalEntryKind;
  canonical_form: string;
  normalized_form: string;
  display_form: string;
  status: WordStatus | null;
  user_definition: string | null;
  personal_note: string | null;
  normalization_provider: string;
  normalization_version: string;
  user_corrected: boolean;
  updated_at_ms: number;
  learning_updated_at_ms: number;
}

export interface LexicalEntryDetails {
  entry: LexicalEntry;
  history: unknown[];
  occurrences: unknown[];
}

export interface LexicalNormalization {
  original: string;
  normalized: string;
  provider: string;
  version: string;
  user_corrected: boolean;
}

export interface LearningResource {
  id: string;
  display_name: string;
  version: string;
  source_url: string;
  license: string;
  checksum_sha256: string;
  size_bytes: number;
  local_path: string | null;
  state: "available" | "installing" | "installed" | "failed";
  installed_bytes: number;
  error: string | null;
  updated_at_ms: number;
}

export interface SubtitleSearchResult {
  id: string;
  file_id: number;
  language: string;
  release: string;
  source: string;
  rating: number;
  download_count: number;
}

export interface DictionaryPhonetic {
  text: string;
  region: string | null;
  audio_url: string | null;
}

export interface DictionaryLookup {
  query: string;
  lemma: string;
  definitions: Array<{ part_of_speech: string | null; text: string }>;
  phonetics: DictionaryPhonetic[];
  provider: string;
  cached_at_ms: number;
}

export interface DictionaryLookupBundle {
  query: string;
  normalized_lemma: string;
  results: Array<{
    provider: {
      id: string;
      display_name: string;
      supported_languages: string[];
      provides_definitions: boolean;
      provides_phonetics: boolean;
      provides_audio: boolean;
      offline: boolean;
    };
    lookup: DictionaryLookup | null;
    error: string | null;
  }>;
}

export class LocalApiV1 {
  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
  ) {}

  health(): Promise<Health> {
    return this.request("/v1/health", {}, false);
  }

  registerMedia(input: RegisterMedia): Promise<MediaItem> {
    return this.request("/v1/media", { method: "POST", body: JSON.stringify(input) });
  }

  readMedia(mediaId: string): Promise<MediaItem> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}`);
  }

  readProgress(mediaId: string): Promise<Progress> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/progress`);
  }

  updateProgress(mediaId: string, positionMs: number): Promise<Progress> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/progress`, {
      method: "PUT",
      body: JSON.stringify({ position_ms: positionMs }),
    });
  }

  importSubtitle(mediaId: string, path: string, language?: string): Promise<SubtitleTrack> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/subtitles`, {
      method: "POST",
      body: JSON.stringify({ path, language }),
    });
  }

  readSubtitle(trackId: string): Promise<SubtitleTrack> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}`);
  }

  exportSubtitle(trackId: string): Promise<string> {
    return this.requestText(`/v1/subtitles/${encodeURIComponent(trackId)}/export?format=srt`);
  }

  pronunciationProviders(): Promise<PronunciationProviderInfo[]> {
    return this.request("/v1/pronunciation/providers");
  }

  pronunciationLookup(word: string): Promise<unknown> {
    return this.request(`/v1/pronunciation/lookup?word=${encodeURIComponent(word)}`);
  }

  analyzeSentencePronunciation(sentenceId: string): Promise<unknown> {
    return this.request("/v1/pronunciation/analyze-sentence", {
      method: "POST", body: JSON.stringify({ sentence_id: sentenceId }),
    });
  }

  pronunciationRules(): Promise<unknown> {
    return this.request("/v1/pronunciation/rules");
  }

  trackPronunciation(trackId: string): Promise<unknown[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/pronunciation`);
  }

  generateTrackPronunciation(trackId: string): Promise<unknown[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/pronunciation-analysis`, {
      method: "POST",
    });
  }

  trackWordTimings(trackId: string): Promise<WordTiming[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/word-timings`);
  }

  generateTrackWordTimings(trackId: string): Promise<WordTiming[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/word-timings`, {
      method: "POST",
      body: JSON.stringify({ timings: [] }),
    });
  }

  speechBatchJobs(): Promise<SpeechBatchJob[]> {
    return this.request("/v1/speech/jobs");
  }

  createSpeechBatchJob(trackId: string, kind: SpeechBatchKind): Promise<SpeechBatchJob> {
    return this.request("/v1/speech/jobs", {
      method: "POST",
      body: JSON.stringify({ track_id: trackId, kind }),
    });
  }

  speechBatchJob(jobId: string): Promise<SpeechBatchJob> {
    return this.request(`/v1/speech/jobs/${encodeURIComponent(jobId)}`);
  }

  cancelSpeechBatchJob(jobId: string): Promise<SpeechBatchJob> {
    return this.request(`/v1/speech/jobs/${encodeURIComponent(jobId)}/cancel`, {
      method: "POST",
    });
  }

  retrySpeechBatchJob(jobId: string): Promise<SpeechBatchJob> {
    return this.request(`/v1/speech/jobs/${encodeURIComponent(jobId)}/retry`, {
      method: "POST",
    });
  }

  listLexicalEntries(): Promise<LexicalEntryDetails[]> {
    return this.request("/v1/lexical-entries?language=en&limit=200&offset=0");
  }

  upsertLexicalEntry(input: unknown): Promise<LexicalEntryDetails> {
    return this.request("/v1/lexical-entries", { method: "PUT", body: JSON.stringify(input) });
  }

  normalizeLexical(value: string): Promise<LexicalNormalization> {
    return this.request("/v1/lexical-normalization", {
      method: "POST", body: JSON.stringify({ language: "en", value }),
    });
  }

  correctLemma(original: string, corrected: string): Promise<LexicalNormalization> {
    return this.request("/v1/lexical-normalization/correct", {
      method: "POST", body: JSON.stringify({ language: "en", original, corrected }),
    });
  }

  phraseCandidates(sentenceId: string): Promise<unknown[]> {
    return this.request(`/v1/sentences/${encodeURIComponent(sentenceId)}/phrase-candidates`);
  }

  learningResources(): Promise<LearningResource[]> {
    return this.request("/v1/learning-resources");
  }

  installLearningResource(id: string): Promise<LearningResource> {
    return this.request(`/v1/learning-resources/${encodeURIComponent(id)}/install`, {
      method: "POST",
    });
  }

  removeLearningResource(id: string): Promise<LearningResource> {
    return this.request(`/v1/learning-resources/${encodeURIComponent(id)}`, {
      method: "DELETE",
    });
  }

  searchSubtitles(input: unknown): Promise<SubtitleSearchResult[]> {
    return this.request("/v1/subtitle-search", { method: "POST", body: JSON.stringify(input) });
  }

  downloadSubtitle(input: unknown): Promise<string> {
    return this.requestText("/v1/subtitle-search/download", {
      method: "POST", body: JSON.stringify(input),
    });
  }

  transcriptionProviders(): Promise<unknown[]> {
    return this.request("/v1/transcription/providers");
  }

  transcriptionModels(): Promise<unknown[]> {
    return this.request("/v1/transcription/models");
  }

  installTranscriptionModel(model_id: string): Promise<unknown> {
    return this.request("/v1/transcription/models/install", {
      method: "POST",
      body: JSON.stringify({ model_id }),
    });
  }

  registerCustomTranscriptionModel(path: string): Promise<unknown> {
    return this.request("/v1/transcription/models/register-custom", {
      method: "POST",
      body: JSON.stringify({ path }),
    });
  }

  transcriptionJobs(): Promise<unknown[]> {
    return this.request("/v1/transcription/jobs");
  }

  createTranscriptionJob(input: unknown): Promise<unknown> {
    return this.request("/v1/transcription/jobs", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  phoneticAnalysisProviders(): Promise<unknown[]> {
    return this.request("/v1/phonetic-analysis/providers");
  }

  phoneticAnalysisModels(): Promise<unknown[]> {
    return this.request("/v1/phonetic-analysis/models");
  }

  installPhoneticAnalysisModel(modelId: string): Promise<unknown> {
    return this.request("/v1/phonetic-analysis/models/install", {
      method: "POST",
      body: JSON.stringify({ model_id: modelId }),
    });
  }

  registerCustomPhoneticAnalysisModel(path: string): Promise<unknown> {
    return this.request("/v1/phonetic-analysis/models/register-custom", {
      method: "POST",
      body: JSON.stringify({ path }),
    });
  }

  cancelPhoneticAnalysisModelInstall(modelId: string): Promise<unknown> {
    return this.request(
      `/v1/phonetic-analysis/models/${encodeURIComponent(modelId)}/cancel-install`,
      { method: "POST" },
    );
  }

  deletePhoneticAnalysisModel(modelId: string): Promise<void> {
    return this.request(`/v1/phonetic-analysis/models/${encodeURIComponent(modelId)}`, {
      method: "DELETE",
    });
  }

  phoneticAnalysisJobs(): Promise<unknown[]> {
    return this.request("/v1/phonetic-analysis/jobs");
  }

  createPhoneticAnalysisJob(input: unknown): Promise<unknown> {
    return this.request("/v1/phonetic-analysis/jobs", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  phoneticAnalysisJob(jobId: string): Promise<unknown> {
    return this.request(`/v1/phonetic-analysis/jobs/${encodeURIComponent(jobId)}`);
  }

  cancelPhoneticAnalysisJob(jobId: string): Promise<unknown> {
    return this.request(`/v1/phonetic-analysis/jobs/${encodeURIComponent(jobId)}/cancel`, {
      method: "POST",
    });
  }

  retryPhoneticAnalysisJob(jobId: string): Promise<unknown> {
    return this.request(`/v1/phonetic-analysis/jobs/${encodeURIComponent(jobId)}/retry`, {
      method: "POST",
    });
  }

  trackPhoneticAnalyses(trackId: string): Promise<unknown[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/phonetic-analyses`);
  }

  phoneticAnalysisFindings(analysisId: string): Promise<unknown[]> {
    return this.request(`/v1/phonetic-analysis/${encodeURIComponent(analysisId)}/findings`);
  }

  updatePhoneticFindingFeedback(
    findingId: string,
    value: "confirmed" | "rejected" | "ignored",
    note: string | null,
  ): Promise<unknown> {
    return this.request(
      `/v1/phonetic-analysis/findings/${encodeURIComponent(findingId)}/feedback`,
      { method: "PUT", body: JSON.stringify({ value, note }) },
    );
  }

  readWordProfile(language: string, lemma: string): Promise<WordProfile | null> {
    const query = new URLSearchParams({ language, lemma });
    return this.request(`/v1/word-profiles?${query}`);
  }

  updateWordProfile(input: UpdateWordProfile): Promise<WordProfile> {
    return this.request("/v1/word-profiles", {
      method: "PUT",
      body: JSON.stringify(input),
    });
  }

  readWordProfiles(language: string, lemmas: string[]): Promise<WordProfile[]> {
    return this.request("/v1/word-profiles/batch", {
      method: "POST",
      body: JSON.stringify({ language, lemmas }),
    });
  }

  createWordObservation(input: {
    word_profile_id: string;
    sentence_id: string;
    original_form: string;
    result: "recognized_in_context" | "not_recognized_in_context";
  }): Promise<unknown> {
    return this.request("/v1/word-observations", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  listVocabulary(status: WordStatus, search = ""): Promise<unknown[]> {
    const query = new URLSearchParams({ language: "en", status, search });
    return this.request(`/v1/vocabulary?${query}`);
  }

  wordDetails(profileId: string): Promise<unknown> {
    return this.request(`/v1/word-profiles/${encodeURIComponent(profileId)}/details`);
  }

  updateWordLearningContent(
    profileId: string,
    userDefinition: string | null,
    personalNote: string | null,
  ): Promise<unknown> {
    return this.request(`/v1/word-profiles/${encodeURIComponent(profileId)}/learning-content`, {
      method: "PUT",
      body: JSON.stringify({ user_definition: userDefinition, personal_note: personalNote }),
    });
  }

  exportVocabulary(): Promise<unknown> {
    return this.request("/v1/vocabulary/export");
  }

  importVocabulary(bundle: unknown): Promise<unknown> {
    return this.request("/v1/vocabulary/import", {
      method: "POST",
      body: JSON.stringify(bundle),
    });
  }

  importExternalVocabulary(input: unknown): Promise<unknown> {
    return this.request("/v1/vocabulary/import-external", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  updateMediaAvailability(
    mediaId: string,
    availability: "available" | "missing" | "archived",
  ): Promise<MediaItem> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/availability`, {
      method: "PUT",
      body: JSON.stringify({ availability }),
    });
  }

  dictionaryLookup(language: string, lemma: string): Promise<DictionaryLookupBundle> {
    const query = new URLSearchParams({ language, lemma });
    return this.request(`/v1/dictionary?${query}`);
  }

  diagnoseSentence(sentenceId: string): Promise<unknown> {
    return this.request(`/v1/sentences/${encodeURIComponent(sentenceId)}/diagnosis`);
  }

  private async request<T>(
    path: string,
    init: RequestInit = {},
    authenticated = true,
  ): Promise<T> {
    const headers = new Headers(init.headers);
    headers.set("content-type", "application/json");
    if (authenticated) headers.set("authorization", `Bearer ${this.token}`);
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers });
    if (!response.ok) throw (await response.json()) as ErrorBody;
    return (await response.json()) as T;
  }

  private async requestText(path: string, init: RequestInit = {}): Promise<string> {
    const headers = new Headers(init.headers);
    headers.set("authorization", `Bearer ${this.token}`);
    if (init.body) headers.set("content-type", "application/json");
    const response = await fetch(`${this.baseUrl}${path}`, {
      ...init,
      headers,
    });
    if (!response.ok) throw (await response.json()) as ErrorBody;
    return response.text();
  }
}
