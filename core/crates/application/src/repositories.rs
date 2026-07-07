use domain::*;

use crate::{ApplicationError, LexicalSourceContext};

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
    fn set_track_language(
        &self,
        id: &SubtitleTrackId,
        language: &LanguageCode,
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

pub trait SubtitleTrackRepository: Send + Sync {
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
    fn set_track_language(
        &self,
        id: &SubtitleTrackId,
        language: &LanguageCode,
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
}

impl<T: SubtitleRepository + ?Sized> SubtitleTrackRepository for T {
    fn save_track(&self, track: &SubtitleTrack) -> Result<(), ApplicationError> {
        SubtitleRepository::save_track(self, track)
    }

    fn get_track(&self, id: &SubtitleTrackId) -> Result<Option<SubtitleTrack>, ApplicationError> {
        SubtitleRepository::get_track(self, id)
    }

    fn list_tracks_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Vec<SubtitleTrack>, ApplicationError> {
        SubtitleRepository::list_tracks_for_media(self, media_id)
    }

    fn set_track_status(
        &self,
        id: &SubtitleTrackId,
        status: SubtitleTrackStatus,
    ) -> Result<SubtitleTrack, ApplicationError> {
        SubtitleRepository::set_track_status(self, id, status)
    }

    fn set_track_language(
        &self,
        id: &SubtitleTrackId,
        language: &LanguageCode,
    ) -> Result<SubtitleTrack, ApplicationError> {
        SubtitleRepository::set_track_language(self, id, language)
    }

    fn delete_track(
        &self,
        id: &SubtitleTrackId,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        SubtitleRepository::delete_track(self, id)
    }

    fn get_by_media_fingerprint(
        &self,
        media_id: &MediaId,
        fingerprint: &str,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        SubtitleRepository::get_by_media_fingerprint(self, media_id, fingerprint)
    }

    fn get_sentence(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SubtitleSentence>, ApplicationError> {
        SubtitleRepository::get_sentence(self, id)
    }

    fn sentence_track_language(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<LanguageCode>, ApplicationError> {
        SubtitleRepository::sentence_track_language(self, id)
    }
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

impl<T: SubtitleRepository + ?Sized> PronunciationRepository for T {
    fn save_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        pronunciation: &WordPronunciation,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<(), ApplicationError> {
        SubtitleRepository::save_word_pronunciation(
            self,
            language,
            accent,
            pronunciation,
            provider_id,
            provider_version,
        )
    }

    fn get_word_pronunciation(
        &self,
        language: &str,
        accent: &str,
        normalized_text: &str,
        provider_id: &str,
        provider_version: &str,
    ) -> Result<Option<WordPronunciation>, ApplicationError> {
        SubtitleRepository::get_word_pronunciation(
            self,
            language,
            accent,
            normalized_text,
            provider_id,
            provider_version,
        )
    }

    fn save_pronunciation(&self, analysis: &SentencePronunciation) -> Result<(), ApplicationError> {
        SubtitleRepository::save_pronunciation(self, analysis)
    }

    fn get_pronunciation(
        &self,
        id: &SubtitleSentenceId,
    ) -> Result<Option<SentencePronunciation>, ApplicationError> {
        SubtitleRepository::get_pronunciation(self, id)
    }
}

pub trait TimelineResourceRepository: Send + Sync {
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
}

impl<T: SubtitleRepository + ?Sized> TimelineResourceRepository for T {
    fn save_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
        timings: &[WordTiming],
    ) -> Result<(), ApplicationError> {
        SubtitleRepository::save_word_timings(self, sentence_id, timings)
    }

    fn get_word_timings(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        SubtitleRepository::get_word_timings(self, sentence_id)
    }

    fn save_word_timeline(
        &self,
        timeline: &WordTimeline,
    ) -> Result<WordTimeline, ApplicationError> {
        SubtitleRepository::save_word_timeline(self, timeline)
    }

    fn list_word_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<WordTimeline>, ApplicationError> {
        SubtitleRepository::list_word_timelines(self, track_id)
    }

    fn get_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        SubtitleRepository::get_word_timeline(self, id)
    }

    fn active_word_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<WordTimeline>, ApplicationError> {
        SubtitleRepository::active_word_timeline(self, track_id)
    }

    fn activate_word_timeline(
        &self,
        id: &WordTimelineId,
    ) -> Result<WordTimeline, ApplicationError> {
        SubtitleRepository::activate_word_timeline(self, id)
    }

    fn archive_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError> {
        SubtitleRepository::archive_word_timeline(self, id)
    }

    fn delete_word_timeline(&self, id: &WordTimelineId) -> Result<WordTimeline, ApplicationError> {
        SubtitleRepository::delete_word_timeline(self, id)
    }

    fn save_chunk_timeline(
        &self,
        timeline: &ChunkTimeline,
    ) -> Result<ChunkTimeline, ApplicationError> {
        SubtitleRepository::save_chunk_timeline(self, timeline)
    }

    fn list_chunk_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<ChunkTimeline>, ApplicationError> {
        SubtitleRepository::list_chunk_timelines(self, track_id)
    }

    fn get_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError> {
        SubtitleRepository::get_chunk_timeline(self, id)
    }

    fn active_chunk_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<ChunkTimeline>, ApplicationError> {
        SubtitleRepository::active_chunk_timeline(self, track_id)
    }

    fn activate_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        SubtitleRepository::activate_chunk_timeline(self, id)
    }

    fn archive_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        SubtitleRepository::archive_chunk_timeline(self, id)
    }

    fn delete_chunk_timeline(
        &self,
        id: &ChunkTimelineId,
    ) -> Result<ChunkTimeline, ApplicationError> {
        SubtitleRepository::delete_chunk_timeline(self, id)
    }

    fn save_phone_timeline(
        &self,
        timeline: &PhoneTimeline,
    ) -> Result<PhoneTimeline, ApplicationError> {
        SubtitleRepository::save_phone_timeline(self, timeline)
    }

    fn list_phone_timelines(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Vec<PhoneTimeline>, ApplicationError> {
        SubtitleRepository::list_phone_timelines(self, track_id)
    }

    fn get_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError> {
        SubtitleRepository::get_phone_timeline(self, id)
    }

    fn active_phone_timeline(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<PhoneTimeline>, ApplicationError> {
        SubtitleRepository::active_phone_timeline(self, track_id)
    }

    fn activate_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        SubtitleRepository::activate_phone_timeline(self, id)
    }

    fn archive_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        SubtitleRepository::archive_phone_timeline(self, id)
    }

    fn delete_phone_timeline(
        &self,
        id: &PhoneTimelineId,
    ) -> Result<PhoneTimeline, ApplicationError> {
        SubtitleRepository::delete_phone_timeline(self, id)
    }
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

impl<T: SubtitleRepository + ?Sized> LLTimelineResourceRepository for T {
    fn save_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
        metadata: &LLTimelineMetadata,
        artifacts: &[LLTimelineArtifact],
    ) -> Result<(), ApplicationError> {
        SubtitleRepository::save_lltimeline_resource(self, track_id, metadata, artifacts)
    }

    fn get_lltimeline_resource(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<(LLTimelineMetadata, Vec<LLTimelineArtifact>)>, ApplicationError> {
        SubtitleRepository::get_lltimeline_resource(self, track_id)
    }
}

pub trait LearningAssetRepository: Send + Sync {
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
    fn list_lexical_entries(
        &self,
        language: &LanguageCode,
        kind: Option<LexicalEntryKind>,
        status: Option<LearningStatus>,
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
    fn update_lexical_learning_content(
        &self,
        id: &LexicalEntryId,
        user_definition: Option<String>,
        personal_note: Option<String>,
        updated_at_ms: u64,
    ) -> Result<LexicalEntryDetails, ApplicationError>;
    fn export_assets(&self) -> Result<VocabularyAssetBundle, ApplicationError>;
    fn import_assets(&self, bundle: &VocabularyAssetBundle) -> Result<(), ApplicationError>;
    fn export_all_capability_profiles(
        &self,
    ) -> Result<Vec<LexicalCapabilityProfile>, ApplicationError>;
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

pub trait ReviewRepository: Send + Sync {
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

pub trait RecordingRepository: Send + Sync {
    fn save_recording_asset(
        &self,
        asset: &RecordingAsset,
    ) -> Result<RecordingAsset, ApplicationError>;
    fn get_recording_asset(
        &self,
        id: &RecordingAssetId,
    ) -> Result<Option<RecordingAsset>, ApplicationError>;
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
