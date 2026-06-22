use domain::*;

use crate::{ApplicationError, LexicalSourceContext, SourceContext};

pub trait MediaRepository: Send + Sync {
    fn upsert(&self, media: &MediaItem) -> Result<MediaItem, ApplicationError>;
    fn get(&self, id: &MediaId) -> Result<Option<MediaItem>, ApplicationError>;
    fn set_availability(
        &self,
        id: &MediaId,
        availability: MediaAvailability,
    ) -> Result<MediaItem, ApplicationError>;
}

pub trait SubtitleRepository: Send + Sync {
    fn save_track(&self, track: &SubtitleTrack) -> Result<(), ApplicationError>;
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
    /// Learning language of the track a sentence belongs to, used to resolve the
    /// language for diagnosis and phrase detection instead of assuming English.
    /// `None` when the sentence is unknown or its track declares no language.
    fn sentence_track_language(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<LanguageCode>, ApplicationError>;
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
    fn archive_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError>;
    fn delete_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError>;
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
    fn archive_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError>;
    fn delete_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError>;
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

pub trait WordProfileRepository: Send + Sync {
    fn upsert(&self, profile: &WordProfile) -> Result<WordProfile, ApplicationError>;
    fn get_by_key(
        &self,
        language: &LanguageCode,
        normalized_lemma: &str,
    ) -> Result<Option<WordProfile>, ApplicationError>;
    fn get_many(
        &self,
        language: &LanguageCode,
        normalized_lemmas: &[String],
    ) -> Result<Vec<WordProfile>, ApplicationError>;
}

pub trait WordObservationRepository: Send + Sync {
    fn create(&self, observation: &WordObservation) -> Result<WordObservation, ApplicationError>;
    fn list_by_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordObservation>, ApplicationError>;
    fn clear(
        &self,
        word_profile_id: &WordProfileId,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError>;
}

pub trait VocabularyAssetRepository: Send + Sync {
    fn apply_status(
        &self,
        profile: &WordProfile,
        source: Option<&SourceContext>,
        change_source: WordChangeSource,
    ) -> Result<WordDetails, ApplicationError>;
    fn capture_occurrence(
        &self,
        profile: &WordProfile,
        source: &SourceContext,
    ) -> Result<WordOccurrence, ApplicationError>;
    fn list_vocabulary(
        &self,
        language: &LanguageCode,
        status: WordStatus,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<WordDetails>, ApplicationError>;
    fn details(&self, id: &WordProfileId) -> Result<Option<WordDetails>, ApplicationError>;
    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError>;
    fn import_assets(&self, bundle: &VocabularyAssetBundle) -> Result<(), ApplicationError>;
    fn update_learning_content(
        &self,
        id: &WordProfileId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<WordDetails, ApplicationError>;
    fn import_external(
        &self,
        input: &ExternalVocabularyImport,
        imported_at_ms: u64,
    ) -> Result<ExternalVocabularyImportSummary, ApplicationError>;
}

pub trait LexicalEntryRepository: Send + Sync {
    fn upsert_lexical_entry(
        &self,
        entry: &LexicalEntry,
        source: Option<&LexicalSourceContext>,
        change_source: WordChangeSource,
    ) -> Result<LexicalEntryDetails, ApplicationError>;
    fn lexical_details(
        &self,
        id: &LexicalEntryId,
    ) -> Result<Option<LexicalEntryDetails>, ApplicationError>;
    fn list_lexical_entries(
        &self,
        language: &LanguageCode,
        kind: Option<LexicalEntryKind>,
        status: Option<WordStatus>,
        search: &str,
        limit: u32,
        offset: u32,
    ) -> Result<Vec<LexicalEntryDetails>, ApplicationError>;
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
    fn create_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError>;
    fn update_job(&self, job: &TranscriptionJob) -> Result<TranscriptionJob, ApplicationError>;
    fn get_job(
        &self,
        id: &TranscriptionJobId,
    ) -> Result<Option<TranscriptionJob>, ApplicationError>;
    fn list_jobs(&self) -> Result<Vec<TranscriptionJob>, ApplicationError>;
    fn find_completed_job(
        &self,
        input_fingerprint: &str,
    ) -> Result<Option<TranscriptionJob>, ApplicationError>;
    fn interrupt_active_jobs(&self, updated_at_ms: u64) -> Result<(), ApplicationError>;
    fn save_provenance(&self, provenance: &SubtitleTrackProvenance)
    -> Result<(), ApplicationError>;
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
