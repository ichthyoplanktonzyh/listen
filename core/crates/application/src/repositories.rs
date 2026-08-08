use domain::{
    CapabilityFilter, CapabilityOverride, CapabilityProjection, ChunkTimeline, ChunkTimelineId,
    ContentDifficultyProfile, CorpusOccurrence, CorpusOccurrenceId, DictionaryEntry,
    HuntingCandidate, HuntingCandidateId, HuntingCandidateStatus, HuntingTarget, HuntingTargetId,
    HuntingTargetStatus, JudgmentAdjudication, LLTimelineArtifact, LLTimelineMetadata,
    LanguageCode, LearnerProfile, LearnerProfileId, LearningChangeSource, LearningEvent,
    LearningEventKind, LearningEventSubjectKind, LearningObservation, LearningStatus,
    LexicalCapability, LexicalCapabilityHistory, LexicalCapabilityProfile, LexicalEntry,
    LexicalEntryDetails, LexicalEntryId, LexicalEntryKind, LexicalObservation, LexicalOccurrenceId,
    LexicalSenseFolder, LexicalSenseId, ListeningInboxItem, ListeningInboxItemId,
    ListeningInboxStatus, LlmProviderProfile, LlmProviderProfileId, MediaAvailability, MediaId,
    MediaItem, MediaTriageIntent, PhoneTimeline, PhoneTimelineId, PhoneticAnalysis,
    PhoneticAnalysisId, PhoneticAnalysisJob, PhoneticAnalysisJobId,
    PhoneticAnalysisModelDescriptor, PhoneticAnalysisModelId, PhoneticFindingFeedback,
    PhoneticFindingId, PracticeAttempt, PracticeAttemptId, PracticeItem, PracticeItemId,
    PracticeSession, PracticeSessionId, ProductionCorpusDocument, ProductionCorpusEntry,
    ProductionCorpusHit, ProductionCorpusSummary, ProductionGapCandidateFacts, ProjectionDecision,
    ProjectionProposal, ProjectionProposalId, ReadingPosition, RealtimeConversationSession,
    RealtimeConversationSessionId, RealtimeConversationTurn, RealtimeConversationTurnId,
    RealtimeProviderProfile, RealtimeProviderProfileId, RecognitionEvidence, RecordingAsset,
    RecordingAssetId, ReviewAttempt, ReviewAttemptId, ReviewItem, ReviewItemId, ReviewItemStatus,
    ReviewSchedule, SecretRef, SemanticJudgment, SemanticJudgmentId, SemanticRubric,
    SemanticRubricId, SemanticTaskAttempt, SemanticTaskAttemptId, SemanticTaskKind,
    SenseGroupAnalysis, SenseGroupAnalysisId, SentencePronunciation, ShadowingAnalysisRecord,
    SoundFitCalibration, SubtitleSentence, SubtitleSentenceId, SubtitleTrack, SubtitleTrackId,
    SubtitleTrackStatus, TimeMs, TranscriptionModelDescriptor, TranscriptionModelId,
    UpgradeSuggestion, UpgradeSuggestionId, UpgradeSuggestionStatus, VocabularyAssetBundle,
    WordPronunciation, WordTimeline, WordTimelineId, WordTiming, WritingDraft,
    WritingFeedbackFinding, WritingFeedbackFindingId, WritingFindingDisposition,
    WritingFindingDispositionId,
};

use crate::{ApplicationError, LexicalSourceContext};

pub trait MediaRepository: Send + Sync {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError>;
    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError>;
    fn list(&self) -> Result<Vec<MediaItem>, ApplicationError>;
    fn set_availability(
        &self,
        id: &MediaId,
        availability: MediaAvailability,
    ) -> Result<MediaItem, ApplicationError>;
    /// Stores the user's explicit triage judgment for one media; `None`
    /// clears it. Intent rows are durable user data, not derived state.
    fn set_triage_intent(
        &self,
        media_id: &MediaId,
        intent: Option<MediaTriageIntent>,
        updated_at_ms: u64,
    ) -> Result<(), ApplicationError>;
    fn get_triage_intent(
        &self,
        media_id: &MediaId,
    ) -> Result<Option<MediaTriageIntent>, ApplicationError>;
    fn list_triage_intents(&self) -> Result<Vec<(MediaId, MediaTriageIntent)>, ApplicationError>;
}

pub trait SubtitleTrackRepository: Send + Sync {
    fn save_track(&self, track: &SubtitleTrack) -> Result<(), ApplicationError>;
    /// Atomically persists the authoritative subtitle track and replaces its
    /// complete rebuildable corpus projection.
    ///
    /// Import and language retokenization must use this unit-of-work boundary:
    /// callers must never observe new subtitle sentences with an old or
    /// missing corpus projection.
    fn save_track_and_replace_corpus(
        &self,
        track: &SubtitleTrack,
        occurrences: &[CorpusOccurrence],
    ) -> Result<(), ApplicationError>;
    fn get_track(&self, id: &SubtitleTrackId) -> Result<Option<SubtitleTrack>, ApplicationError>;
    fn list_tracks_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Vec<SubtitleTrack>, ApplicationError>;
    fn set_track_status(
        &self,
        id: &SubtitleTrackId,
        status: SubtitleTrackStatus,
    ) -> Result<SubtitleTrack, ApplicationError>;
    fn delete_track(&self, id: &SubtitleTrackId)
    -> Result<Option<SubtitleTrack>, ApplicationError>;
    fn get_by_media_fingerprint(
        &self,
        media_id: &MediaId,
        fingerprint: &str,
    ) -> Result<Option<SubtitleTrack>, ApplicationError>;
    fn get_sentence(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleSentence>, ApplicationError>;
    fn sentence_track_language(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<LanguageCode>, ApplicationError>;
    /// Track a sentence belongs to; `None` when the sentence is unknown.
    /// Used to reach track-scoped resources (rhythm frames) from a
    /// sentence-scoped call such as diagnosis.
    fn sentence_track_id(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleTrackId>, ApplicationError>;
}

pub trait PronunciationRepository: Send + Sync {
    fn save_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        pronunciation: &WordPronunciation,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<(), ApplicationError>;
    fn get_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        normalized_text: &str,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<Option<WordPronunciation>, ApplicationError>;
    fn save_pronunciation(&self, analysis: &SentencePronunciation) -> Result<(), ApplicationError>;
    fn get_pronunciation(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SentencePronunciation>, ApplicationError>;
}

/// Word timing and word-timeline persistence change together because active
/// selection and raw timing compatibility share one invariant.
pub trait WordTimelineRepository: Send + Sync {
    fn save_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
        timings: &[WordTiming],
    ) -> Result<(), ApplicationError>;
    fn get_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordTiming>, ApplicationError>;
    fn save_word_timeline(&self, timeline: &WordTimeline)
    -> Result<WordTimeline, ApplicationError>;
    fn list_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimeline>, ApplicationError>;
    fn get_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<Option<WordTimeline>, ApplicationError>;
    fn active_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<WordTimeline>, ApplicationError>;
    fn activate_word_timeline(&self, id: &WordTimelineId)
    -> Result<WordTimeline, ApplicationError>;
    /// Returns the track's existing active timeline, or atomically activates
    /// `id` when the track has no active timeline.
    fn activate_word_timeline_if_absent(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError>;
    fn archive_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError>;
    fn delete_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError>;
}

/// Chunk partitions have an independent lifecycle.
pub trait ChunkTimelineRepository: Send + Sync {
    fn save_chunk_timeline(
        &self,
        timeline: &ChunkTimeline,
    ) -> Result<ChunkTimeline, ApplicationError>;
    fn list_chunk_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ChunkTimeline>, ApplicationError>;
    fn get_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError>;
    fn active_chunk_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError>;
    fn activate_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError>;
    /// Returns the track's existing active timeline, or atomically activates
    /// `id` when the track has no active timeline.
    fn activate_chunk_timeline_if_absent(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError>;
    fn archive_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError>;
    fn delete_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError>;
}

/// Sense-group analyses are versioned and activated as one resource family.
pub trait SenseGroupRepository: Send + Sync {
    fn get_llm_sentence_checkpoint(
        &self,
        fingerprint: &str,
    ) -> Result<Option<crate::batch_governor::CachedPartition>, ApplicationError>;
    fn save_llm_sentence_checkpoint(
        &self,
        fingerprint: &str,
        partition: &crate::batch_governor::CachedPartition,
        updated_at_ms: u64,
    ) -> Result<(), ApplicationError>;
    fn save_sense_group_analysis(
        &self,
        analysis: &SenseGroupAnalysis,
    ) -> Result<SenseGroupAnalysis, ApplicationError>;
    fn list_sense_group_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<SenseGroupAnalysis>, ApplicationError>;
    fn get_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<Option<SenseGroupAnalysis>, ApplicationError>;
    fn active_sense_group_analysis(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<SenseGroupAnalysis>, ApplicationError>;
    fn activate_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError>;
    /// Returns the track's existing active analysis, or atomically activates
    /// `id` when the track has no active analysis.
    fn activate_sense_group_analysis_if_absent(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError>;
    fn archive_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError>;
    fn delete_sense_group_analysis(
        &self,
        id: &SenseGroupAnalysisId,
    ) -> Result<SenseGroupAnalysis, ApplicationError>;
}

/// Phone timelines have their own activation and archival lifecycle.
pub trait PhoneTimelineRepository: Send + Sync {
    fn save_phone_timeline(
        &self,
        timeline: &PhoneTimeline,
    ) -> Result<PhoneTimeline, ApplicationError>;
    fn list_phone_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneTimeline>, ApplicationError>;
    fn get_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError>;
    fn active_phone_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError>;
    fn activate_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError>;
    fn archive_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError>;
    fn delete_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError>;
}

pub trait LLTimelineResourceRepository: Send + Sync {
    fn save_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
        metadata: &LLTimelineMetadata,
        artifacts: &[LLTimelineArtifact],
    ) -> Result<(), ApplicationError>;
    fn get_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<(LLTimelineMetadata, Vec<LLTimelineArtifact>)>, ApplicationError>;
}

/// A fully validated LLTimeline import snapshot.
///
/// This is an import-specific unit of work, not a new domain aggregate:
/// resource families keep their independent repositories and lifecycles after
/// import. The persistence adapter must commit every field below, including
/// the rebuildable corpus projection, in one transaction.
#[derive(Debug, Clone)]
pub struct LLTimelineImport {
    /// Present only when detached import creates a synthetic, unavailable
    /// media identity. Attached and already-known media are read-only here.
    pub media_to_create: Option<MediaItem>,
    pub track: SubtitleTrack,
    pub metadata: LLTimelineMetadata,
    pub artifacts: Vec<LLTimelineArtifact>,
    pub word_timelines: Vec<WordTimeline>,
    pub phone_timelines: Vec<PhoneTimeline>,
    pub chunk_timelines: Vec<ChunkTimeline>,
    pub sense_group_analyses: Vec<SenseGroupAnalysis>,
    pub corpus_occurrences: Vec<CorpusOccurrence>,
}

/// Atomic persistence boundary for one LLTimeline interchange import.
pub trait LLTimelineImportRepository: Send + Sync {
    /// Commits the source identity (when new), subtitle track, independent
    /// analysis resources, active selections, and corpus projection together.
    ///
    /// Returning `Err` guarantees that none of this import's durable writes
    /// were committed. Consequently there is no post-commit reindex phase
    /// whose failure could make an otherwise successful import ambiguous.
    fn import_lltimeline(&self, import: &LLTimelineImport) -> Result<(), ApplicationError>;
}

/// A validated Resource Package projected into Core-owned records.
///
/// This input is deliberately distinct from [`LLTimelineImport`]: package
/// resources are immutable candidates and cannot carry Core active-selection
/// policy across the exchange boundary.
#[derive(Debug, Clone)]
pub struct ContentPackageCandidateImport {
    pub track: SubtitleTrack,
    pub metadata: LLTimelineMetadata,
    pub artifacts: Vec<LLTimelineArtifact>,
    pub word_timelines: Vec<WordTimeline>,
    pub phone_timelines: Vec<PhoneTimeline>,
    pub chunk_timelines: Vec<ChunkTimeline>,
    pub sense_group_analyses: Vec<SenseGroupAnalysis>,
    pub corpus_occurrences: Vec<CorpusOccurrence>,
}

/// Atomic, candidate-only persistence boundary for a Resource Package.
pub trait ContentPackageImportRepository: Send + Sync {
    /// Adds resources idempotently without changing any existing active
    /// selection. Returning `Err` guarantees that no package write committed.
    fn import_content_package_candidates(
        &self,
        import: &ContentPackageCandidateImport,
    ) -> Result<(), ApplicationError>;
}

/// Capability projections and their audit history change under one invariant.
pub trait LexicalCapabilityRepository: Send + Sync {
    fn lexical_capability_profile(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
    ) -> Result<Option<LexicalCapabilityProfile>, ApplicationError>;
    fn set_lexical_capability_projection(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
        capability: LexicalCapability,
        projection: Option<CapabilityProjection>,
        changed_at_ms: u64,
    ) -> Result<LexicalCapabilityProfile, ApplicationError>;
    fn set_lexical_capability_override(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
        capability: LexicalCapability,
        user_override: Option<CapabilityOverride>,
        changed_at_ms: u64,
    ) -> Result<LexicalCapabilityProfile, ApplicationError>;
    fn lexical_capability_history(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: Option<&LexicalSenseId>,
    ) -> Result<Vec<LexicalCapabilityHistory>, ApplicationError>;
    fn save_projection_proposal(
        &self,
        proposal: &ProjectionProposal,
    ) -> Result<ProjectionProposal, ApplicationError>;
    fn projection_proposal(
        &self,
        id: &ProjectionProposalId,
    ) -> Result<Option<ProjectionProposal>, ApplicationError>;
    fn list_projection_proposals(
        &self,
        lexical_entry_id: &LexicalEntryId,
        capability: Option<LexicalCapability>,
    ) -> Result<Vec<ProjectionProposal>, ApplicationError>;
    fn resolve_projection_proposal(
        &self,
        decision: &ProjectionDecision,
        proposal: &ProjectionProposal,
        confirmed_projection: Option<CapabilityProjection>,
    ) -> Result<(), ApplicationError>;
}

/// Lexical identity, lookup, normalization overrides, and vocabulary
/// watermarks are one catalog capability.
pub trait LexicalEntryRepository: Send + Sync {
    fn upsert_lexical_entry(
        &self,
        entry: &LexicalEntry,
        source: Option<&LexicalSourceContext>,
        change_source: LearningChangeSource,
    ) -> Result<LexicalEntryDetails, ApplicationError>;
    fn lexical_details(
        &self,
        id: &LexicalEntryId,
    ) -> Result<Option<LexicalEntryDetails>, ApplicationError>;
    // Query axes remain explicit because capability filtering is optional only
    // as a pair; an unvalidated bag would permit invalid combinations.
    #[allow(clippy::too_many_arguments)]
    fn list_lexical_entries(
        &self,
        language: &LanguageCode,
        kind: Option<LexicalEntryKind>,
        status: Option<LearningStatus>,
        capability_filter: Option<CapabilityFilter>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError>;
    fn lexical_entries_by_keys(
        &self,
        language: &LanguageCode,
        kind: LexicalEntryKind,
        normalized_forms: &[String],
    ) -> Result<Vec<LexicalEntry>, ApplicationError>;
    /// Cheap vocabulary-snapshot watermark for one language:
    /// `(entry_count, max_learning_updated_at_ms)`. Any marking or import
    /// moves at least one component, so cache fingerprints built from it
    /// (ADR 0018 decision 5) invalidate on every vocabulary change.
    fn lexical_vocabulary_watermark(
        &self,
        language: &LanguageCode,
    ) -> Result<(u64, u64), ApplicationError>;
    fn set_lemma_override(
        &self,
        language: &LanguageCode,
        original_normalized: &str,
        corrected_normalized: &str,
        updated_at_ms: u64,
    ) -> Result<(), ApplicationError>;
    fn lemma_override(
        &self,
        language: &LanguageCode,
        original_normalized: &str,
    ) -> Result<Option<String>, ApplicationError>;
    fn lexical_entry_by_key(
        &self,
        language: &LanguageCode,
        kind: LexicalEntryKind,
        normalized_form: &str,
    ) -> Result<Option<LexicalEntry>, ApplicationError>;
}

/// Occurrence and channelized learning observations are append/read/clear
/// evidence operations.
pub trait LearningObservationRepository: Send + Sync {
    fn create_lexical_observation(
        &self,
        observation: &LexicalObservation,
    ) -> Result<LexicalObservation, ApplicationError>;
    fn list_lexical_observations_by_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<LexicalObservation>, ApplicationError>;
    /// Append-only channelized evidence (ADR 0017). Idempotent on id; never
    /// replaces an existing row.
    fn append_learning_observation(
        &self,
        observation: &LearningObservation,
    ) -> Result<LearningObservation, ApplicationError>;
    fn list_learning_observations(
        &self,
        lexical_entry_id: &LexicalEntryId,
        capability: Option<LexicalCapability>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LearningObservation>, ApplicationError>;
    fn clear_lexical_observation(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError>;
}

/// User-authored lexical content and sense-folder assignment share editing
/// consistency rules.
pub trait LexicalContentRepository: Send + Sync {
    fn update_lexical_learning_content(
        &self,
        id: &LexicalEntryId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<LexicalEntryDetails, ApplicationError>;
    fn create_lexical_sense_folder(
        &self,
        folder: &LexicalSenseFolder,
    ) -> Result<LexicalSenseFolder, ApplicationError>;
    fn update_lexical_sense_folder(
        &self,
        folder: &LexicalSenseFolder,
    ) -> Result<LexicalSenseFolder, ApplicationError>;
    fn delete_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
    ) -> Result<(), ApplicationError>;
    fn assign_occurrence_to_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
        occurrence_id: &LexicalOccurrenceId,
    ) -> Result<(), ApplicationError>;
    fn unassign_occurrence_from_lexical_sense_folder(
        &self,
        lexical_entry_id: &LexicalEntryId,
        sense_id: &LexicalSenseId,
        occurrence_id: &LexicalOccurrenceId,
    ) -> Result<(), ApplicationError>;
}

/// Import/export owns whole-vocabulary snapshot compatibility.
pub trait VocabularyAssetRepository: Send + Sync {
    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError>;
    fn import_assets(&self, bundle: &VocabularyAssetBundle) -> Result<(), ApplicationError>;
    fn export_all_capability_profiles(
        &self,
    ) -> Result<Vec<LexicalCapabilityProfile>, ApplicationError>;
}

pub trait PracticeRepository: Send + Sync {
    fn create_practice_session(
        &self,
        session: &PracticeSession,
    ) -> Result<PracticeSession, ApplicationError>;
    fn get_practice_session(
        &self,
        id: &PracticeSessionId,
    ) -> Result<Option<PracticeSession>, ApplicationError>;
    fn create_practice_item(&self, item: &PracticeItem) -> Result<PracticeItem, ApplicationError>;
    fn get_practice_item(
        &self,
        id: &PracticeItemId,
    ) -> Result<Option<PracticeItem>, ApplicationError>;
    fn list_practice_items_for_session(
        &self,
        session_id: &PracticeSessionId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PracticeItem>, ApplicationError>;
    fn create_practice_attempt(
        &self,
        attempt: &PracticeAttempt,
    ) -> Result<PracticeAttempt, ApplicationError>;
    fn get_practice_attempt(
        &self,
        id: &PracticeAttemptId,
    ) -> Result<Option<PracticeAttempt>, ApplicationError>;
    fn list_practice_attempts_for_item(
        &self,
        item_id: &PracticeItemId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<PracticeAttempt>, ApplicationError>;
}

/// Review cards, attempts, and schedules form one transaction-oriented queue.
pub trait ReviewQueueRepository: Send + Sync {
    fn create_review_item(&self, item: &ReviewItem) -> Result<ReviewItem, ApplicationError>;
    fn get_review_item(&self, id: &ReviewItemId) -> Result<Option<ReviewItem>, ApplicationError>;
    fn list_review_items(
        &self,
        status: Option<ReviewItemStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ReviewItem>, ApplicationError>;
    fn create_review_attempt(
        &self,
        attempt: &ReviewAttempt,
    ) -> Result<ReviewAttempt, ApplicationError>;
    fn get_review_attempt(
        &self,
        id: &ReviewAttemptId,
    ) -> Result<Option<ReviewAttempt>, ApplicationError>;
    fn save_review_schedule(
        &self,
        schedule: &ReviewSchedule,
    ) -> Result<ReviewSchedule, ApplicationError>;
    fn get_review_schedule(
        &self,
        item_id: &ReviewItemId,
    ) -> Result<Option<ReviewSchedule>, ApplicationError>;
    fn list_due_review_items(
        &self,
        due_at_or_before_ms: u64,
        limit: u32,
    ) -> Result<Vec<(ReviewItem, ReviewSchedule)>, ApplicationError>;
    fn list_review_items_with_schedules(
        &self,
        limit: u32,
    ) -> Result<Vec<(ReviewItem, ReviewSchedule)>, ApplicationError>;
    fn review_attempt_counts_between(
        &self,
        start_ms: u64,
        end_ms: u64,
    ) -> Result<(u32, u32), ApplicationError>;
    fn get_review_daily_limits(&self) -> Result<crate::ReviewDailyLimits, ApplicationError>;
    fn save_review_daily_limits(
        &self,
        limits: crate::ReviewDailyLimits,
    ) -> Result<crate::ReviewDailyLimits, ApplicationError>;
    fn list_imported_deck_schedules(
        &self,
    ) -> Result<Vec<crate::ImportedDeckSchedule>, ApplicationError>;
    fn import_anki_package(
        &self,
        request: &crate::AnkiPackageImportRequest,
    ) -> Result<crate::AnkiPackageImportSummary, ApplicationError>;
    fn export_anki_package(
        &self,
        request: &crate::AnkiPackageExportRequest,
    ) -> Result<crate::AnkiPackageExportSummary, ApplicationError>;
}

/// Hunting candidates and targets evolve together as one discovery workflow.
pub trait HuntingRepository: Send + Sync {
    fn upsert_hunting_candidate(
        &self,
        candidate: &HuntingCandidate,
    ) -> Result<HuntingCandidate, ApplicationError>;
    fn get_hunting_candidate(
        &self,
        id: &HuntingCandidateId,
    ) -> Result<Option<HuntingCandidate>, ApplicationError>;
    fn list_hunting_candidates(
        &self,
        status: Option<HuntingCandidateStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<HuntingCandidate>, ApplicationError>;
    fn upsert_hunting_target(
        &self,
        target: &HuntingTarget,
    ) -> Result<HuntingTarget, ApplicationError>;
    fn get_hunting_target(
        &self,
        id: &HuntingTargetId,
    ) -> Result<Option<HuntingTarget>, ApplicationError>;
    fn list_hunting_targets(
        &self,
        status: Option<HuntingTargetStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<HuntingTarget>, ApplicationError>;
}

/// Recognition evidence and upgrade suggestions share the promotion invariant.
pub trait RecognitionUpgradeRepository: Send + Sync {
    fn upsert_recognition_evidence(
        &self,
        evidence: &RecognitionEvidence,
    ) -> Result<RecognitionEvidence, ApplicationError>;
    fn list_recognition_evidence(
        &self,
        lexical_entry_id: &LexicalEntryId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<RecognitionEvidence>, ApplicationError>;
    fn save_upgrade_suggestion(
        &self,
        suggestion: &UpgradeSuggestion,
    ) -> Result<UpgradeSuggestion, ApplicationError>;
    fn get_upgrade_suggestion(
        &self,
        id: &UpgradeSuggestionId,
    ) -> Result<Option<UpgradeSuggestion>, ApplicationError>;
    fn list_upgrade_suggestions(
        &self,
        lexical_entry_id: Option<&LexicalEntryId>,
        status: Option<UpgradeSuggestionStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<UpgradeSuggestion>, ApplicationError>;
}

pub trait LearningEventRepository: Send + Sync {
    fn append_learning_event(
        &self,
        event: &LearningEvent,
    ) -> Result<LearningEvent, ApplicationError>;
    fn list_learning_events(
        &self,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LearningEvent>, ApplicationError>;
    fn list_learning_events_for_session(
        &self,
        session_id: &PracticeSessionId,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LearningEvent>, ApplicationError>;
    /// Distinct subject ids that carry at least one event of `kind` on
    /// `subject_kind` — e.g. media marked as familiar material.
    fn list_event_subject_ids(
        &self,
        kind: LearningEventKind,
        subject_kind: LearningEventSubjectKind,
    ) -> Result<Vec<String>, ApplicationError>;
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CoachDashboardFacts {
    pub practice_attempts: u64,
    pub correct_practice_attempts: u64,
    pub review_attempts: u64,
    pub successful_review_attempts: u64,
    pub extensive_sessions: u64,
    pub extensive_listening_ms: u64,
    pub due_review_items: u64,
    pub active_hunting_candidates: u64,
    pub l1_difficulty_hits: u64,
    pub listening_capability_changes: u64,
    pub channels: Vec<CoachChannelFacts>,
    pub cross_modal_gap_count: u64,
    pub personal_expression_asset_count: u64,
    pub llm_provider_profile_count: u64,
    pub materials: Vec<CoachMaterialFact>,
}

/// Read-only, already-layered facts for one capability channel. Counts remain
/// separate so the Coach cannot collapse attempts, supporting judgments,
/// proposals, confirmed projections, overrides, and effective assessment into
/// a second capability truth.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CoachChannelFacts {
    pub channel: String,
    pub completed_attempts: u64,
    pub supporting_judgments: u64,
    pub adjudications: u64,
    pub observations: u64,
    pub projection_proposals: u64,
    pub confirmed_projections: u64,
    pub capability_changes: u64,
    pub personal_expression_attempts: u64,
    pub acquired_entries: u64,
    pub not_acquired_entries: u64,
    pub unassessed_entries: u64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CoachMaterialFact {
    pub media_id: String,
    pub title: String,
    pub report_count: u64,
    pub first_report: Option<String>,
    pub latest_report: Option<String>,
    pub reports_understood_all: u64,
    pub reports_got_the_gist: u64,
    pub reports_unclear: u64,
    pub practice_attempts: u64,
    pub practice_correct: u64,
    pub triage_intent: Option<String>,
}

pub trait CoachDashboardRepository: Send + Sync {
    fn coach_dashboard_facts(
        &self,
        language: &LanguageCode,
        period_start_ms: u64,
        period_end_ms: u64,
        as_of_ms: u64,
    ) -> Result<CoachDashboardFacts, ApplicationError>;
    fn coach_evidence(
        &self,
        metric: &str,
        period_start_ms: u64,
        period_end_ms: u64,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<CoachEvidenceFact>, ApplicationError>;
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CoachEvidenceFact {
    pub id: String,
    pub occurred_at_ms: u64,
    pub result: String,
    pub source_kind: String,
    pub snapshot: String,
    pub source_available: bool,
    pub unavailable_reason: Option<String>,
}

pub trait ListeningInboxRepository: Send + Sync {
    fn upsert_listening_inbox_item(
        &self,
        item: &ListeningInboxItem,
    ) -> Result<ListeningInboxItem, ApplicationError>;
    fn get_listening_inbox_item(
        &self,
        id: &ListeningInboxItemId,
    ) -> Result<Option<ListeningInboxItem>, ApplicationError>;
    fn list_listening_inbox_items(
        &self,
        status: Option<ListeningInboxStatus>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ListeningInboxItem>, ApplicationError>;
}

pub trait CorpusIndexRepository: Send + Sync {
    /// Atomically replaces the rebuildable projection for one subtitle track.
    /// The source subtitle remains authoritative; callers never patch single
    /// rows in response to a learning action.
    fn replace_corpus_occurrences_for_track(
        &self,
        track_id: &SubtitleTrackId,
        occurrences: &[CorpusOccurrence],
    ) -> Result<(), ApplicationError>;
    fn upsert_corpus_occurrence(
        &self,
        occurrence: &CorpusOccurrence,
    ) -> Result<CorpusOccurrence, ApplicationError>;
    fn search_corpus_occurrences(
        &self,
        language: &LanguageCode,
        query: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError>;
    fn media_has_corpus_occurrences(
        &self,
        media_id: &MediaId,
        track_id: Option<&SubtitleTrackId>,
    ) -> Result<bool, ApplicationError>;
    fn search_corpus_occurrences_in_media(
        &self,
        language: &LanguageCode,
        query: &str,
        media_id: &MediaId,
        track_id: Option<&SubtitleTrackId>,
        limit: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError>;
    fn get_corpus_occurrence(
        &self,
        id: &CorpusOccurrenceId,
    ) -> Result<Option<CorpusOccurrence>, ApplicationError>;
    /// Rebuild input for the semantic read model. Only phrase/chunk rows are
    /// returned; lexical and connected-speech rows remain exact-key assets.
    fn list_semantic_corpus_occurrences(&self) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        Ok(Vec::new())
    }
    /// Connected-speech family aggregation (Phase 3.9): occurrences of kind
    /// `connected_speech` whose `normalized_key` is one of `families`,
    /// round-robin interleaved across media like word search. `media_id`
    /// narrows to one media for the current-media degraded path.
    fn search_corpus_family_occurrences(
        &self,
        language: &LanguageCode,
        families: &[String],
        media_id: Option<&MediaId>,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError>;
}

/// Phase 3.15.5 personal production corpus — a rebuildable projection over
/// immutable semantic attempts. Rows mint no identity and are always safe to
/// delete and regenerate; the repository therefore only offers whole-rubric
/// replacement, never row patching.
pub trait ProductionCorpusRepository: Send + Sync {
    /// Atomically replaces every projection row derived from one rubric's
    /// attempts (a rubric groups all attempts over one source/task).
    fn replace_production_entries_for_rubric(
        &self,
        rubric_id: &SemanticRubricId,
        documents: &[ProductionCorpusDocument],
        entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError>;
    /// Atomically replaces the complete projection after all source attempts
    /// have been derived successfully. A failed rebuild leaves the previous
    /// readable projection intact.
    fn replace_all_production_entries(
        &self,
        documents: &[ProductionCorpusDocument],
        entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError>;
    fn replace_production_entries_for_realtime_turn(
        &self,
        turn_id: &RealtimeConversationTurnId,
        documents: &[ProductionCorpusDocument],
        entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError>;
    /// Exact lemma lookup, newest first.
    fn list_production_entries_by_key(
        &self,
        language: &LanguageCode,
        normalized_key: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ProductionCorpusHit>, ApplicationError>;
    /// FTS phrase lookup over one-copy-per-revision response documents.
    fn search_production_documents(
        &self,
        language: &LanguageCode,
        query: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<ProductionCorpusHit>, ApplicationError>;
    fn production_corpus_summary(
        &self,
        language: &LanguageCode,
        channel: domain::ProductionChannel,
    ) -> Result<ProductionCorpusSummary, ApplicationError>;
    fn list_production_gap_candidates(
        &self,
        language: &LanguageCode,
        channel: domain::ProductionChannel,
    ) -> Result<Vec<ProductionGapCandidateFacts>, ApplicationError>;
    /// Rebuild input for semantic document search. These rows are already a
    /// projection of immutable learner attempts/local-authoritative turns.
    fn list_production_documents(&self) -> Result<Vec<ProductionCorpusDocument>, ApplicationError> {
        Ok(Vec::new())
    }
    /// Distinct actually-produced lemmas used only to enrich the existing
    /// read-only gap result. This never manufactures a gap candidate.
    fn list_production_lexemes(
        &self,
        language: &LanguageCode,
        channel: domain::ProductionChannel,
    ) -> Result<Vec<String>, ApplicationError> {
        let _ = (language, channel);
        Ok(Vec::new())
    }
}

/// Phase 3.16 durable user-owned patterns. Unlike production corpus and
/// embedding indexes, these rows are authoritative assets and are never
/// rebuildable projections.
pub trait PersonalExpressionRepository: Send + Sync {
    fn create_pattern(
        &self,
        asset: &domain::UserSentencePatternAsset,
    ) -> Result<domain::UserSentencePatternAsset, ApplicationError>;
    fn append_pattern_version(
        &self,
        pattern_id: &domain::UserSentencePatternId,
        version: &domain::UserSentencePatternVersion,
        updated_at_ms: u64,
    ) -> Result<domain::UserSentencePatternAsset, ApplicationError>;
    fn get_pattern(
        &self,
        id: &domain::UserSentencePatternId,
    ) -> Result<Option<domain::UserSentencePatternAsset>, ApplicationError>;
    fn list_patterns(
        &self,
        language: Option<&LanguageCode>,
        query: Option<&str>,
    ) -> Result<Vec<domain::UserSentencePatternAsset>, ApplicationError>;
    fn list_pattern_versions(
        &self,
        id: &domain::UserSentencePatternId,
    ) -> Result<Vec<domain::UserSentencePatternVersion>, ApplicationError>;
    fn delete_pattern(&self, id: &domain::UserSentencePatternId) -> Result<bool, ApplicationError>;
    fn save_personal_expression_attempt(
        &self,
        attempt: &domain::PersonalExpressionAttempt,
    ) -> Result<domain::PersonalExpressionAttempt, ApplicationError>;
    fn list_personal_expression_attempts(
        &self,
        id: &domain::UserSentencePatternId,
    ) -> Result<Vec<domain::PersonalExpressionAttempt>, ApplicationError>;
}

pub trait SemanticEmbeddingIndexRepository: Send + Sync {
    /// Atomically replaces the whole model-specific read model. A failed
    /// rebuild must leave the previous index readable.
    fn replace_semantic_embedding_index(
        &self,
        model_fingerprint: &str,
        records: &[domain::SemanticEmbeddingIndexRecord],
    ) -> Result<(), ApplicationError>;
    fn list_semantic_embedding_records(
        &self,
        model_fingerprint: &str,
    ) -> Result<Vec<domain::SemanticEmbeddingIndexRecord>, ApplicationError>;
    fn semantic_embedding_index_summary(&self) -> Result<Vec<(String, u32)>, ApplicationError>;
    fn delete_semantic_embedding_index(&self) -> Result<(), ApplicationError>;
}

pub trait DifficultyRepository: Send + Sync {
    fn save_difficulty_profile(
        &self,
        profile: &ContentDifficultyProfile,
    ) -> Result<ContentDifficultyProfile, ApplicationError>;
    fn get_difficulty_profile(
        &self,
        subject_kind: &str,
        subject_id: &str,
    ) -> Result<Option<ContentDifficultyProfile>, ApplicationError>;
    /// Durable usage-feedback record (Phase 3.5 Slice 7) — evidence, not
    /// cache: it must survive profile recomputes and cache invalidation.
    fn save_fit_calibration(
        &self,
        calibration: &SoundFitCalibration,
    ) -> Result<SoundFitCalibration, ApplicationError>;
    fn get_fit_calibration(
        &self,
        subject_kind: &str,
        subject_id: &str,
    ) -> Result<Option<SoundFitCalibration>, ApplicationError>;
}

pub trait LearnerProfileRepository: Send + Sync {
    fn save_learner_profile(
        &self,
        profile: &LearnerProfile,
    ) -> Result<LearnerProfile, ApplicationError>;
    fn get_learner_profile(
        &self,
        id: &LearnerProfileId,
    ) -> Result<Option<LearnerProfile>, ApplicationError>;
}

/// Reading cursor persistence (Phase 3.13). Upsert semantics: the position
/// is a cursor, not evidence, so overwriting is the intended behavior.
pub trait ReadingPositionRepository: Send + Sync {
    fn save_reading_position(
        &self,
        position: &ReadingPosition,
    ) -> Result<ReadingPosition, ApplicationError>;
    fn get_reading_position(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<ReadingPosition>, ApplicationError>;
}

pub trait RecordingRepository: Send + Sync {
    fn save_recording_asset(
        &self,
        asset: &RecordingAsset,
    ) -> Result<RecordingAsset, ApplicationError>;
    fn get_recording_asset(
        &self,
        id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError>;
    fn delete_recording_asset(
        &self,
        id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError>;
    fn save_shadowing_analysis(
        &self,
        record: &ShadowingAnalysisRecord,
    ) -> Result<ShadowingAnalysisRecord, ApplicationError>;
    fn latest_shadowing_analysis(
        &self,
        recording_id: &RecordingAssetId,
    ) -> Result<Option<ShadowingAnalysisRecord>, ApplicationError>;
}

/// Phase 3.11 semantic task fact layer (ADR 0021). Submitted facts are append-only end to end:
/// there are intentionally no update or delete methods, and implementations
/// must not add them — corrections are new rows. The explicitly named draft
/// methods are the sole mutable crash-recovery projection and are not evidence.
pub trait SemanticTaskRepository: Send + Sync {
    fn save_semantic_rubric(
        &self,
        rubric: &SemanticRubric,
    ) -> Result<SemanticRubric, ApplicationError>;
    fn get_semantic_rubric(
        &self,
        id: &SemanticRubricId,
        version: u32,
    ) -> Result<Option<SemanticRubric>, ApplicationError>;
    fn latest_semantic_rubric(
        &self,
        id: &SemanticRubricId,
    ) -> Result<Option<SemanticRubric>, ApplicationError>;
    /// Latest rubric version matching one source identity tuple. Read-side
    /// lookup so clients can find an existing rubric without re-deriving the
    /// server-minted fingerprint id (Phase 3.13).
    #[allow(clippy::too_many_arguments)]
    fn find_semantic_rubric_by_source(
        &self,
        media_id: Option<&MediaId>,
        start_ms: u64,
        end_ms: u64,
        purpose: SemanticTaskKind,
        response_language: &LanguageCode,
        source_sha256: &str,
    ) -> Result<Option<SemanticRubric>, ApplicationError>;
    fn save_semantic_attempt(
        &self,
        attempt: &SemanticTaskAttempt,
    ) -> Result<SemanticTaskAttempt, ApplicationError>;
    fn get_semantic_attempt(
        &self,
        id: &SemanticTaskAttemptId,
    ) -> Result<Option<SemanticTaskAttempt>, ApplicationError>;
    fn list_semantic_attempts_for_rubric(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<Vec<SemanticTaskAttempt>, ApplicationError>;
    /// Every attempt of the given kinds, oldest first — the full-rebuild feed
    /// for kind-scoped projections (Phase 3.15.5 production corpus).
    fn list_semantic_attempts_by_kinds(
        &self,
        kinds: &[SemanticTaskKind],
    ) -> Result<Vec<SemanticTaskAttempt>, ApplicationError>;
    fn save_semantic_judgment(
        &self,
        judgment: &SemanticJudgment,
    ) -> Result<SemanticJudgment, ApplicationError>;
    fn get_semantic_judgment(
        &self,
        id: &SemanticJudgmentId,
    ) -> Result<Option<SemanticJudgment>, ApplicationError>;
    fn list_semantic_judgments_for_attempt(
        &self,
        attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<SemanticJudgment>, ApplicationError>;
    fn save_judgment_adjudication(
        &self,
        adjudication: &JudgmentAdjudication,
    ) -> Result<JudgmentAdjudication, ApplicationError>;
    fn list_judgment_adjudications(
        &self,
        judgment_id: &SemanticJudgmentId,
    ) -> Result<Vec<JudgmentAdjudication>, ApplicationError>;
    fn save_writing_feedback_finding(
        &self,
        finding: &WritingFeedbackFinding,
    ) -> Result<WritingFeedbackFinding, ApplicationError>;
    fn get_writing_feedback_finding(
        &self,
        id: &WritingFeedbackFindingId,
    ) -> Result<Option<WritingFeedbackFinding>, ApplicationError>;
    fn list_writing_feedback_findings(
        &self,
        attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<WritingFeedbackFinding>, ApplicationError>;
    fn save_writing_finding_disposition(
        &self,
        disposition: &WritingFindingDisposition,
    ) -> Result<WritingFindingDisposition, ApplicationError>;
    fn get_writing_finding_disposition(
        &self,
        id: &WritingFindingDispositionId,
    ) -> Result<Option<WritingFindingDisposition>, ApplicationError>;
    fn list_writing_finding_dispositions(
        &self,
        finding_id: &WritingFeedbackFindingId,
    ) -> Result<Vec<WritingFindingDisposition>, ApplicationError>;
    fn upsert_writing_draft(&self, draft: &WritingDraft) -> Result<WritingDraft, ApplicationError>;
    fn get_writing_draft(
        &self,
        rubric_id: &SemanticRubricId,
    ) -> Result<Option<WritingDraft>, ApplicationError>;
    fn delete_writing_draft(&self, rubric_id: &SemanticRubricId) -> Result<(), ApplicationError>;
}

/// Phase 3.12 provider profiles. Unlike append-only semantic facts, a provider
/// configuration is mutable: it may be edited or removed. Only routing metadata
/// and an opaque `auth_ref` are stored; secrets live in the OS keychain.
/// Durable outbox for removing opaque secret-store references. Profile
/// mutations enqueue cleanup in the same database transaction; deletion from
/// the OS keychain is retried until this outbox entry can be acknowledged.
pub trait SecretCleanupRepository: Send + Sync {
    fn reserve_secret_cleanup(&self, auth_ref: &SecretRef) -> Result<(), ApplicationError>;
    fn schedule_secret_cleanup(&self, auth_ref: &SecretRef) -> Result<(), ApplicationError>;
    fn recover_secret_cleanup_reservations(&self) -> Result<usize, ApplicationError>;
    fn pending_secret_cleanups(&self) -> Result<Vec<SecretRef>, ApplicationError>;
    fn complete_secret_cleanup(&self, auth_ref: &SecretRef) -> Result<(), ApplicationError>;
}

pub trait LlmProviderProfileRepository: SecretCleanupRepository {
    fn upsert_provider_profile(
        &self,
        profile: &LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError>;
    fn get_provider_profile(
        &self,
        id: &LlmProviderProfileId,
    ) -> Result<Option<LlmProviderProfile>, ApplicationError>;
    fn list_provider_profiles(&self) -> Result<Vec<LlmProviderProfile>, ApplicationError>;
    fn delete_provider_profile(&self, id: &LlmProviderProfileId) -> Result<(), ApplicationError>;
    fn upsert_provider_profile_preserving_credential(
        &self,
        profile: &LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError>;
    /// Atomically commits the profile mutation and any stale credential's
    /// durable cleanup-outbox entry.
    fn upsert_provider_profile_and_schedule_cleanup(
        &self,
        profile: &LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError>;
    /// Atomically removes the profile and records its credential for retryable
    /// cleanup.
    fn delete_provider_profile_and_schedule_cleanup(
        &self,
        id: &LlmProviderProfileId,
    ) -> Result<(), ApplicationError>;
}

/// Realtime provider config plus local session/turn facts. Provider events may
/// update live transcript fields, but finalized local learner transcripts are
/// immutable and repository implementations must reject divergent rewrites.
pub trait RealtimeConversationRepository: SecretCleanupRepository {
    fn upsert_realtime_profile(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError>;
    fn get_realtime_profile(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<Option<RealtimeProviderProfile>, ApplicationError>;
    fn list_realtime_profiles(&self) -> Result<Vec<RealtimeProviderProfile>, ApplicationError>;
    fn delete_realtime_profile(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<(), ApplicationError>;
    /// Persists profile settings without changing an existing credential.
    ///
    /// A missing write-only secret means "keep the current credential" for an
    /// existing profile and "create a keyless profile" for a new profile.
    fn upsert_realtime_profile_preserving_credential(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError>;
    /// Atomically commits the profile mutation and any stale credential's
    /// durable cleanup-outbox entry.
    fn upsert_realtime_profile_and_schedule_cleanup(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError>;
    /// Atomically removes the profile and records its credential for retryable
    /// cleanup.
    fn delete_realtime_profile_and_schedule_cleanup(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<(), ApplicationError>;
    fn save_realtime_session(
        &self,
        session: &RealtimeConversationSession,
    ) -> Result<RealtimeConversationSession, ApplicationError>;
    fn get_realtime_session(
        &self,
        id: &RealtimeConversationSessionId,
    ) -> Result<Option<RealtimeConversationSession>, ApplicationError>;
    fn list_realtime_sessions(&self) -> Result<Vec<RealtimeConversationSession>, ApplicationError>;
    fn save_realtime_turn(
        &self,
        turn: &RealtimeConversationTurn,
    ) -> Result<RealtimeConversationTurn, ApplicationError>;
    fn get_realtime_turn(
        &self,
        id: &RealtimeConversationTurnId,
    ) -> Result<Option<RealtimeConversationTurn>, ApplicationError>;
    fn list_realtime_turns(
        &self,
        session_id: &RealtimeConversationSessionId,
    ) -> Result<Vec<RealtimeConversationTurn>, ApplicationError>;
}

pub trait DictionaryCacheRepository: Send + Sync {
    fn put(&self, entry: &DictionaryEntry) -> Result<(), ApplicationError>;
    fn get(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
        provider: &str,
    ) -> Result<Option<DictionaryEntry>, ApplicationError>;
}

pub trait PlaybackProgressRepository: Send + Sync {
    fn load(&self, media_id: &MediaId) -> Result<Option<TimeMs>, ApplicationError>;
    fn save(&self, media_id: &MediaId, position: TimeMs) -> Result<(), ApplicationError>;
}

pub trait TranscriptionRepository: Send + Sync {
    fn upsert_model(
        &self,
        model: &TranscriptionModelDescriptor,
    ) -> Result<TranscriptionModelDescriptor, ApplicationError>;
    fn list_models(&self) -> Result<Vec<TranscriptionModelDescriptor>, ApplicationError>;
    fn get_model(
        &self,
        id: &TranscriptionModelId,
    ) -> Result<Option<TranscriptionModelDescriptor>, ApplicationError>;
    fn delete_model(&self, id: &TranscriptionModelId) -> Result<(), ApplicationError>;
}

pub trait PhoneticAnalysisRepository: Send + Sync {
    fn upsert_phonetic_model(
        &self,
        model: &PhoneticAnalysisModelDescriptor,
    ) -> Result<PhoneticAnalysisModelDescriptor, ApplicationError>;
    fn list_phonetic_models(
        &self,
    ) -> Result<Vec<PhoneticAnalysisModelDescriptor>, ApplicationError>;
    fn get_phonetic_model(
        &self,
        id: &PhoneticAnalysisModelId,
    ) -> Result<Option<PhoneticAnalysisModelDescriptor>, ApplicationError>;
    fn delete_phonetic_model(&self, id: &PhoneticAnalysisModelId) -> Result<(), ApplicationError>;
    fn create_phonetic_job(
        &self,
        job: &PhoneticAnalysisJob,
    ) -> Result<PhoneticAnalysisJob, ApplicationError>;
    fn update_phonetic_job(
        &self,
        job: &PhoneticAnalysisJob,
    ) -> Result<PhoneticAnalysisJob, ApplicationError>;
    fn get_phonetic_job(
        &self,
        id: &PhoneticAnalysisJobId,
    ) -> Result<Option<PhoneticAnalysisJob>, ApplicationError>;
    fn list_phonetic_jobs(&self) -> Result<Vec<PhoneticAnalysisJob>, ApplicationError>;
    fn find_completed_phonetic_job(
        &self,
        input_fingerprint: &str,
    ) -> Result<Option<PhoneticAnalysisJob>, ApplicationError>;
    fn delete_phonetic_job(&self, id: &PhoneticAnalysisJobId) -> Result<(), ApplicationError>;
    fn delete_terminal_phonetic_jobs(&self) -> Result<u64, ApplicationError>;
    fn interrupt_active_phonetic_jobs(&self, updated_at_ms: u64) -> Result<(), ApplicationError>;
    fn save_phonetic_analysis(
        &self,
        analysis: &PhoneticAnalysis,
    ) -> Result<PhoneticAnalysis, ApplicationError>;
    fn get_phonetic_analysis(
        &self,
        id: &PhoneticAnalysisId,
    ) -> Result<Option<PhoneticAnalysis>, ApplicationError>;
    fn list_track_phonetic_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneticAnalysis>, ApplicationError>;
    fn save_phonetic_feedback(
        &self,
        feedback: &PhoneticFindingFeedback,
    ) -> Result<PhoneticFindingFeedback, ApplicationError>;
    fn get_phonetic_feedback(
        &self,
        finding_id: &PhoneticFindingId,
    ) -> Result<Option<PhoneticFindingFeedback>, ApplicationError>;
}
