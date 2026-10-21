use domain::{
    CapabilityFilter, CapabilityOverride, CapabilityProjection, ContentDifficultyProfile,
    CorpusOccurrence, CorpusOccurrenceId, DictionaryEntry, HuntingCandidate, HuntingCandidateId,
    HuntingCandidateStatus, HuntingTarget, HuntingTargetId, HuntingTargetStatus,
    LLTimelineArtifact, LLTimelineMetadata, LanguageCode, LearnerProfile, LearnerProfileId,
    LearningChangeSource, LearningEvent, LearningEventKind, LearningEventSubjectKind,
    LearningObservation, LearningStatus, LexicalCapability, LexicalCapabilityHistory,
    LexicalCapabilityProfile, LexicalEntry, LexicalEntryDetails, LexicalEntryId, LexicalEntryKind,
    LexicalObservation, LexicalOccurrenceId, LexicalSenseFolder, LexicalSenseId,
    ListeningInboxItem, ListeningInboxItemId, ListeningInboxStatus, LlmProviderProfile,
    LlmProviderProfileId, MediaAvailability, MediaId, MediaItem, MediaTriageIntent, PhoneTimeline,
    PhoneTimelineId, PhoneticAnalysis, PhoneticAnalysisId, PhoneticAnalysisJob,
    PhoneticAnalysisJobId, PhoneticAnalysisModelDescriptor, PhoneticAnalysisModelId,
    PhoneticFindingFeedback, PhoneticFindingId, PracticeAttempt, PracticeAttemptId, PracticeItem,
    PracticeItemId, PracticeSession, PracticeSessionId, ProsodyAnalysis, ProsodyAnalysisId,
    RecognitionEvidence, ReviewAttempt, ReviewAttemptId, ReviewItem, ReviewItemId,
    ReviewItemStatus, ReviewSchedule, SecretRef, SenseGroupAnalysis, SenseGroupAnalysisId,
    SentencePronunciation, SoundFitCalibration, SubtitleSentence, SubtitleSentenceId,
    SubtitleTrack, SubtitleTrackId, SubtitleTrackStatus, TimeMs, UpgradeSuggestion,
    UpgradeSuggestionId, UpgradeSuggestionStatus, VocabularyAssetBundle, WordPronunciation,
    WordTimeline, WordTimelineId, WordTiming,
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
    /// Changes Personal Library membership for an existing media item.
    /// Mutates only `retained_at_ms` and `updated_at_ms`; media identity,
    /// availability, and every learner-owned or resource record stay
    /// untouched. `None` removes membership, `Some(timestamp)` records it.
    fn set_library_membership(
        &self,
        id: &MediaId,
        retained_at_ms: Option<u64>,
        updated_at_ms: u64,
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

/// Prosody analyses are the single semantic source for the Prosodic Chunk
/// foundation slot. Imported package resources enter as candidates and are
/// never activated by import; activation is an explicit Core lifecycle
/// decision.
pub trait ProsodyAnalysisRepository: Send + Sync {
    fn save_prosody_analysis(
        &self,
        analysis: &ProsodyAnalysis,
    ) -> Result<ProsodyAnalysis, ApplicationError>;
    fn list_prosody_analyses(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ProsodyAnalysis>, ApplicationError>;
    fn get_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<Option<ProsodyAnalysis>, ApplicationError>;
    fn active_prosody_analysis(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<ProsodyAnalysis>, ApplicationError>;
    fn activate_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<ProsodyAnalysis, ApplicationError>;
    fn archive_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<ProsodyAnalysis, ApplicationError>;
    fn delete_prosody_analysis(
        &self,
        id: &ProsodyAnalysisId,
    ) -> Result<ProsodyAnalysis, ApplicationError>;
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
    pub sense_group_analyses: Vec<SenseGroupAnalysis>,
    pub prosody_analyses: Vec<ProsodyAnalysis>,
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

/// Atomic persistence boundary for one adopted Resource Package's projected
/// analysis candidates.
///
/// Unlike [`LLTimelineImportRepository`], the package subtitle track has
/// already been landed by [`crate::AppServices::land_adopted_subtitle_track`];
/// this seam only attaches immutable candidate analysis resources to that
/// track. It must never activate, archive, or replace any existing resource.
pub trait ContentPackageCandidateImportRepository: Send + Sync {
    fn import_content_package_candidates(
        &self,
        import: &ContentPackageCandidateImport,
    ) -> Result<(), ApplicationError>;
}

/// Without configured persistence every package-candidate landing errors with
/// the same not-configured message, so an unconfigured `AppServices` never
/// silently drops candidate resources.
pub(crate) struct DisabledContentPackageCandidateImportRepository;

impl ContentPackageCandidateImportRepository for DisabledContentPackageCandidateImportRepository {
    fn import_content_package_candidates(
        &self,
        _import: &ContentPackageCandidateImport,
    ) -> Result<(), ApplicationError> {
        Err(ApplicationError::Repository(
            "content package candidate import repository is not configured".into(),
        ))
    }
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
    pub sense_group_analyses: Vec<SenseGroupAnalysis>,
    pub prosody_analyses: Vec<ProsodyAnalysis>,
    pub corpus_occurrences: Vec<CorpusOccurrence>,
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
    /// Count and timestamp watermarks for listening-only capability state.
    /// Counts make same-millisecond changes invalidate derived read models.
    fn listening_capability_watermark(
        &self,
        _language: &LanguageCode,
    ) -> Result<(u64, u64, u64, u64), ApplicationError> {
        Ok((0, 0, 0, 0))
    }
    fn save_projection_proposal(
        &self,
        _proposal: &domain::ProjectionProposal,
    ) -> Result<domain::ProjectionProposal, ApplicationError> {
        Err(ApplicationError::Repository(
            "projection review repository is not configured".into(),
        ))
    }
    fn projection_proposal(
        &self,
        _id: &domain::ProjectionProposalId,
    ) -> Result<Option<domain::ProjectionProposal>, ApplicationError> {
        Err(ApplicationError::Repository(
            "projection review repository is not configured".into(),
        ))
    }
    fn list_projection_proposals(
        &self,
        _lexical_entry_id: &LexicalEntryId,
        _capability: Option<LexicalCapability>,
    ) -> Result<Vec<domain::ProjectionProposal>, ApplicationError> {
        Err(ApplicationError::Repository(
            "projection review repository is not configured".into(),
        ))
    }
    fn resolve_projection_proposal(
        &self,
        _decision: &domain::ProjectionDecision,
        _proposal: &domain::ProjectionProposal,
        _confirmed_projection: Option<CapabilityProjection>,
    ) -> Result<(), ApplicationError> {
        Err(ApplicationError::Repository(
            "projection review repository is not configured".into(),
        ))
    }
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
}

/// Automatic candidates and explicit listening targets are two stages of the
/// same workflow; candidate promotion remains a learner action.
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

/// Listening recognition evidence and its learner-confirmed upgrade
/// suggestions.
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
    /// `subject_kind`.
    fn list_event_subject_ids(
        &self,
        kind: LearningEventKind,
        subject_kind: LearningEventSubjectKind,
    ) -> Result<Vec<String>, ApplicationError>;
}

/// Listening-only source facts for the coach. This contains activity counts
/// and material self-reports, never synthesized claims for other channels.
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
    pub materials: Vec<CoachMaterialFact>,
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

pub trait CoachDashboardRepository: Send + Sync {
    fn coach_dashboard_facts(
        &self,
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
