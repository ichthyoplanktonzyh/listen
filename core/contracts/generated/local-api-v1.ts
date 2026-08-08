// Handwritten client generation experiment for contracts/openapi/v1.yaml.
// Replace with generated Dart output when the Flutter desktop integration begins.
export type MediaKind = "video" | "audio";
export type LearningStatus =
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
  status: "available" | "archived";
  sentences: SubtitleSentence[];
}

export type CapabilitySupport = "supported" | "approximate" | "unsupported";

export interface LanguageLearningProfile {
  language: string;
  display_name: string;
  script: string;
  tokenization: string;
  lexical_granularities: string[];
  lexical_normalization: string;
  listening_units: string[];
  pronunciation: string;
  sound_features: string[];
  rhythm_prosody: string;
  morphology: string;
  dictionary_providers: string[];
  diagnosis_reasons: string[];
  word_timeline: CapabilitySupport;
  chunk_timeline: CapabilitySupport;
  phone_timeline: CapabilitySupport;
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

export type TimelineCreator = "algorithm" | "user";
export type TimelineStatus = "candidate" | "active" | "archived";

export interface WordTimeline {
  id: string;
  track_id: string;
  media_id: string;
  algorithm_id: string;
  algorithm_version: string;
  config_hash: string;
  parent_timeline_id: string | null;
  created_by: TimelineCreator;
  status: TimelineStatus;
  metrics_json: unknown;
  words: WordTiming[];
  created_at_ms: number;
  updated_at_ms: number;
}

export type WordTimelineLifecycleStage =
  | "algorithm_candidate"
  | "user_adjusted"
  | "published";

export interface WordTimelineSummary {
  id: string;
  track_id: string;
  media_id: string;
  algorithm_id: string;
  algorithm_version: string;
  parent_timeline_id: string | null;
  created_by: TimelineCreator;
  status: TimelineStatus;
  lifecycle_stage: WordTimelineLifecycleStage;
  word_count: number;
  start_ms: number | null;
  end_ms: number | null;
  provider_ids: string[];
  timing_sources: TimingSource[];
  average_confidence: number | null;
  created_at_ms: number;
  updated_at_ms: number;
  can_activate: boolean;
  can_archive: boolean;
  can_delete: boolean;
}

export interface CreateWordTimeline {
  algorithm_id?: string | null;
  algorithm_version?: string | null;
  config_hash?: string | null;
  parent_timeline_id?: string | null;
  created_by?: TimelineCreator | null;
  status?: TimelineStatus | null;
  metrics_json?: unknown | null;
  words: WordTiming[];
}

export type PhoneTimelinePrecision = "detected" | "aligned" | "approximate";
export type PhoneAlignmentKind =
  | "match"
  | "substitution"
  | "insertion"
  | "deletion"
  | "merge";
export type PhoneticFindingStatus =
  | "uncertain"
  | "supported_by_alignment"
  | "detected_in_audio";

export interface DetectedPhone {
  symbol: string;
  phone_set: string;
  start_ms: number;
  end_ms: number;
  confidence: number | null;
  token_index: number | null;
  provider_id: string;
  provider_version: string;
  model_revision: string;
}

export interface PhoneAlignment {
  kind: PhoneAlignmentKind;
  token_start: number | null;
  token_end: number | null;
  canonical_phones: string[];
  detected_phone_start: number | null;
  detected_phone_end: number | null;
  confidence: number;
}

export interface PhoneticFinding {
  id: string;
  analysis_id: string;
  finding_type: string;
  affected_token_start: number;
  affected_token_end: number;
  canonical_phones: string[];
  detected_phones: string[];
  aligned_phone_start: number | null;
  aligned_phone_end: number | null;
  audio_start_ms: number;
  audio_end_ms: number;
  confidence: number;
  evidence: string;
  status: PhoneticFindingStatus;
}

export interface PhoneTimeline {
  id: string;
  track_id: string;
  media_id: string;
  sentence_id: string | null;
  parent_word_timeline_id: string | null;
  parent_phonetic_analysis_id: string | null;
  provider_id: string;
  provider_version: string;
  model_id: string | null;
  model_revision: string | null;
  phone_set: string;
  precision: PhoneTimelinePrecision;
  created_by: TimelineCreator;
  status: TimelineStatus;
  metrics_json: unknown;
  phones: DetectedPhone[];
  alignments: PhoneAlignment[];
  findings: PhoneticFinding[];
  created_at_ms: number;
  updated_at_ms: number;
}

export interface PhoneTimelineSummary {
  id: string;
  track_id: string;
  media_id: string;
  sentence_id: string | null;
  parent_word_timeline_id: string | null;
  parent_phonetic_analysis_id: string | null;
  provider_id: string;
  provider_version: string;
  model_id: string | null;
  model_revision: string | null;
  phone_set: string;
  precision: PhoneTimelinePrecision;
  created_by: TimelineCreator;
  status: TimelineStatus;
  phone_count: number;
  finding_count: number;
  start_ms: number | null;
  end_ms: number | null;
  average_confidence: number | null;
  created_at_ms: number;
  updated_at_ms: number;
  can_activate: boolean;
  can_archive: boolean;
  can_delete: boolean;
}

export type SenseGroupSource =
  | "dependency_parse"
  | "phrase_structure"
  | "language_model"
  | "punctuation"
  | "length_limit"
  | "rule"
  | "user";

export interface SenseGroup {
  id: string;
  sentence_id: string;
  group_index: number;
  start_token_index: number;
  end_token_index: number;
  text: string;
  label: string | null;
  head_token_index: number | null;
  confidence: number;
  sources: SenseGroupSource[];
}

export interface SenseGroupAnalysis {
  id: string;
  track_id: string;
  media_id: string;
  parent_word_timeline_id: string | null;
  provider_id: string;
  provider_version: string;
  algorithm: string;
  status: TimelineStatus;
  created_by: TimelineCreator;
  metrics_json: unknown;
  groups: SenseGroup[];
  created_at_ms: number;
  updated_at_ms: number;
}

export interface LLTimelineDocument {
  schema: "llplayer.timeline.v1";
  metadata: {
    created_at_ms: number;
    generator: { id: string; version: string; mode: string };
    media: {
      id: string;
      fingerprint: string;
      path: string | null;
      title: string;
      duration_ms: number | null;
    };
    language: string | null;
    human_reviewed: boolean;
    extra: unknown;
  };
  segments: Array<{
    id: string;
    index: number;
    start_ms: number;
    end_ms: number;
    text: string;
    display_text: string;
    tokens: SubtitleToken[];
  }>;
  word_timelines: WordTimeline[];
  active_word_timeline_id: string | null;
  phone_timelines: PhoneTimeline[];
  active_phone_timeline_id: string | null;
  chunk_timelines: unknown[];
  active_chunk_timeline_id: string | null;
  sense_group_analyses?: SenseGroupAnalysis[];
  active_sense_group_analysis_id?: string | null;
  artifacts: unknown[];
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

export type LexicalEntryKind = "word" | "phrase";
export type LexicalCapability = "reading" | "listening" | "speaking" | "writing";
export type CapabilityAssessment = "unassessed" | "not_acquired" | "acquired";

export interface LexicalSource {
  media_id?: string | null;
  sentence_id?: string | null;
  original_form: string;
  sentence_text: string;
  media_title: string;
  media_fingerprint: string;
  start_ms: number;
  end_ms: number;
  token_start?: number | null;
  token_end?: number | null;
}

export interface UpsertLexicalEntry {
  language: string;
  kind: LexicalEntryKind;
  canonical_form: string;
  display_form: string;
  status?: LearningStatus | null;
  user_definition?: string | null;
  personal_note?: string | null;
  source?: LexicalSource | null;
}

export interface LexicalUnit {
  language: string;
  granularity: string;
  normalization: string;
  normalized_key: string;
  display_form: string;
}

export interface LexicalEntry {
  id: string;
  unit: LexicalUnit;
  language: string;
  kind: LexicalEntryKind;
  canonical_form: string;
  normalized_form: string;
  display_form: string;
  status: LearningStatus | null;
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

export interface LexicalObservation {
  id: string;
  lexical_entry_id: string;
  sentence_id: string;
  original_form: string;
  result: "recognized_in_context" | "not_recognized_in_context";
  created_at_ms: number;
}

export type PracticeMode = "intensive" | "extensive" | "review" | "specialty";
export type PracticeKind = "cloze" | "dictation" | "subtitle_fade" | "shadowing";
export type PracticeTargetKind = "lexical" | "sentence" | "chunk" | "segment" | "connected_speech";
export type PracticeAnchorKind =
  | "lexical_entry"
  | "sentence"
  | "word_timeline"
  | "chunk_timeline"
  | "chunk"
  | "phone_timeline"
  | "phone"
  | "connected_speech";
export type PracticeResult = "correct" | "partial" | "incorrect" | "completed" | "skipped";
export type PracticeTokenResult = "correct" | "missing" | "extra" | "mismatch";
export type ReviewSourceKind =
  | "lexical_entry"
  | "practice_failure"
  | "listening_inbox"
  | "chunk"
  | "sentence"
  | "connected_speech";
export type ReviewItemStatus = "active" | "suspended" | "archived";
export type ReviewRating = "again" | "hard" | "good" | "easy";
export type ReviewCardKind =
  | "word_recognition"
  | "chunk_cloze"
  | "phrase_presence"
  | "source_sentence_recall";
export type LearningEventKind =
  | "listening_started"
  | "listening_completed"
  | "practice_completed"
  | "review_completed"
  | "status_changed"
  | "stuck_point_marked"
  | "stuck_point_skipped"
  | "diagnosis_viewed"
  | "stuck_point_closed"
  | "familiar_material_marked"
  | "listening_inbox_captured"
  | "listening_inbox_processed"
  | "hunting_check_answered";
export type LearningEventSubjectKind =
  | "media"
  | "sentence"
  | "chunk"
  | "lexical_entry"
  | "review_item"
  | "practice_attempt"
  | "practice_session"
  | "listening_inbox_item"
  | "hunting_target";

export type ListeningComprehensionReport =
  | "understood_all"
  | "got_the_gist"
  | "unclear";
export type ListeningInboxStatus = "active" | "archived";
export type ListeningInboxResolution =
  | "review_item"
  | "micro_intensive"
  | "favorite"
  | "dismissed"
  | "expired";

export interface PracticeSession {
  id: string;
  mode: PracticeMode;
  media_id: string | null;
  track_id: string | null;
  source: string;
  started_at_ms: number;
  ended_at_ms: number | null;
}

export interface CreatePracticeSession {
  mode: PracticeMode;
  media_id?: string | null;
  track_id?: string | null;
  source?: string | null;
}

export interface PracticeTarget {
  kind: PracticeTargetKind;
  id: string | null;
  sentence_id: string | null;
  chunk_id: string | null;
  start_ms: number | null;
  end_ms: number | null;
}

export interface PracticeAnchor {
  kind: PracticeAnchorKind;
  id: string;
  label: string | null;
  lexical_entry_id: string | null;
  sentence_id: string | null;
  token_start: number | null;
  token_end: number | null;
  start_ms: number | null;
  end_ms: number | null;
}

export interface PracticeItem {
  id: string;
  session_id: string | null;
  kind: PracticeKind;
  target: PracticeTarget;
  prompt_snapshot: string;
  expected_answer: unknown;
  anchors: PracticeAnchor[];
  created_at_ms: number;
}

export interface CreatePracticeItem {
  session_id?: string | null;
  kind: PracticeKind;
  target: PracticeTarget;
  prompt_snapshot: string;
  expected_text: string;
  anchors: PracticeAnchor[];
}

export interface PracticeTokenEvaluation {
  expected: string | null;
  actual: string | null;
  result: PracticeTokenResult;
}

export interface PracticeEvaluation {
  summary: string;
  token_results: PracticeTokenEvaluation[];
  extra: unknown;
}

export interface PracticeAttempt {
  id: string;
  item_id: string;
  submitted_at_ms: number;
  input: unknown;
  result: PracticeResult;
  score: number | null;
  evaluation: PracticeEvaluation;
  generated_observation_ids: string[];
  generated_review_item_ids: string[];
}

export interface SubmitPracticeAttempt {
  item_id: string;
  text_answer: string;
  create_review_item_on_failure: boolean;
}

export type PlayableSegmentAvailability =
  | "available"
  | "missing_media"
  | "missing_timeline";

export interface PlayableSegment {
  media_id: string | null;
  start_ms: number;
  end_ms: number;
  label: string;
  subtitle_snapshot: string;
  availability: PlayableSegmentAvailability;
}

export interface RecordingAudioMetadata {
  container: string;
  codec: string;
  sample_rate_hz: number;
  channels: number;
  sample_format: string;
  byte_length: number;
  content_sha256: string;
}

export interface RecordingAsset {
  id: string;
  file_path: string;
  created_at_ms: number;
  duration_ms: number;
  practice_attempt_id: string | null;
  target: PracticeTarget;
  source_segment: PlayableSegment;
  language: string;
  audio: RecordingAudioMetadata;
  recorder_version: string;
}

export interface CreateRecordingAsset {
  file_path: string;
  duration_ms: number;
  target: PracticeTarget;
  source_segment: PlayableSegment;
  language: string;
  audio: RecordingAudioMetadata;
  recorder_version: string;
}

export interface CompleteShadowingAttempt {
  item_id: string;
  recording_id: string;
}

export interface CreateShadowingComparison {
  recording_id: string;
  reference_wav_path: string;
}

export interface AudioPauseInterval {
  start_ms: number;
  end_ms: number;
}

export interface AudioWaveformSummary {
  duration_ms: number;
  bucket_ms: number;
  peaks: number[];
  rms: number[];
}

export interface ShadowingPauseAlignment {
  reference_pauses: AudioPauseInterval[];
  recording_pauses: AudioPauseInterval[];
  mean_absolute_offset_ms: number | null;
}

export interface ShadowingComparison {
  attempt_id: string;
  reference_segment: PlayableSegment;
  recording_id: string;
  duration_delta_ms: number;
  pause_alignment: ShadowingPauseAlignment;
  reference_waveform: AudioWaveformSummary;
  recording_waveform: AudioWaveformSummary;
}

export interface ReviewSource {
  kind: ReviewSourceKind;
  id: string | null;
  practice_attempt_id: string | null;
  lexical_entry_id: string | null;
  media_id: string | null;
  track_id: string | null;
}

export interface ReviewItem {
  id: string;
  source: ReviewSource;
  anchors: PracticeAnchor[];
  prompt_snapshot: string;
  status: ReviewItemStatus;
  created_at_ms: number;
  updated_at_ms: number;
}

export interface CreateReviewItem {
  source: ReviewSource;
  anchors: PracticeAnchor[];
  prompt_snapshot: string;
}

export interface ReviewSchedule {
  item_id: string;
  algorithm: string;
  due_at_ms: number;
  stability: number | null;
  difficulty: number | null;
  interval_days: number | null;
  lapse_count: number;
}

export interface ReviewAttempt {
  id: string;
  item_id: string;
  reviewed_at_ms: number;
  rating: ReviewRating;
  practice_attempt_id: string | null;
  next_due_at_ms: number | null;
}

export interface ReviewCard {
  kind: ReviewCardKind;
  cue: string | null;
  answer: string;
  target: string | null;
}

export interface ReviewQueueEntry {
  item: ReviewItem;
  schedule: ReviewSchedule;
  card: ReviewCard;
}

export interface SubmitReviewAttempt {
  item_id: string;
  rating: ReviewRating;
}

export interface ReviewSubmission {
  attempt: ReviewAttempt;
  schedule: ReviewSchedule;
  generated_observation_ids: string[];
  hunting_candidate_ids: string[];
  upgrade_suggestions: UpgradeSuggestion[];
}

export type HuntingCandidateStatus = "active" | "consumed" | "dismissed";
export type HuntingTargetSourceKind = "manual" | "review_candidate" | "listening_inbox";
export type HuntingTargetStatus = "active" | "archived";

export interface HuntingCandidate {
  id: string;
  lexical_entry_id: string;
  review_item_id: string;
  sentence_id: string | null;
  media_id: string | null;
  track_id: string | null;
  target_snapshot: string;
  prompt_snapshot: string;
  failure_count: number;
  status: HuntingCandidateStatus;
  created_at_ms: number;
  last_failed_at_ms: number;
}

export interface CreateHuntingTargetInput {
  lexical_entry_id: string;
  source_kind: HuntingTargetSourceKind;
  source_id?: string | null;
}

export interface HuntingTarget {
  id: string;
  lexical_entry_id: string;
  source_kind: HuntingTargetSourceKind;
  source_id: string | null;
  target_snapshot: string;
  status: HuntingTargetStatus;
  created_at_ms: number;
  updated_at_ms: number;
}

export interface CorpusOccurrence {
  id: string;
  language: string;
  kind: "lexical" | "phrase" | "chunk" | "sound_pattern" | "connected_speech";
  normalized_key: string | null;
  display_text: string;
  media_id: string | null;
  track_id: string | null;
  sentence_id: string | null;
  start_ms: number;
  end_ms: number;
  source_snapshot: string;
}

export interface HuntingOccurrence {
  target_id: string;
  lexical_entry_id: string;
  target_snapshot: string;
  occurrence: CorpusOccurrence;
}

export interface HuntingOccurrenceQueryResult {
  indexed: boolean;
  occurrences: HuntingOccurrence[];
}

export type HuntingCheckAnswer = "recognized" | "not_recognized" | "not_noticed";

export interface SubmitHuntingCheckInput {
  session_id: string;
  target_id: string;
  occurrence_id: string;
  answer: HuntingCheckAnswer;
}

export interface HuntingCheckResult {
  answer: HuntingCheckAnswer;
  event_id: string;
  observation_id: string | null;
}

export type UpgradeSuggestionStatus = "pending" | "accepted" | "rejected" | "obsolete";

export interface UpgradeSuggestion {
  id: string;
  lexical_entry_id: string;
  lexical_display_form: string;
  previous_status: LearningStatus;
  suggested_status: LearningStatus;
  status: UpgradeSuggestionStatus;
  evidence_context_count: number;
  evidence_ids: string[];
  threshold: number;
  evidence_class: string;
  created_at_ms: number;
  resolved_at_ms: number | null;
  cooldown_until_ms: number | null;
}

export interface CompleteListeningSessionInput {
  comprehension_report?: ListeningComprehensionReport | null;
  hunting_summary?: HuntingCompletionSummary | null;
}

export interface HuntingCompletionSummary {
  prompted_count: number;
  recognized_count: number;
  not_recognized_count: number;
  not_noticed_count: number;
}

export interface CaptureListeningInboxItemInput {
  session_id: string;
  target: PracticeTarget;
  anchors: PracticeAnchor[];
  label?: string | null;
  subtitle_snapshot: string;
  context_before?: string | null;
  context_after?: string | null;
  expires_in_days?: number | null;
}

export interface ProcessListeningInboxItemInput {
  resolution: ListeningInboxResolution;
}

export interface ListeningInboxItem {
  id: string;
  session_id: string | null;
  media_id: string | null;
  track_id: string | null;
  target: PracticeTarget;
  anchors: PracticeAnchor[];
  label: string | null;
  subtitle_snapshot: string;
  context_before: string | null;
  context_after: string | null;
  captured_at_ms: number;
  expires_at_ms: number | null;
  status: ListeningInboxStatus;
  resolution: ListeningInboxResolution | null;
  review_item_ids: string[];
  practice_item_id: string | null;
  updated_at_ms: number;
}

export interface LearningEventSubject {
  kind: LearningEventSubjectKind;
  id: string;
}

export interface LearningEvent {
  id: string;
  occurred_at_ms: number;
  kind: LearningEventKind;
  subject: LearningEventSubject;
  payload: unknown;
  session_id: string | null;
}

export interface VocabularyAssetBundle {
  version: 5 | 6 | 7;
  exported_at_ms: number;
  lexical_entries: LexicalEntry[];
  lexical_history: unknown[];
  lexical_occurrences: unknown[];
  lexical_sense_folders?: LexicalSenseFolder[];
  lexical_sense_folder_occurrences?: LexicalSenseFolderOccurrence[];
  lexical_observations: LexicalObservation[];
  phonetic_finding_feedback: unknown[];
}

export interface LexicalSenseFolder {
  id: string;
  lexical_entry_id: string;
  label: string;
  definition: string | null;
  gloss: string | null;
  external_ref: string | null;
  created_at_ms: number;
  updated_at_ms: number;
}

export interface LexicalSenseFolderOccurrence {
  lexical_sense_id: string;
  lexical_occurrence_id: string;
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

  importLLTimeline(document: LLTimelineDocument): Promise<SubtitleTrack> {
    return this.request("/v1/lltimeline/import", {
      method: "POST",
      body: JSON.stringify(document),
    });
  }

  importLLTimelineForMedia(
    mediaId: string,
    document: LLTimelineDocument,
    allowMismatch = false,
  ): Promise<SubtitleTrack> {
    return this.request(
      `/v1/media/${encodeURIComponent(mediaId)}/lltimeline/import?allow_mismatch=${allowMismatch}`,
      {
        method: "POST",
        body: JSON.stringify(document),
      },
    );
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

  mediaSubtitles(mediaId: string): Promise<SubtitleTrack[]> {
    return this.request(`/v1/media/${encodeURIComponent(mediaId)}/subtitles`);
  }

  readSubtitle(trackId: string): Promise<SubtitleTrack> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}`);
  }

  archiveSubtitle(trackId: string): Promise<SubtitleTrack> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/archive`, {
      method: "POST",
    });
  }

  restoreSubtitle(trackId: string): Promise<SubtitleTrack> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/restore`, {
      method: "POST",
    });
  }

  updateTrackLanguage(trackId: string, language: string): Promise<SubtitleTrack> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/language`, {
      method: "PATCH",
      body: JSON.stringify({ language }),
    });
  }

  deleteSubtitle(trackId: string): Promise<SubtitleTrack> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}`, {
      method: "DELETE",
    });
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

  trackWordTimelines(trackId: string): Promise<WordTimeline[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/word-timelines`);
  }

  trackWordTimelineSummaries(trackId: string): Promise<WordTimelineSummary[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/word-timelines/summary`);
  }

  createTrackWordTimeline(
    trackId: string,
    input: CreateWordTimeline,
  ): Promise<WordTimeline> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/word-timelines`, {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  exportTrackLLTimeline(trackId: string): Promise<LLTimelineDocument> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/lltimeline/export`);
  }

  wordTimeline(timelineId: string): Promise<WordTimeline> {
    return this.request(`/v1/word-timelines/${encodeURIComponent(timelineId)}`);
  }

  activateWordTimeline(timelineId: string): Promise<WordTimeline> {
    return this.request(`/v1/word-timelines/${encodeURIComponent(timelineId)}/activate`, {
      method: "POST",
    });
  }

  publishWordTimeline(timelineId: string): Promise<WordTimeline> {
    return this.request(`/v1/word-timelines/${encodeURIComponent(timelineId)}/publish`, {
      method: "POST",
    });
  }

  archiveWordTimeline(timelineId: string): Promise<WordTimeline> {
    return this.request(`/v1/word-timelines/${encodeURIComponent(timelineId)}/archive`, {
      method: "POST",
    });
  }

  exportWordTimeline(timelineId: string): Promise<WordTimeline> {
    return this.request(`/v1/word-timelines/${encodeURIComponent(timelineId)}/export`);
  }

  deleteWordTimeline(timelineId: string): Promise<WordTimeline> {
    return this.request(`/v1/word-timelines/${encodeURIComponent(timelineId)}`, {
      method: "DELETE",
    });
  }

  trackPhoneTimelines(trackId: string): Promise<PhoneTimeline[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/phone-timelines`);
  }

  trackPhoneTimelineSummaries(trackId: string): Promise<PhoneTimelineSummary[]> {
    return this.request(`/v1/subtitles/${encodeURIComponent(trackId)}/phone-timelines/summary`);
  }

  phoneTimeline(timelineId: string): Promise<PhoneTimeline> {
    return this.request(`/v1/phone-timelines/${encodeURIComponent(timelineId)}`);
  }

  activatePhoneTimeline(timelineId: string): Promise<PhoneTimeline> {
    return this.request(`/v1/phone-timelines/${encodeURIComponent(timelineId)}/activate`, {
      method: "POST",
    });
  }

  archivePhoneTimeline(timelineId: string): Promise<PhoneTimeline> {
    return this.request(`/v1/phone-timelines/${encodeURIComponent(timelineId)}/archive`, {
      method: "POST",
    });
  }

  exportPhoneTimeline(timelineId: string): Promise<PhoneTimeline> {
    return this.request(`/v1/phone-timelines/${encodeURIComponent(timelineId)}/export`);
  }

  deletePhoneTimeline(timelineId: string): Promise<PhoneTimeline> {
    return this.request(`/v1/phone-timelines/${encodeURIComponent(timelineId)}`, {
      method: "DELETE",
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

  readLexicalEntries(
    language: string,
    kind: LexicalEntryKind,
    forms: string[],
  ): Promise<LexicalEntry[]> {
    return this.request("/v1/lexical-entries/batch", {
      method: "POST",
      body: JSON.stringify({ language, kind, forms }),
    });
  }

  listLexicalEntries(input: {
    language?: string;
    kind?: LexicalEntryKind;
    status?: LearningStatus;
    search?: string;
    limit?: number;
    offset?: number;
  } = {}): Promise<LexicalEntryDetails[]> {
    const query = new URLSearchParams({
      language: input.language ?? "en",
      limit: String(input.limit ?? 200),
      offset: String(input.offset ?? 0),
    });
    if (input.kind) query.set("kind", input.kind);
    if (input.status) query.set("status", input.status);
    if (input.search) query.set("search", input.search);
    return this.request(`/v1/lexical-entries?${query}`);
  }

  upsertLexicalEntry(input: UpsertLexicalEntry): Promise<LexicalEntryDetails> {
    return this.request("/v1/lexical-entries", { method: "PUT", body: JSON.stringify(input) });
  }

  lexicalEntryDetails(id: string): Promise<LexicalEntryDetails> {
    return this.request(`/v1/lexical-entries/${encodeURIComponent(id)}`);
  }

  updateLexicalLearningContent(
    id: string,
    userDefinition: string | null,
    personalNote: string | null,
  ): Promise<LexicalEntryDetails> {
    return this.request(`/v1/lexical-entries/${encodeURIComponent(id)}/learning-content`, {
      method: "PUT",
      body: JSON.stringify({ user_definition: userDefinition, personal_note: personalNote }),
    });
  }

  createLexicalObservation(input: {
    lexical_entry_id: string;
    sentence_id: string;
    original_form: string;
    result?: "recognized_in_context" | "not_recognized_in_context" | null;
    clear?: boolean;
    source?: LexicalSource | null;
  }): Promise<LexicalObservation | undefined> {
    return this.request("/v1/lexical-observations", {
      method: "POST",
      body: JSON.stringify(input),
    });
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

  createPracticeSession(input: CreatePracticeSession): Promise<PracticeSession> {
    return this.request("/v1/practice/sessions", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  completeListeningSession(
    id: string,
    input: CompleteListeningSessionInput,
  ): Promise<PracticeSession> {
    return this.request(`/v1/listening/sessions/${encodeURIComponent(id)}/complete`, {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  createPracticeItem(input: CreatePracticeItem): Promise<PracticeItem> {
    return this.request("/v1/practice/items", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  submitPracticeAttempt(input: SubmitPracticeAttempt): Promise<PracticeAttempt> {
    return this.request("/v1/practice/attempts", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  completeShadowingAttempt(input: CompleteShadowingAttempt): Promise<PracticeAttempt> {
    return this.request("/v1/practice/shadowing-attempts", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  createRecordingAsset(input: CreateRecordingAsset): Promise<RecordingAsset> {
    return this.request("/v1/recordings", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  recordingAsset(id: string): Promise<RecordingAsset> {
    return this.request(`/v1/recordings/${encodeURIComponent(id)}`);
  }

  deleteRecordingAsset(id: string): Promise<RecordingAsset> {
    return this.request(`/v1/recordings/${encodeURIComponent(id)}`, {
      method: "DELETE",
    });
  }

  compareShadowing(input: CreateShadowingComparison): Promise<ShadowingComparison> {
    return this.request("/v1/shadowing/comparisons", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  practiceAttempt(id: string): Promise<PracticeAttempt> {
    return this.request(`/v1/practice/attempts/${encodeURIComponent(id)}`);
  }

  listeningInboxItems(
    status: ListeningInboxStatus = "active",
    limit = 100,
    offset = 0,
  ): Promise<ListeningInboxItem[]> {
    const params = new URLSearchParams({
      status,
      limit: String(limit),
      offset: String(offset),
    });
    return this.request(`/v1/listening-inbox/items?${params.toString()}`);
  }

  captureListeningInboxItem(
    input: CaptureListeningInboxItemInput,
  ): Promise<ListeningInboxItem> {
    return this.request("/v1/listening-inbox/items", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  processListeningInboxItem(
    id: string,
    input: ProcessListeningInboxItemInput,
  ): Promise<ListeningInboxItem> {
    return this.request(`/v1/listening-inbox/items/${encodeURIComponent(id)}/process`, {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  listHuntingCandidates(
    status: HuntingCandidateStatus = "active",
    limit = 100,
    offset = 0,
  ): Promise<HuntingCandidate[]> {
    const params = new URLSearchParams({
      status,
      limit: String(limit),
      offset: String(offset),
    });
    return this.request(`/v1/hunting/candidates?${params.toString()}`);
  }

  listHuntingTargets(
    status: HuntingTargetStatus = "active",
    limit = 100,
    offset = 0,
  ): Promise<HuntingTarget[]> {
    const params = new URLSearchParams({
      status,
      limit: String(limit),
      offset: String(offset),
    });
    return this.request(`/v1/hunting/targets?${params.toString()}`);
  }

  createHuntingTarget(input: CreateHuntingTargetInput): Promise<HuntingTarget> {
    return this.request("/v1/hunting/targets", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  archiveHuntingTarget(id: string): Promise<HuntingTarget> {
    return this.request(`/v1/hunting/targets/${encodeURIComponent(id)}`, {
      method: "DELETE",
    });
  }

  listHuntingOccurrences(
    mediaId: string,
    trackId?: string,
  ): Promise<HuntingOccurrenceQueryResult> {
    const params = new URLSearchParams({ media_id: mediaId });
    if (trackId !== undefined) params.set("track_id", trackId);
    return this.request(`/v1/hunting/occurrences?${params.toString()}`);
  }

  submitHuntingCheck(input: SubmitHuntingCheckInput): Promise<HuntingCheckResult> {
    return this.request("/v1/hunting/checks", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  createReviewItem(input: CreateReviewItem): Promise<ReviewItem> {
    return this.request("/v1/review/items", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  listDueReviewItems(limit = 20, atMs?: number): Promise<ReviewQueueEntry[]> {
    const params = new URLSearchParams({ limit: String(limit) });
    if (atMs !== undefined) params.set("at_ms", String(atMs));
    return this.request(`/v1/review/items?${params.toString()}`);
  }

  submitReviewAttempt(input: SubmitReviewAttempt): Promise<ReviewSubmission> {
    return this.request("/v1/review/attempts", {
      method: "POST",
      body: JSON.stringify(input),
    });
  }

  listUpgradeSuggestions(
    status: UpgradeSuggestionStatus = "pending",
    lexicalEntryId?: string,
    limit = 100,
    offset = 0,
  ): Promise<UpgradeSuggestion[]> {
    const params = new URLSearchParams({ status, limit: String(limit), offset: String(offset) });
    if (lexicalEntryId !== undefined) params.set("lexical_entry_id", lexicalEntryId);
    return this.request(`/v1/review/upgrade-suggestions?${params.toString()}`);
  }

  upgradeSuggestionHistory(
    lexicalEntryId?: string,
    limit = 100,
    offset = 0,
  ): Promise<UpgradeSuggestion[]> {
    const params = new URLSearchParams({ limit: String(limit), offset: String(offset) });
    if (lexicalEntryId !== undefined) params.set("lexical_entry_id", lexicalEntryId);
    return this.request(`/v1/review/upgrade-suggestions/history?${params.toString()}`);
  }

  confirmUpgradeSuggestion(id: string): Promise<UpgradeSuggestion> {
    return this.request(`/v1/review/upgrade-suggestions/${encodeURIComponent(id)}/confirm`, {
      method: "POST",
    });
  }

  rejectUpgradeSuggestion(id: string): Promise<UpgradeSuggestion> {
    return this.request(`/v1/review/upgrade-suggestions/${encodeURIComponent(id)}/reject`, {
      method: "POST",
    });
  }

  reviewItem(id: string): Promise<ReviewItem> {
    return this.request(`/v1/review/items/${encodeURIComponent(id)}`);
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

  clearTerminalPhoneticAnalysisJobs(): Promise<{ deleted: number }> {
    return this.request("/v1/phonetic-analysis/jobs/clear", {
      method: "POST",
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

  listVocabulary(
    options: {
      language?: string;
      kind?: LexicalEntryKind;
      status?: LearningStatus;
      capability?: LexicalCapability;
      assessment?: CapabilityAssessment;
      search?: string;
    } = {},
  ): Promise<unknown[]> {
    const query = new URLSearchParams({ language: options.language ?? "en" });
    if (options.kind) query.set("kind", options.kind);
    if (options.status) query.set("status", options.status);
    if (options.capability) query.set("capability", options.capability);
    if (options.assessment) query.set("assessment", options.assessment);
    if (options.search) query.set("search", options.search);
    return this.request(`/v1/vocabulary?${query}`);
  }

  exportVocabulary(): Promise<VocabularyAssetBundle> {
    return this.request("/v1/vocabulary/export");
  }

  importVocabulary(bundle: VocabularyAssetBundle): Promise<unknown> {
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

  listLanguages(): Promise<string[]> {
    return this.request("/v1/languages");
  }

  languageProfile(code: string): Promise<LanguageLearningProfile> {
    return this.request(`/v1/languages/${encodeURIComponent(code)}/profile`);
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
    if (response.status === 204) return undefined as T;
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
