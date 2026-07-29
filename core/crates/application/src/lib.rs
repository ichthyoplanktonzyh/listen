use std::collections::HashMap;
use std::sync::Arc;

use crate::coach_dashboard::DisabledCoachDashboardRepository;
use domain::{
    CapabilityAssessment, CapabilityConclusion, CapabilityFilter, CapabilityOverride,
    CapabilityOverrideSource, CapabilityProjection, CapabilityProjectionSource, CapabilitySupport,
    ChunkBoundarySource, ChunkId, ChunkTimeline, ChunkTimelineChunk, ChunkTimelineId,
    ChunkTimelinePrecision, ChunkTimelineSummary, ContentDifficultyProfile, CorpusOccurrence,
    CorpusOccurrenceId, CorpusOccurrenceKind, DetectedPhone, DiagnosisKind, DictionaryEntry,
    DictionaryEntryId, DictionaryLookupBundle, DictionaryProviderResult, ExternalVocabularyImport,
    ExternalVocabularyImportSummary, HuntingCandidate, HuntingCandidateId, HuntingCandidateStatus,
    HuntingTarget, HuntingTargetId, HuntingTargetStatus, JudgmentAdjudication, L1DiagnosisContext,
    L1DiagnosisHint, L1DiagnosisSpan, L1DiagnosisSupport, LISTENING_CONFIDENCE_TASK,
    LLTIMELINE_SCHEMA_V1, LLTimelineArtifact, LLTimelineDocument, LLTimelineGenerator,
    LLTimelineId, LLTimelineMedia, LLTimelineMetadata, LLTimelineRhythmFrame, LLTimelineSegment,
    LLTimelineToken, LanguageCode, LearnerProfile, LearnerProfileId, LearningChangeSource,
    LearningEvent, LearningEventId, LearningEventKind, LearningEventSubject,
    LearningEventSubjectKind, LearningObservation, LearningStatus, LexicalCapability,
    LexicalCapabilityProfile, LexicalEntry, LexicalEntryDetails, LexicalEntryId, LexicalEntryKind,
    LexicalObservation, LexicalObservationId, LexicalOccurrenceId, LexicalSenseFolder,
    LexicalSenseId, LexicalUnit, ListeningComprehensionReport, ListeningInboxItem,
    ListeningInboxItemId, ListeningInboxResolution, ListeningInboxStatus, LlmProviderProfile,
    LlmProviderProfileId, MediaAvailability, MediaId, MediaItem, MediaKind, MediaTriageIntent,
    ObservationOrigin, ObservationResult, ObservationSpec, PhoneTimeline, PhoneTimelineId,
    PhoneTimelinePrecision, PhoneTimelineSummary, PhoneticAnalysis, PhoneticAnalysisId,
    PhoneticAnalysisJob, PhoneticFindingStatus, PhraseCandidate, PracticeAnchorKind,
    PracticeAttempt, PracticeAttemptId, PracticeItem, PracticeItemId, PracticeKind, PracticeMode,
    PracticeResult, PracticeSession, PracticeSessionId, PracticeTarget, PracticeTargetKind,
    ProductionCorpusDocument, ProductionCorpusEntry, ProductionCorpusHit,
    PronunciationProviderInfo, ReadingPosition,
    RealtimeConversationSession as DomainRealtimeConversationSession,
    RealtimeConversationSessionId, RealtimeConversationTurn, RealtimeConversationTurnId,
    RealtimeProviderProfile, RealtimeProviderProfileId, RecognitionEvidence, RecognitionEvidenceId,
    RecognitionEvidenceSourceKind, ReviewAttempt, ReviewAttemptId, ReviewItem, ReviewItemId,
    ReviewItemStatus, ReviewRating, ReviewSchedule, ReviewSource, ReviewSourceKind, RhythmFrameId,
    SecretRef, SemanticJudgment, SemanticJudgmentId, SemanticRubric, SemanticRubricId,
    SemanticTaskAttempt, SemanticTaskAttemptId, SemanticTaskKind, SenseGroup, SenseGroupAnalysis,
    SenseGroupAnalysisId, SenseGroupAnalysisSummary, SenseGroupId, SentenceDiagnosis,
    SentencePronunciation, SoundFitCalibration, SubtitleSentence, SubtitleSentenceId,
    SubtitleToken, SubtitleTokenKind, SubtitleTrack, SubtitleTrackId, SubtitleTrackStatus,
    SyntacticAnalysis, TimeMs, TimelineCreator, TimelineMetrics, TimelineStatus, TimingSource,
    UpgradeSuggestion, UpgradeSuggestionId, UpgradeSuggestionStatus, VocabularyAssetBundle,
    WordPronunciation, WordTimeline, WordTimelineId, WordTimelineLifecycleStage,
    WordTimelineSummary, WordTiming, WritingDraft, WritingFeedbackFinding,
    WritingFeedbackFindingId, WritingFindingDisposition, WritingFindingDispositionId,
    learning_observation_id, normalize_lemma, observation_spec_for_marking,
    observation_spec_for_practice, observation_spec_for_reading_marking,
    observation_spec_for_review, observation_spec_for_speaking_production,
    observation_spec_for_upgrade_confirmation, projection_proposal_v1, validate_syntactic_analysis,
};

mod background_jobs;
pub mod batch_governor;

mod chunks;
mod coach_dashboard;
mod content_fit;
mod corpus;
mod diagnosis;
mod dictionary;
mod dto;
mod error;
mod evaluator;
mod hunting;
mod learner_profile;
mod lexical;
mod listening;
mod llm_provider;
mod media;
mod personal_expression;
mod phones;
mod phonetic_fixture;
mod practice;
mod production_corpus;
mod projection_review;
mod pronunciation;
mod pronunciation_providers;
mod providers;
mod reading;
mod realtime_conversation;
mod recording;
mod repositories;
mod secret_store;
mod semantic_embedding;
mod semantic_task;
mod sense_groups;
mod speech_synthesis;
mod subtitles;
mod syntactic_consumers;
mod transcription_pipeline;
mod util;
mod vocabulary;
mod word_timelines;

pub use background_jobs::{
    BackgroundJobStore, BackgroundJobTransition, InMemoryBackgroundJobStore,
};
pub use coach_dashboard::{
    CoachAssessmentSummary, CoachChannelStatus, CoachChannelSummary, CoachDashboard,
    CoachEvidenceItem, CoachFeatureAvailability, CoachMaterialInsight, CoachMetric,
    CoachSuggestion, CoachSuggestionDestination,
};
pub use dictionary::DictionaryUseCases;
pub use dto::*;
pub use error::ApplicationError;
pub use evaluator::PracticeAnswerEvaluator;
pub use learner_profile::{LearnerProfileUseCases, LearnerProfileView};
pub use lexical::LexicalLearningUseCases;
pub use llm_provider::LlmProviderUseCases;
pub use media::MediaAnalysisUseCases;
pub use personal_expression::PersonalExpressionUseCases;
pub use practice::PracticeUseCases;
pub use production_corpus::ProductionCorpusUseCases;
pub use projection_review::ProjectionReviewUseCases;
pub use pronunciation::PronunciationUseCases;
pub use pronunciation_providers::*;
pub use providers::*;
pub use reading::ReadingUseCases;
pub use realtime_conversation::*;
pub use recording::RecordingUseCases;
pub use repositories::*;
pub use secret_store::{InMemorySecretStore, SecretStore, SecretStoreError};
pub use semantic_embedding::*;
pub use semantic_task::SemanticUseCases;
pub use speech_synthesis::*;
pub use syntactic_consumers::*;
pub use util::now_ms;
pub(crate) use util::{
    clean_optional, clean_required, normalize_american_english, normalize_phrase,
    phrase_candidates, require_text,
};
pub(crate) use vocabulary::ObservationContext;

#[derive(Clone)]
pub struct AppServices {
    pub(crate) media: Arc<dyn MediaRepository>,
    pub(crate) progress: Arc<dyn PlaybackProgressRepository>,
    pub(crate) subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
    pub(crate) pronunciations: Arc<dyn PronunciationRepository>,
    pub(crate) word_timelines: Arc<dyn WordTimelineRepository>,
    pub(crate) chunk_timelines: Arc<dyn ChunkTimelineRepository>,
    pub(crate) sense_groups: Arc<dyn SenseGroupRepository>,
    pub(crate) phone_timelines: Arc<dyn PhoneTimelineRepository>,
    pub(crate) lltimeline_resources: Arc<dyn LLTimelineResourceRepository>,
    pub(crate) dictionary: Arc<dyn DictionaryCacheRepository>,
    pub(crate) lexical_capabilities: Arc<dyn LexicalCapabilityRepository>,
    pub(crate) lexical_entries: Arc<dyn LexicalEntryRepository>,
    pub(crate) learning_observations: Arc<dyn LearningObservationRepository>,
    pub(crate) lexical_content: Arc<dyn LexicalContentRepository>,
    pub(crate) vocabulary_assets: Arc<dyn VocabularyAssetRepository>,
    pub(crate) practice: Arc<dyn PracticeRepository>,
    pub(crate) review_queue: Arc<dyn ReviewQueueRepository>,
    pub(crate) hunting: Arc<dyn HuntingRepository>,
    pub(crate) recognition_upgrades: Arc<dyn RecognitionUpgradeRepository>,
    pub(crate) learning_events: Arc<dyn LearningEventRepository>,
    pub(crate) listening_inbox: Arc<dyn ListeningInboxRepository>,
    pub(crate) recordings: Arc<dyn RecordingRepository>,
    pub(crate) corpus: Arc<dyn CorpusIndexRepository>,
    pub(crate) difficulty: Arc<dyn DifficultyRepository>,
    pub(crate) learner_profiles: Arc<dyn LearnerProfileRepository>,
    pub(crate) reading_positions: Arc<dyn ReadingPositionRepository>,
    pub(crate) coach_dashboard: Arc<dyn CoachDashboardRepository>,
    pub(crate) semantic_tasks: Arc<dyn SemanticTaskRepository>,
    pub(crate) production_corpus: Arc<dyn ProductionCorpusRepository>,
    pub(crate) personal_expression: Arc<dyn PersonalExpressionRepository>,
    pub(crate) llm_provider_profiles: Arc<dyn LlmProviderProfileRepository>,
    pub(crate) realtime_conversations: Arc<dyn RealtimeConversationRepository>,
    pub(crate) semantic_embedding_index: Arc<dyn SemanticEmbeddingIndexRepository>,
    pub(crate) embedding_provider: Arc<dyn EmbeddingProvider>,
    pub(crate) lexical_normalizers: Arc<Vec<Arc<dyn LexicalNormalizationProvider>>>,
    pub(crate) pronunciation_providers: Arc<Vec<Arc<dyn PronunciationProvider>>>,
}

impl AppServices {
    pub fn practice_learning(&self) -> PracticeUseCases {
        PracticeUseCases::from_services(self)
    }

    pub fn media_analysis(&self) -> MediaAnalysisUseCases {
        MediaAnalysisUseCases::from_services(self)
    }

    pub fn lexical_learning(&self) -> LexicalLearningUseCases {
        LexicalLearningUseCases::from_services(self)
    }

    pub fn pronunciation(&self) -> PronunciationUseCases {
        PronunciationUseCases::new(
            self.pronunciations.clone(),
            self.subtitle_tracks.clone(),
            self.word_timelines.clone(),
            self.pronunciation_providers.clone(),
        )
    }

    pub fn recordings(&self) -> RecordingUseCases {
        RecordingUseCases::new(
            self.recordings.clone(),
            self.practice.clone(),
            self.learning_events.clone(),
            self.subtitle_tracks.clone(),
            self.word_timelines.clone(),
        )
    }

    pub fn dictionary(&self) -> DictionaryUseCases {
        DictionaryUseCases::new(self.dictionary.clone())
    }

    pub fn learner_profile(&self) -> LearnerProfileUseCases {
        LearnerProfileUseCases::new(self.learner_profiles.clone())
    }

    pub fn reading(&self) -> ReadingUseCases {
        ReadingUseCases::new(self.reading_positions.clone())
    }

    pub fn llm_providers(&self) -> LlmProviderUseCases {
        LlmProviderUseCases::from_services(self)
    }

    pub fn realtime_conversations(&self) -> RealtimeConversationUseCases {
        RealtimeConversationUseCases::new(self.realtime_conversations.clone())
    }

    pub fn semantic(&self) -> SemanticUseCases {
        SemanticUseCases::new(self.semantic_tasks.clone())
    }

    pub fn production_corpus(&self) -> ProductionCorpusUseCases {
        ProductionCorpusUseCases::from_services(self)
    }

    pub fn personal_expression(&self) -> PersonalExpressionUseCases {
        PersonalExpressionUseCases::new(self.personal_expression.clone())
    }

    pub fn projection_review(&self) -> ProjectionReviewUseCases {
        ProjectionReviewUseCases::new(
            self.lexical_capabilities.clone(),
            self.learning_observations.clone(),
            self.lexical_entries.clone(),
        )
    }

    pub fn semantic_embedding(&self) -> SemanticEmbeddingUseCases {
        SemanticEmbeddingUseCases::from_services(self)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn new<R, L>(
        media: Arc<dyn MediaRepository>,
        progress: Arc<dyn PlaybackProgressRepository>,
        subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
        pronunciations: Arc<dyn PronunciationRepository>,
        timelines: Arc<R>,
        lltimeline_resources: Arc<dyn LLTimelineResourceRepository>,
        dictionary: Arc<dyn DictionaryCacheRepository>,
        learning_assets: Arc<L>,
    ) -> Self
    where
        R: WordTimelineRepository
            + ChunkTimelineRepository
            + SenseGroupRepository
            + PhoneTimelineRepository
            + 'static,
        L: LexicalCapabilityRepository
            + LexicalEntryRepository
            + LearningObservationRepository
            + LexicalContentRepository
            + VocabularyAssetRepository
            + 'static,
    {
        Self {
            media,
            progress,
            subtitle_tracks,
            pronunciations,
            word_timelines: timelines.clone(),
            chunk_timelines: timelines.clone(),
            sense_groups: timelines.clone(),
            phone_timelines: timelines,
            lltimeline_resources,
            dictionary,
            lexical_capabilities: learning_assets.clone(),
            lexical_entries: learning_assets.clone(),
            learning_observations: learning_assets.clone(),
            lexical_content: learning_assets.clone(),
            vocabulary_assets: learning_assets,
            practice: Arc::new(DisabledLearningLoopRepository),
            review_queue: Arc::new(DisabledLearningLoopRepository),
            hunting: Arc::new(DisabledLearningLoopRepository),
            recognition_upgrades: Arc::new(DisabledLearningLoopRepository),
            learning_events: Arc::new(DisabledLearningLoopRepository),
            listening_inbox: Arc::new(DisabledLearningLoopRepository),
            recordings: Arc::new(DisabledLearningLoopRepository),
            corpus: Arc::new(DisabledCorpusIndexRepository),
            difficulty: Arc::new(DisabledDifficultyRepository),
            learner_profiles: Arc::new(DisabledLearnerProfileRepository),
            reading_positions: Arc::new(DisabledReadingPositionRepository),
            coach_dashboard: Arc::new(DisabledCoachDashboardRepository),
            semantic_tasks: Arc::new(DisabledSemanticTaskRepository),
            production_corpus: Arc::new(DisabledProductionCorpusRepository),
            personal_expression: Arc::new(DisabledPersonalExpressionRepository),
            llm_provider_profiles: Arc::new(DisabledLlmProviderProfileRepository),
            realtime_conversations: Arc::new(DisabledRealtimeConversationRepository),
            semantic_embedding_index: Arc::new(DisabledSemanticEmbeddingIndexRepository),
            embedding_provider: Arc::new(UnavailableEmbeddingProvider),
            lexical_normalizers: Arc::new(Vec::new()),
            pronunciation_providers: Arc::new(Vec::new()),
        }
    }

    pub fn with_coach_dashboard_repository(
        mut self,
        repository: Arc<dyn CoachDashboardRepository>,
    ) -> Self {
        self.coach_dashboard = repository;
        self
    }

    pub fn with_learning_loop_repositories<R>(
        mut self,
        practice: Arc<dyn PracticeRepository>,
        review: Arc<R>,
        learning_events: Arc<dyn LearningEventRepository>,
        listening_inbox: Arc<dyn ListeningInboxRepository>,
    ) -> Self
    where
        R: ReviewQueueRepository + HuntingRepository + RecognitionUpgradeRepository + 'static,
    {
        self.practice = practice;
        self.review_queue = review.clone();
        self.hunting = review.clone();
        self.recognition_upgrades = review;
        self.learning_events = learning_events;
        self.listening_inbox = listening_inbox;
        self
    }

    pub fn with_difficulty_repository(mut self, difficulty: Arc<dyn DifficultyRepository>) -> Self {
        self.difficulty = difficulty;
        self
    }

    pub fn with_recording_repository(mut self, recordings: Arc<dyn RecordingRepository>) -> Self {
        self.recordings = recordings;
        self
    }

    pub fn with_corpus_index_repository(mut self, corpus: Arc<dyn CorpusIndexRepository>) -> Self {
        self.corpus = corpus;
        self
    }

    pub fn with_learner_profile_repository(
        mut self,
        learner_profiles: Arc<dyn LearnerProfileRepository>,
    ) -> Self {
        self.learner_profiles = learner_profiles;
        self
    }

    pub fn with_reading_position_repository(
        mut self,
        reading_positions: Arc<dyn ReadingPositionRepository>,
    ) -> Self {
        self.reading_positions = reading_positions;
        self
    }

    pub fn with_semantic_task_repository(
        mut self,
        semantic_tasks: Arc<dyn SemanticTaskRepository>,
    ) -> Self {
        self.semantic_tasks = semantic_tasks;
        self
    }

    pub fn with_production_corpus_repository(
        mut self,
        production_corpus: Arc<dyn ProductionCorpusRepository>,
    ) -> Self {
        self.production_corpus = production_corpus;
        self
    }

    pub fn with_personal_expression_repository(
        mut self,
        repository: Arc<dyn PersonalExpressionRepository>,
    ) -> Self {
        self.personal_expression = repository;
        self
    }

    pub fn with_llm_provider_profile_repository(
        mut self,
        llm_provider_profiles: Arc<dyn LlmProviderProfileRepository>,
    ) -> Self {
        self.llm_provider_profiles = llm_provider_profiles;
        self
    }

    pub fn with_realtime_conversation_repository(
        mut self,
        repository: Arc<dyn RealtimeConversationRepository>,
    ) -> Self {
        self.realtime_conversations = repository;
        self
    }

    pub fn with_semantic_embedding(
        mut self,
        repository: Arc<dyn SemanticEmbeddingIndexRepository>,
        provider: Arc<dyn EmbeddingProvider>,
    ) -> Self {
        self.semantic_embedding_index = repository;
        self.embedding_provider = provider;
        self
    }

    pub fn with_lexical_normalizers(
        mut self,
        providers: Vec<Arc<dyn LexicalNormalizationProvider>>,
    ) -> Self {
        self.lexical_normalizers = Arc::new(providers);
        self
    }

    pub fn with_pronunciation_providers(
        mut self,
        providers: Vec<Arc<dyn PronunciationProvider>>,
    ) -> Self {
        self.pronunciation_providers = Arc::new(providers);
        self
    }
}

struct DisabledSemanticEmbeddingIndexRepository;

impl SemanticEmbeddingIndexRepository for DisabledSemanticEmbeddingIndexRepository {
    fn replace_semantic_embedding_index(
        &self,
        _model_fingerprint: &str,
        _records: &[domain::SemanticEmbeddingIndexRecord],
    ) -> Result<(), ApplicationError> {
        Err(ApplicationError::Repository(
            "semantic embedding index repository is not configured".into(),
        ))
    }

    fn list_semantic_embedding_records(
        &self,
        _model_fingerprint: &str,
    ) -> Result<Vec<domain::SemanticEmbeddingIndexRecord>, ApplicationError> {
        Ok(Vec::new())
    }

    fn semantic_embedding_index_summary(&self) -> Result<Vec<(String, u32)>, ApplicationError> {
        Ok(Vec::new())
    }

    fn delete_semantic_embedding_index(&self) -> Result<(), ApplicationError> {
        Ok(())
    }
}

struct DisabledLearningLoopRepository;

impl DisabledLearningLoopRepository {
    fn disabled() -> ApplicationError {
        ApplicationError::Repository("learning loop repository is not configured".into())
    }
}

struct DisabledDifficultyRepository;

/// L1 is an optional personalization: with no repository configured the
/// profile simply reads as absent, so diagnosis stays language-neutral
/// instead of erroring (Phase 3.9 clean-degradation guardrail).
struct DisabledLearnerProfileRepository;

impl LearnerProfileRepository for DisabledLearnerProfileRepository {
    fn save_learner_profile(
        &self,
        _profile: &LearnerProfile,
    ) -> Result<LearnerProfile, ApplicationError> {
        Err(ApplicationError::Repository(
            "learner profile repository is not configured".into(),
        ))
    }

    fn get_learner_profile(
        &self,
        _id: &LearnerProfileId,
    ) -> Result<Option<LearnerProfile>, ApplicationError> {
        Ok(None)
    }
}

/// Reading positions degrade like learner profiles: reads answer `None`
/// (fresh start), writes error so a missing store is never silently lossy.
struct DisabledReadingPositionRepository;

impl ReadingPositionRepository for DisabledReadingPositionRepository {
    fn save_reading_position(
        &self,
        _position: &ReadingPosition,
    ) -> Result<ReadingPosition, ApplicationError> {
        Err(ApplicationError::Repository(
            "reading position repository is not configured".into(),
        ))
    }

    fn get_reading_position(
        &self,
        _track_id: &SubtitleTrackId,
    ) -> Result<Option<ReadingPosition>, ApplicationError> {
        Ok(None)
    }
}

/// Semantic tasks require configured persistence: silently accepting facts
/// would lose evidence, so every method errors instead of degrading.
struct DisabledSemanticTaskRepository;

impl SemanticTaskRepository for DisabledSemanticTaskRepository {
    fn save_semantic_rubric(
        &self,
        _rubric: &SemanticRubric,
    ) -> Result<SemanticRubric, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_semantic_rubric(
        &self,
        _id: &SemanticRubricId,
        _version: u32,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        Err(Self::disabled())
    }

    fn latest_semantic_rubric(
        &self,
        _id: &SemanticRubricId,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        Err(Self::disabled())
    }

    fn find_semantic_rubric_by_source(
        &self,
        _media_id: Option<&MediaId>,
        _start_ms: u64,
        _end_ms: u64,
        _purpose: SemanticTaskKind,
        _response_language: &LanguageCode,
        _source_sha256: &str,
    ) -> Result<Option<SemanticRubric>, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_semantic_attempt(
        &self,
        _attempt: &SemanticTaskAttempt,
    ) -> Result<SemanticTaskAttempt, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_semantic_attempt(
        &self,
        _id: &SemanticTaskAttemptId,
    ) -> Result<Option<SemanticTaskAttempt>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_semantic_attempts_for_rubric(
        &self,
        _rubric_id: &SemanticRubricId,
    ) -> Result<Vec<SemanticTaskAttempt>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_semantic_attempts_by_kinds(
        &self,
        _kinds: &[SemanticTaskKind],
    ) -> Result<Vec<SemanticTaskAttempt>, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_semantic_judgment(
        &self,
        _judgment: &SemanticJudgment,
    ) -> Result<SemanticJudgment, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_semantic_judgment(
        &self,
        _id: &SemanticJudgmentId,
    ) -> Result<Option<SemanticJudgment>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_semantic_judgments_for_attempt(
        &self,
        _attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<SemanticJudgment>, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_judgment_adjudication(
        &self,
        _adjudication: &JudgmentAdjudication,
    ) -> Result<JudgmentAdjudication, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_judgment_adjudications(
        &self,
        _judgment_id: &SemanticJudgmentId,
    ) -> Result<Vec<JudgmentAdjudication>, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_writing_feedback_finding(
        &self,
        _finding: &WritingFeedbackFinding,
    ) -> Result<WritingFeedbackFinding, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_writing_feedback_finding(
        &self,
        _id: &WritingFeedbackFindingId,
    ) -> Result<Option<WritingFeedbackFinding>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_writing_feedback_findings(
        &self,
        _attempt_id: &SemanticTaskAttemptId,
    ) -> Result<Vec<WritingFeedbackFinding>, ApplicationError> {
        Err(Self::disabled())
    }

    fn save_writing_finding_disposition(
        &self,
        _disposition: &WritingFindingDisposition,
    ) -> Result<WritingFindingDisposition, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_writing_finding_disposition(
        &self,
        _id: &WritingFindingDispositionId,
    ) -> Result<Option<WritingFindingDisposition>, ApplicationError> {
        Err(Self::disabled())
    }

    fn list_writing_finding_dispositions(
        &self,
        _finding_id: &WritingFeedbackFindingId,
    ) -> Result<Vec<WritingFindingDisposition>, ApplicationError> {
        Err(Self::disabled())
    }

    fn upsert_writing_draft(
        &self,
        _draft: &WritingDraft,
    ) -> Result<WritingDraft, ApplicationError> {
        Err(Self::disabled())
    }

    fn get_writing_draft(
        &self,
        _rubric_id: &SemanticRubricId,
    ) -> Result<Option<WritingDraft>, ApplicationError> {
        Err(Self::disabled())
    }

    fn delete_writing_draft(&self, _rubric_id: &SemanticRubricId) -> Result<(), ApplicationError> {
        Err(Self::disabled())
    }
}

impl DisabledSemanticTaskRepository {
    fn disabled() -> ApplicationError {
        ApplicationError::Repository("semantic task repository is not configured".into())
    }
}

/// Without configured persistence, provider profiles simply do not exist: reads
/// return empty and writes error, so no config is silently lost.
struct DisabledLlmProviderProfileRepository;

impl SecretCleanupRepository for DisabledLlmProviderProfileRepository {
    fn reserve_secret_cleanup(&self, _auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        Err(ApplicationError::Repository(
            "llm provider profile repository is not configured".into(),
        ))
    }
    fn schedule_secret_cleanup(&self, _auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        Ok(())
    }
    fn recover_secret_cleanup_reservations(&self) -> Result<usize, ApplicationError> {
        Ok(0)
    }
    fn pending_secret_cleanups(&self) -> Result<Vec<SecretRef>, ApplicationError> {
        Ok(Vec::new())
    }
    fn complete_secret_cleanup(&self, _auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        Ok(())
    }
}

impl LlmProviderProfileRepository for DisabledLlmProviderProfileRepository {
    fn upsert_provider_profile(
        &self,
        _profile: &LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        Err(ApplicationError::Repository(
            "llm provider profile repository is not configured".into(),
        ))
    }

    fn get_provider_profile(
        &self,
        _id: &LlmProviderProfileId,
    ) -> Result<Option<LlmProviderProfile>, ApplicationError> {
        Ok(None)
    }

    fn list_provider_profiles(&self) -> Result<Vec<LlmProviderProfile>, ApplicationError> {
        Ok(Vec::new())
    }

    fn delete_provider_profile(&self, _id: &LlmProviderProfileId) -> Result<(), ApplicationError> {
        Ok(())
    }
    fn upsert_provider_profile_preserving_credential(
        &self,
        profile: &LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        self.upsert_provider_profile(profile)
    }
    fn upsert_provider_profile_and_schedule_cleanup(
        &self,
        profile: &LlmProviderProfile,
    ) -> Result<LlmProviderProfile, ApplicationError> {
        self.upsert_provider_profile(profile)
    }
    fn delete_provider_profile_and_schedule_cleanup(
        &self,
        id: &LlmProviderProfileId,
    ) -> Result<(), ApplicationError> {
        self.delete_provider_profile(id)
    }
}

struct DisabledRealtimeConversationRepository;

impl SecretCleanupRepository for DisabledRealtimeConversationRepository {
    fn reserve_secret_cleanup(&self, _auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        Err(ApplicationError::Repository(
            "realtime conversation repository is not configured".into(),
        ))
    }
    fn schedule_secret_cleanup(&self, _auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        Ok(())
    }
    fn recover_secret_cleanup_reservations(&self) -> Result<usize, ApplicationError> {
        Ok(0)
    }
    fn pending_secret_cleanups(&self) -> Result<Vec<SecretRef>, ApplicationError> {
        Ok(Vec::new())
    }
    fn complete_secret_cleanup(&self, _auth_ref: &SecretRef) -> Result<(), ApplicationError> {
        Ok(())
    }
}

#[cfg(test)]
mod disabled_provider_repository_tests {
    use super::*;

    #[test]
    fn disabled_repositories_fail_before_an_external_secret_write() {
        let auth_ref = SecretRef::new("reserved-test-reference");
        assert!(
            DisabledLlmProviderProfileRepository
                .reserve_secret_cleanup(&auth_ref)
                .is_err()
        );
        assert!(
            DisabledRealtimeConversationRepository
                .reserve_secret_cleanup(&auth_ref)
                .is_err()
        );
    }
}

impl RealtimeConversationRepository for DisabledRealtimeConversationRepository {
    fn upsert_realtime_profile(
        &self,
        _profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError> {
        Err(ApplicationError::Repository(
            "realtime conversation repository is not configured".into(),
        ))
    }
    fn get_realtime_profile(
        &self,
        _id: &RealtimeProviderProfileId,
    ) -> Result<Option<RealtimeProviderProfile>, ApplicationError> {
        Ok(None)
    }
    fn list_realtime_profiles(&self) -> Result<Vec<RealtimeProviderProfile>, ApplicationError> {
        Ok(Vec::new())
    }
    fn delete_realtime_profile(
        &self,
        _id: &RealtimeProviderProfileId,
    ) -> Result<(), ApplicationError> {
        Ok(())
    }
    fn upsert_realtime_profile_and_schedule_cleanup(
        &self,
        profile: &RealtimeProviderProfile,
    ) -> Result<RealtimeProviderProfile, ApplicationError> {
        self.upsert_realtime_profile(profile)
    }
    fn delete_realtime_profile_and_schedule_cleanup(
        &self,
        id: &RealtimeProviderProfileId,
    ) -> Result<(), ApplicationError> {
        self.delete_realtime_profile(id)
    }
    fn save_realtime_session(
        &self,
        _session: &DomainRealtimeConversationSession,
    ) -> Result<DomainRealtimeConversationSession, ApplicationError> {
        Err(ApplicationError::Repository(
            "realtime conversation repository is not configured".into(),
        ))
    }
    fn get_realtime_session(
        &self,
        _id: &RealtimeConversationSessionId,
    ) -> Result<Option<DomainRealtimeConversationSession>, ApplicationError> {
        Ok(None)
    }
    fn list_realtime_sessions(
        &self,
    ) -> Result<Vec<DomainRealtimeConversationSession>, ApplicationError> {
        Ok(Vec::new())
    }
    fn save_realtime_turn(
        &self,
        _turn: &RealtimeConversationTurn,
    ) -> Result<RealtimeConversationTurn, ApplicationError> {
        Err(ApplicationError::Repository(
            "realtime conversation repository is not configured".into(),
        ))
    }
    fn get_realtime_turn(
        &self,
        _id: &RealtimeConversationTurnId,
    ) -> Result<Option<RealtimeConversationTurn>, ApplicationError> {
        Ok(None)
    }
    fn list_realtime_turns(
        &self,
        _session_id: &RealtimeConversationSessionId,
    ) -> Result<Vec<RealtimeConversationTurn>, ApplicationError> {
        Ok(Vec::new())
    }
}

struct DisabledProductionCorpusRepository;

struct DisabledPersonalExpressionRepository;

impl PersonalExpressionRepository for DisabledPersonalExpressionRepository {
    fn create_pattern(
        &self,
        _asset: &domain::UserSentencePatternAsset,
    ) -> Result<domain::UserSentencePatternAsset, ApplicationError> {
        Err(ApplicationError::Repository(
            "personal expression repository is not configured".into(),
        ))
    }
    fn append_pattern_version(
        &self,
        _pattern_id: &domain::UserSentencePatternId,
        _version: &domain::UserSentencePatternVersion,
        _updated_at_ms: u64,
    ) -> Result<domain::UserSentencePatternAsset, ApplicationError> {
        Err(ApplicationError::Repository(
            "personal expression repository is not configured".into(),
        ))
    }
    fn get_pattern(
        &self,
        _id: &domain::UserSentencePatternId,
    ) -> Result<Option<domain::UserSentencePatternAsset>, ApplicationError> {
        Ok(None)
    }
    fn list_patterns(
        &self,
        _language: Option<&LanguageCode>,
        _query: Option<&str>,
    ) -> Result<Vec<domain::UserSentencePatternAsset>, ApplicationError> {
        Ok(Vec::new())
    }
    fn list_pattern_versions(
        &self,
        _id: &domain::UserSentencePatternId,
    ) -> Result<Vec<domain::UserSentencePatternVersion>, ApplicationError> {
        Ok(Vec::new())
    }
    fn delete_pattern(
        &self,
        _id: &domain::UserSentencePatternId,
    ) -> Result<bool, ApplicationError> {
        Ok(false)
    }
    fn save_personal_expression_attempt(
        &self,
        _attempt: &domain::PersonalExpressionAttempt,
    ) -> Result<domain::PersonalExpressionAttempt, ApplicationError> {
        Err(ApplicationError::Repository(
            "personal expression repository is not configured".into(),
        ))
    }
    fn list_personal_expression_attempts(
        &self,
        _id: &domain::UserSentencePatternId,
    ) -> Result<Vec<domain::PersonalExpressionAttempt>, ApplicationError> {
        Ok(Vec::new())
    }
}

impl ProductionCorpusRepository for DisabledProductionCorpusRepository {
    fn replace_production_entries_for_rubric(
        &self,
        _rubric_id: &SemanticRubricId,
        _documents: &[ProductionCorpusDocument],
        _entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError> {
        Ok(())
    }

    fn replace_all_production_entries(
        &self,
        _documents: &[ProductionCorpusDocument],
        _entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError> {
        Ok(())
    }

    fn replace_production_entries_for_realtime_turn(
        &self,
        _turn_id: &RealtimeConversationTurnId,
        _documents: &[ProductionCorpusDocument],
        _entries: &[ProductionCorpusEntry],
    ) -> Result<(), ApplicationError> {
        Ok(())
    }

    fn list_production_entries_by_key(
        &self,
        _language: &LanguageCode,
        _normalized_key: &str,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<ProductionCorpusHit>, ApplicationError> {
        Ok(Vec::new())
    }

    fn search_production_documents(
        &self,
        _language: &LanguageCode,
        _query: &str,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<ProductionCorpusHit>, ApplicationError> {
        Ok(Vec::new())
    }

    fn production_corpus_summary(
        &self,
        _language: &LanguageCode,
        _channel: domain::ProductionChannel,
    ) -> Result<domain::ProductionCorpusSummary, ApplicationError> {
        Ok(domain::ProductionCorpusSummary {
            document_count: 0,
            token_count: 0,
            lemma_count: 0,
        })
    }

    fn list_production_gap_candidates(
        &self,
        _language: &LanguageCode,
        _channel: domain::ProductionChannel,
    ) -> Result<Vec<domain::ProductionGapCandidateFacts>, ApplicationError> {
        Ok(Vec::new())
    }
}

struct DisabledCorpusIndexRepository;

impl CorpusIndexRepository for DisabledCorpusIndexRepository {
    fn replace_corpus_occurrences_for_track(
        &self,
        _track_id: &SubtitleTrackId,
        _occurrences: &[CorpusOccurrence],
    ) -> Result<(), ApplicationError> {
        Ok(())
    }

    fn upsert_corpus_occurrence(
        &self,
        _occurrence: &CorpusOccurrence,
    ) -> Result<CorpusOccurrence, ApplicationError> {
        Err(ApplicationError::Repository(
            "corpus index repository is not configured".into(),
        ))
    }

    fn search_corpus_occurrences(
        &self,
        _language: &LanguageCode,
        _query: &str,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        Ok(Vec::new())
    }

    fn media_has_corpus_occurrences(
        &self,
        _media_id: &MediaId,
        _track_id: Option<&SubtitleTrackId>,
    ) -> Result<bool, ApplicationError> {
        Ok(false)
    }

    fn search_corpus_occurrences_in_media(
        &self,
        _language: &LanguageCode,
        _query: &str,
        _media_id: &MediaId,
        _track_id: Option<&SubtitleTrackId>,
        _limit: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        Ok(Vec::new())
    }

    fn get_corpus_occurrence(
        &self,
        _id: &CorpusOccurrenceId,
    ) -> Result<Option<CorpusOccurrence>, ApplicationError> {
        Ok(None)
    }

    fn search_corpus_family_occurrences(
        &self,
        _language: &LanguageCode,
        _families: &[String],
        _media_id: Option<&MediaId>,
        _limit: u32,
        _offset: u32,
    ) -> Result<Vec<CorpusOccurrence>, ApplicationError> {
        Ok(Vec::new())
    }
}

impl DifficultyRepository for DisabledDifficultyRepository {
    fn save_difficulty_profile(
        &self,
        _profile: &ContentDifficultyProfile,
    ) -> Result<ContentDifficultyProfile, ApplicationError> {
        Err(ApplicationError::Repository(
            "difficulty repository is not configured".into(),
        ))
    }

    fn get_difficulty_profile(
        &self,
        _subject_kind: &str,
        _subject_id: &str,
    ) -> Result<Option<ContentDifficultyProfile>, ApplicationError> {
        Err(ApplicationError::Repository(
            "difficulty repository is not configured".into(),
        ))
    }

    fn save_fit_calibration(
        &self,
        _calibration: &SoundFitCalibration,
    ) -> Result<SoundFitCalibration, ApplicationError> {
        Err(ApplicationError::Repository(
            "difficulty repository is not configured".into(),
        ))
    }

    fn get_fit_calibration(
        &self,
        _subject_kind: &str,
        _subject_id: &str,
    ) -> Result<Option<SoundFitCalibration>, ApplicationError> {
        Err(ApplicationError::Repository(
            "difficulty repository is not configured".into(),
        ))
    }
}

pub(crate) fn timing_priority(source: TimingSource) -> u8 {
    match source {
        TimingSource::Estimated => 1,
        TimingSource::AsrReported => 2,
        TimingSource::AsrAligned => 2,
        TimingSource::ForcedAligned => 3,
        TimingSource::UserAdjusted => 4,
    }
}

pub(crate) fn validate_word_timeline_words(
    track: &SubtitleTrack,
    timings: &[WordTiming],
) -> Result<Vec<WordTiming>, ApplicationError> {
    if timings.is_empty() {
        return Err(ApplicationError::Validation("word timeline timings"));
    }
    let sentences = track
        .sentences
        .iter()
        .map(|sentence| (sentence.id.clone(), sentence))
        .collect::<std::collections::HashMap<_, _>>();
    let sentence_order = track
        .sentences
        .iter()
        .enumerate()
        .map(|(index, sentence)| (sentence.id.clone(), index))
        .collect::<std::collections::HashMap<_, _>>();
    let mut grouped = std::collections::HashMap::<SubtitleSentenceId, Vec<WordTiming>>::new();
    for timing in timings {
        let sentence = sentences
            .get(&timing.sentence_id)
            .ok_or(ApplicationError::Validation("word timing sentence"))?;
        if timing.end_ms <= timing.start_ms
            || timing.start_ms < sentence.start.get()
            || timing.end_ms > sentence.end.get()
            || !sentence.tokens.iter().any(|token| {
                token.index == timing.token_index && token.kind == SubtitleTokenKind::Word
            })
        {
            return Err(ApplicationError::Validation("word timing boundary"));
        }
        grouped
            .entry(timing.sentence_id.clone())
            .or_default()
            .push(timing.clone());
    }

    let mut values = Vec::with_capacity(timings.len());
    for (sentence_id, mut sentence_timings) in grouped {
        sentence_timings.sort_by_key(|value| (value.start_ms, value.end_ms, value.token_index));
        if sentence_timings
            .windows(2)
            .any(|pair| pair[0].end_ms > pair[1].start_ms)
        {
            return Err(ApplicationError::Validation("word timing monotonicity"));
        }
        let order = *sentence_order
            .get(&sentence_id)
            .ok_or(ApplicationError::Validation("word timing sentence"))?;
        values.extend(sentence_timings.into_iter().map(|timing| (order, timing)));
    }
    values.sort_by_key(|(sentence_order, timing)| {
        (
            *sentence_order,
            timing.start_ms,
            timing.end_ms,
            timing.token_index,
        )
    });
    Ok(values.into_iter().map(|(_, timing)| timing).collect())
}

// Construction requires complete algorithm provenance and optional parent/
// metrics together; an options bag would make incomplete snapshots possible.
#[allow(clippy::too_many_arguments)]
pub(crate) fn build_word_timeline(
    track: &SubtitleTrack,
    words: Vec<WordTiming>,
    algorithm_id: Option<String>,
    algorithm_version: Option<String>,
    config_hash: Option<String>,
    parent_timeline_id: Option<WordTimelineId>,
    created_by: Option<TimelineCreator>,
    status: TimelineStatus,
    metrics_json: Option<TimelineMetrics>,
) -> Result<WordTimeline, ApplicationError> {
    let words = validate_word_timeline_words(track, &words)?;
    let first = words
        .first()
        .ok_or(ApplicationError::Validation("word timeline timings"))?;
    let default_algorithm_id = match first.timing_source {
        TimingSource::UserAdjusted => "user-adjusted".to_owned(),
        _ => first.provider_id.clone(),
    };
    let algorithm_id = clean_required(
        algorithm_id.unwrap_or(default_algorithm_id),
        "word timeline algorithm",
    )?;
    let algorithm_version = clean_required(
        algorithm_version.unwrap_or_else(|| first.provider_version.clone()),
        "word timeline algorithm version",
    )?;
    let created_by = created_by.unwrap_or_else(|| {
        if first.timing_source == TimingSource::UserAdjusted {
            TimelineCreator::User
        } else {
            TimelineCreator::Algorithm
        }
    });
    let generated_config_hash = WordTimelineId::from_fingerprint(
        "word-timeline-config",
        &format!(
            "{}:{}:{}:{}:{}",
            track.id.as_str(),
            algorithm_id,
            algorithm_version,
            first.provider_id,
            first.provider_version
        ),
    )
    .as_str()
    .to_owned();
    let config_hash = clean_required(
        config_hash.unwrap_or(generated_config_hash),
        "word timeline config hash",
    )?;
    let now = now_ms();
    let id = WordTimelineId::from_fingerprint(
        "word-timeline",
        &format!(
            "{}:{}:{}:{}:{now}",
            track.id.as_str(),
            algorithm_id,
            algorithm_version,
            config_hash
        ),
    );
    Ok(WordTimeline {
        id,
        track_id: track.id.clone(),
        media_id: track.media_id.clone(),
        algorithm_id,
        algorithm_version,
        config_hash,
        parent_timeline_id,
        created_by,
        status,
        metrics_json: metrics_json.unwrap_or_default(),
        words,
        created_at_ms: now,
        updated_at_ms: now,
    })
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn save_word_timeline_snapshot_with_metrics(
    services: &MediaAnalysisUseCases,
    track_id: &SubtitleTrackId,
    timings: &[WordTiming],
    algorithm_id: &str,
    algorithm_version: &str,
    config_hash: &str,
    status: TimelineStatus,
    parent_timeline_id: Option<&WordTimelineId>,
    metrics_json: Option<TimelineMetrics>,
) -> Result<WordTimelineId, ApplicationError> {
    services
        .create_word_timeline(
            track_id,
            CreateWordTimeline {
                algorithm_id: Some(algorithm_id.into()),
                algorithm_version: Some(algorithm_version.into()),
                config_hash: Some(config_hash.into()),
                parent_timeline_id: parent_timeline_id.cloned(),
                created_by: Some(TimelineCreator::Algorithm),
                status: Some(status),
                metrics_json,
                words: timings.to_vec(),
            },
        )
        .map(|timeline| timeline.id)
}

pub(crate) fn forced_align_segments(sentences: &[SubtitleSentence]) -> Vec<ForcedAlignSegment> {
    sentences
        .iter()
        .filter_map(|sentence| {
            let words = sentence
                .tokens
                .iter()
                .filter(|token| token.kind == SubtitleTokenKind::Word)
                .map(|token| token.text.clone())
                .collect::<Vec<_>>();
            if words.is_empty() {
                return None;
            }
            Some(ForcedAlignSegment {
                index: sentence.index,
                text: sentence.display_text.clone(),
                words,
                start_ms: sentence.start.get(),
                end_ms: sentence.end.get(),
            })
        })
        .collect()
}

pub(crate) fn word_timeline_summary(timeline: &WordTimeline) -> WordTimelineSummary {
    let mut provider_ids = timeline
        .words
        .iter()
        .map(|word| word.provider_id.clone())
        .collect::<Vec<_>>();
    provider_ids.sort();
    provider_ids.dedup();
    let mut timing_sources = timeline
        .words
        .iter()
        .map(|word| word.timing_source)
        .collect::<Vec<_>>();
    timing_sources.sort();
    timing_sources.dedup();
    let confidence_values = timeline
        .words
        .iter()
        .filter_map(|word| word.confidence)
        .collect::<Vec<_>>();
    let average_confidence = if confidence_values.is_empty() {
        None
    } else {
        Some(confidence_values.iter().sum::<f32>() / confidence_values.len() as f32)
    };
    WordTimelineSummary {
        id: timeline.id.clone(),
        track_id: timeline.track_id.clone(),
        media_id: timeline.media_id.clone(),
        algorithm_id: timeline.algorithm_id.clone(),
        algorithm_version: timeline.algorithm_version.clone(),
        parent_timeline_id: timeline.parent_timeline_id.clone(),
        created_by: timeline.created_by,
        status: timeline.status,
        lifecycle_stage: word_timeline_lifecycle_stage(timeline),
        word_count: timeline.words.len() as u32,
        start_ms: timeline.words.iter().map(|word| word.start_ms).min(),
        end_ms: timeline.words.iter().map(|word| word.end_ms).max(),
        provider_ids,
        timing_sources,
        average_confidence,
        created_at_ms: timeline.created_at_ms,
        updated_at_ms: timeline.updated_at_ms,
        can_activate: timeline.status != TimelineStatus::Archived,
        can_archive: timeline.status != TimelineStatus::Archived,
        can_delete: true,
    }
}

pub(crate) fn word_timeline_lifecycle_stage(timeline: &WordTimeline) -> WordTimelineLifecycleStage {
    if timeline
        .metrics_json
        .as_object()
        .get("lifecycle")
        .and_then(serde_json::Value::as_object)
        .and_then(|value| value.get("published"))
        .and_then(serde_json::Value::as_bool)
        .unwrap_or(false)
    {
        WordTimelineLifecycleStage::Published
    } else if timeline.created_by == TimelineCreator::User
        || timeline
            .words
            .iter()
            .any(|word| word.timing_source == TimingSource::UserAdjusted)
    {
        WordTimelineLifecycleStage::UserAdjusted
    } else {
        WordTimelineLifecycleStage::AlgorithmCandidate
    }
}

pub(crate) fn mark_word_timeline_published(timeline: &mut WordTimeline) {
    let now = now_ms();
    let root = timeline.metrics_json.as_object_mut();
    let lifecycle = root
        .entry("lifecycle")
        .or_insert_with(|| serde_json::json!({}));
    if !lifecycle.is_object() {
        *lifecycle = serde_json::json!({});
    }
    let lifecycle = lifecycle
        .as_object_mut()
        .expect("lifecycle was normalized to object");
    lifecycle.insert("published".into(), serde_json::json!(true));
    lifecycle.insert("published_at_ms".into(), serde_json::json!(now));
}

pub(crate) fn lltimeline_segments_from_track(track: &SubtitleTrack) -> Vec<LLTimelineSegment> {
    track
        .sentences
        .iter()
        .map(|sentence| LLTimelineSegment {
            id: sentence.id.clone(),
            index: sentence.index,
            start_ms: sentence.start.get(),
            end_ms: sentence.end.get(),
            text: sentence.original_text.clone(),
            display_text: sentence.display_text.clone(),
            tokens: sentence
                .tokens
                .iter()
                .map(|token| LLTimelineToken {
                    index: token.index,
                    kind: token.kind,
                    text: token.text.clone(),
                    normalized: token.normalized.clone(),
                    start_char: token.start_char,
                    end_char: token.end_char,
                })
                .collect(),
        })
        .collect()
}

pub(crate) fn lltimeline_track_extra(
    track_id: &SubtitleTrackId,
    track_fingerprint: &str,
    track_source: &str,
) -> serde_json::Value {
    serde_json::json!({
        "track_id": track_id.as_str(),
        "track_fingerprint": track_fingerprint,
        "track_source": track_source,
    })
}

pub(crate) fn merge_lltimeline_track_extra(
    extra: serde_json::Value,
    track_id: &SubtitleTrackId,
    track_fingerprint: &str,
    track_source: &str,
) -> serde_json::Value {
    let mut merged = extra.as_object().cloned().unwrap_or_default();
    merged.insert("track_id".into(), serde_json::json!(track_id.as_str()));
    merged.insert(
        "track_fingerprint".into(),
        serde_json::json!(track_fingerprint),
    );
    merged.insert("track_source".into(), serde_json::json!(track_source));
    serde_json::Value::Object(merged)
}

pub(crate) fn lltimeline_track_id(
    document: &LLTimelineDocument,
) -> Result<SubtitleTrackId, ApplicationError> {
    if let Some(track_id) = document
        .metadata
        .extra
        .get("track_id")
        .and_then(serde_json::Value::as_str)
    {
        return SubtitleTrackId::parse(track_id.to_owned()).map_err(ApplicationError::from);
    }
    Ok(SubtitleTrackId::from_fingerprint(
        "subtitle-track",
        &format!(
            "{}:{}",
            document.metadata.media.id.as_str(),
            lltimeline_track_fingerprint(document)
        ),
    ))
}

pub(crate) fn lltimeline_track_fingerprint(document: &LLTimelineDocument) -> String {
    document
        .metadata
        .extra
        .get("track_fingerprint")
        .and_then(serde_json::Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(str::to_owned)
        .unwrap_or_else(|| {
            LLTimelineId::from_fingerprint(
                "lltimeline-track-fingerprint",
                &serde_json::to_string(&document.segments).unwrap_or_default(),
            )
            .as_str()
            .to_owned()
        })
}

/// Remap every embedded identity in an imported LLTimeline document onto the
/// destination track/media: segment/sentence ids, word/chunk/phone timeline
/// ids (including active/parent references), rhythm frame ids, chunk ids,
/// artifact payload references, and the `track_id`/`media_id` carried on each
/// resource. This function is the single owner of import identity rewriting:
/// any new ID-bearing field added to `LLTimelineDocument` must be remapped
/// here and covered by `remap_lltimeline_identity_leaves_no_original_ids`.
/// Document `metadata` stays caller-owned (it is replaced, not remapped).
pub(crate) fn remap_lltimeline_identity(
    document: &mut LLTimelineDocument,
    track_id: &SubtitleTrackId,
    media_id: &MediaId,
) {
    for timeline in &mut document.word_timelines {
        timeline.media_id = media_id.clone();
        timeline.track_id = track_id.clone();
    }
    for timeline in &mut document.chunk_timelines {
        timeline.media_id = media_id.clone();
        timeline.track_id = track_id.clone();
    }
    for timeline in &mut document.phone_timelines {
        timeline.media_id = media_id.clone();
        timeline.track_id = track_id.clone();
    }
    for analysis in &mut document.sense_group_analyses {
        analysis.media_id = media_id.clone();
        analysis.track_id = track_id.clone();
    }
    for frame in &mut document.rhythm_frames {
        frame.media_id = media_id.clone();
        frame.track_id = track_id.clone();
    }
    let mut sentence_ids = HashMap::new();
    for segment in &mut document.segments {
        let original = segment.id.clone();
        let remapped = SubtitleSentenceId::from_fingerprint(
            "subtitle-sentence",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        segment.id = remapped.clone();
        sentence_ids.insert(original, remapped);
    }
    for timeline in &mut document.word_timelines {
        for word in &mut timeline.words {
            if let Some(sentence_id) = sentence_ids.get(&word.sentence_id) {
                word.sentence_id = sentence_id.clone();
            }
        }
    }
    for chunk_timeline in &mut document.chunk_timelines {
        for chunk in &mut chunk_timeline.chunks {
            if let Some(sentence_id) = sentence_ids.get(&chunk.sentence_id) {
                chunk.sentence_id = sentence_id.clone();
            }
        }
    }
    for analysis in &mut document.sense_group_analyses {
        for group in &mut analysis.groups {
            if let Some(sentence_id) = sentence_ids.get(&group.sentence_id) {
                group.sentence_id = sentence_id.clone();
            }
        }
    }
    let mut word_timeline_ids = HashMap::new();
    for timeline in &mut document.word_timelines {
        let original = timeline.id.clone();
        let remapped = WordTimelineId::from_fingerprint(
            "word-timeline",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        timeline.id = remapped.clone();
        word_timeline_ids.insert(original, remapped);
    }
    if let Some(active_id) = document.active_word_timeline_id.as_mut()
        && let Some(remapped) = word_timeline_ids.get(active_id)
    {
        *active_id = remapped.clone();
    }
    for timeline in &mut document.word_timelines {
        if let Some(parent_id) = timeline.parent_timeline_id.as_mut()
            && let Some(remapped) = word_timeline_ids.get(parent_id)
        {
            *parent_id = remapped.clone();
        }
    }
    remap_lltimeline_artifact_refs(document, &sentence_ids, &word_timeline_ids);
    for chunk_timeline in &mut document.chunk_timelines {
        if let Some(word_timeline_id) = chunk_timeline.parent_word_timeline_id.as_mut()
            && let Some(remapped) = word_timeline_ids.get(word_timeline_id)
        {
            *word_timeline_id = remapped.clone();
        }
    }
    for frame in &mut document.rhythm_frames {
        if let Some(sentence_id) = sentence_ids.get(&frame.sentence_id) {
            frame.sentence_id = sentence_id.clone();
        }
        if let Some(word_timeline_id) = frame.parent_word_timeline_id.as_mut()
            && let Some(remapped) = word_timeline_ids.get(word_timeline_id)
        {
            *word_timeline_id = remapped.clone();
        }
    }
    for frame in &mut document.rhythm_frames {
        frame.id = RhythmFrameId::from_fingerprint(
            "rhythm-frame",
            &format!("{}:{}", track_id.as_str(), frame.id.as_str()),
        );
    }
    for phone_timeline in &mut document.phone_timelines {
        if let Some(sentence_id) = phone_timeline.sentence_id.as_mut()
            && let Some(remapped) = sentence_ids.get(sentence_id)
        {
            *sentence_id = remapped.clone();
        }
        if let Some(word_timeline_id) = phone_timeline.parent_word_timeline_id.as_mut()
            && let Some(remapped) = word_timeline_ids.get(word_timeline_id)
        {
            *word_timeline_id = remapped.clone();
        }
    }
    let mut phone_timeline_ids = HashMap::new();
    for timeline in &mut document.phone_timelines {
        let original = timeline.id.clone();
        let remapped = PhoneTimelineId::from_fingerprint(
            "phone-timeline",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        timeline.id = remapped.clone();
        phone_timeline_ids.insert(original, remapped);
    }
    if let Some(active_id) = document.active_phone_timeline_id.as_mut()
        && let Some(remapped) = phone_timeline_ids.get(active_id)
    {
        *active_id = remapped.clone();
    }
    let mut chunk_timeline_ids = HashMap::new();
    for timeline in &mut document.chunk_timelines {
        let original = timeline.id.clone();
        let remapped = ChunkTimelineId::from_fingerprint(
            "chunk-timeline",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        timeline.id = remapped.clone();
        chunk_timeline_ids.insert(original, remapped.clone());
        for chunk in &mut timeline.chunks {
            chunk.id = ChunkId::from_fingerprint(
                "chunk",
                &format!(
                    "{}:{}:{}",
                    remapped.as_str(),
                    chunk.sentence_id.as_str(),
                    chunk.chunk_index
                ),
            );
        }
    }
    if let Some(active_id) = document.active_chunk_timeline_id.as_mut()
        && let Some(remapped) = chunk_timeline_ids.get(active_id)
    {
        *active_id = remapped.clone();
    }
    for analysis in &mut document.sense_group_analyses {
        if let Some(word_timeline_id) = analysis.parent_word_timeline_id.as_mut()
            && let Some(remapped) = word_timeline_ids.get(word_timeline_id)
        {
            *word_timeline_id = remapped.clone();
        }
    }
    let mut sense_group_analysis_ids = HashMap::new();
    for analysis in &mut document.sense_group_analyses {
        let original = analysis.id.clone();
        let remapped = SenseGroupAnalysisId::from_fingerprint(
            "sense-group-analysis",
            &format!("{}:{}", track_id.as_str(), original.as_str()),
        );
        analysis.id = remapped.clone();
        sense_group_analysis_ids.insert(original, remapped.clone());
        for group in &mut analysis.groups {
            group.id = SenseGroupId::from_fingerprint(
                "sense-group",
                &format!(
                    "{}:{}:{}",
                    remapped.as_str(),
                    group.sentence_id.as_str(),
                    group.group_index
                ),
            );
        }
    }
    if let Some(active_id) = document.active_sense_group_analysis_id.as_mut()
        && let Some(remapped) = sense_group_analysis_ids.get(active_id)
    {
        *active_id = remapped.clone();
    }
}

fn remap_lltimeline_artifact_refs(
    document: &mut LLTimelineDocument,
    sentence_ids: &HashMap<SubtitleSentenceId, SubtitleSentenceId>,
    word_timeline_ids: &HashMap<WordTimelineId, WordTimelineId>,
) {
    for artifact in &mut document.artifacts {
        if artifact.kind != "rhythm_word_acoustic_cues" {
            continue;
        }
        let Some(payload) = artifact.payload.as_object_mut() else {
            continue;
        };
        if let Some(original) = payload
            .get("timeline_id")
            .and_then(serde_json::Value::as_str)
            .and_then(|value| WordTimelineId::parse(value.to_owned()).ok())
            && let Some(remapped) = word_timeline_ids.get(&original)
        {
            payload.insert(
                "timeline_id".into(),
                serde_json::Value::String(remapped.as_str().to_owned()),
            );
        }
        let Some(cues) = payload
            .get_mut("cues")
            .and_then(serde_json::Value::as_array_mut)
        else {
            continue;
        };
        for cue in cues {
            let Some(cue) = cue.as_object_mut() else {
                continue;
            };
            if let Some(original) = cue
                .get("sentence_id")
                .and_then(serde_json::Value::as_str)
                .and_then(|value| SubtitleSentenceId::parse(value.to_owned()).ok())
                && let Some(remapped) = sentence_ids.get(&original)
            {
                cue.insert(
                    "sentence_id".into(),
                    serde_json::Value::String(remapped.as_str().to_owned()),
                );
            }
        }
    }
}

pub(crate) fn lltimeline_segments_to_sentences(
    segments: &[LLTimelineSegment],
) -> Result<Vec<SubtitleSentence>, ApplicationError> {
    if segments.is_empty() {
        return Err(ApplicationError::Validation("lltimeline segments"));
    }
    let mut sentences = Vec::with_capacity(segments.len());
    for segment in segments {
        if segment.end_ms <= segment.start_ms {
            return Err(ApplicationError::Validation("lltimeline segment boundary"));
        }
        sentences.push(SubtitleSentence {
            id: segment.id.clone(),
            index: segment.index,
            start: TimeMs::new(segment.start_ms),
            end: TimeMs::new(segment.end_ms),
            original_text: segment.text.clone(),
            display_text: segment.display_text.clone(),
            tokens: segment
                .tokens
                .iter()
                .map(|token| SubtitleToken {
                    index: token.index,
                    kind: token.kind,
                    text: token.text.clone(),
                    normalized: token.normalized.clone(),
                    start_char: token.start_char,
                    end_char: token.end_char,
                })
                .collect(),
        });
    }
    sentences.sort_by_key(|sentence| (sentence.start, sentence.end, sentence.index));
    Ok(sentences)
}

pub(crate) fn word_timing_cache_is_usable(values: &[WordTiming]) -> bool {
    values.first().is_some_and(|first| {
        (first.timing_source != TimingSource::Estimated
            || (first.provider_id == "subtitle-weighted-estimator"
                && first.provider_version.starts_with("v")))
            && values.iter().all(|value| value.start_ms < value.end_ms)
    })
}

pub(crate) fn chunk_partition_config_for_track_source(
    source: &str,
) -> speech_analysis::chunking::ChunkPartitionConfig {
    if source.starts_with("ASR-") {
        speech_analysis::chunking::ChunkPartitionConfig::for_asr_generated_subtitle()
    } else {
        speech_analysis::chunking::ChunkPartitionConfig::default()
    }
}

#[cfg(test)]
mod tests;
