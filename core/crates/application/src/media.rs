use std::collections::{HashMap, HashSet};

use crate::{
    AppServices, ApplicationError, CoachDashboardRepository, ContentPackageImportRepository,
    CorpusIndexRepository, DifficultyRepository, LLTimelineImportRepository,
    LLTimelineResourceRepository, LearnerProfileUseCases, LearningEventKind,
    LearningEventRepository, LearningEventSubjectKind, LexicalEntryRepository,
    LexicalLearningUseCases, MediaAvailability, MediaId, MediaItem, MediaLibraryEntry,
    MediaRepository, MediaTriageIntent, PhoneTimelineRepository, PlaybackProgressRepository,
    PronunciationProvider, PronunciationRepository, PronunciationUseCases,
    ProsodyAnalysisRepository, RegisterMedia, SenseGroupRepository, SubtitleTrack, SubtitleTrackId,
    SubtitleTrackRepository, SubtitleTrackStatus, TimeMs, WordTimelineRepository, now_ms,
    require_text,
};
use std::sync::Arc;

/// Owns media registration, subtitle/timeline resources, corpus projection,
/// and derived analysis. These operations share invalidation and provenance
/// rules; lexical learning remains an explicit collaborating module.
#[derive(Clone)]
pub struct MediaAnalysisUseCases {
    pub(crate) media: Arc<dyn MediaRepository>,
    pub(crate) progress: Arc<dyn PlaybackProgressRepository>,
    pub(crate) subtitle_tracks: Arc<dyn SubtitleTrackRepository>,
    pub(crate) pronunciations: Arc<dyn PronunciationRepository>,
    pub(crate) word_timelines: Arc<dyn WordTimelineRepository>,
    pub(crate) sense_groups: Arc<dyn SenseGroupRepository>,
    pub(crate) prosody: Arc<dyn ProsodyAnalysisRepository>,
    pub(crate) phone_timelines: Arc<dyn PhoneTimelineRepository>,
    pub(crate) lltimeline_resources: Arc<dyn LLTimelineResourceRepository>,
    pub(crate) lltimeline_imports: Arc<dyn LLTimelineImportRepository>,
    pub(crate) content_package_imports: Arc<dyn ContentPackageImportRepository>,
    pub(crate) corpus: Arc<dyn CorpusIndexRepository>,
    pub(crate) difficulty: Arc<dyn DifficultyRepository>,
    pub(crate) lexical_entries: Arc<dyn LexicalEntryRepository>,
    pub(crate) learning_events: Arc<dyn LearningEventRepository>,
    pub(crate) coach_dashboard: Arc<dyn CoachDashboardRepository>,
    pub(crate) pronunciation_providers: Arc<Vec<Arc<dyn PronunciationProvider>>>,
    lexical_learning: LexicalLearningUseCases,
    learner_profile: LearnerProfileUseCases,
}

impl MediaAnalysisUseCases {
    pub(crate) fn from_services(services: &AppServices) -> Self {
        Self {
            media: services.media.clone(),
            progress: services.progress.clone(),
            subtitle_tracks: services.subtitle_tracks.clone(),
            pronunciations: services.pronunciations.clone(),
            word_timelines: services.word_timelines.clone(),
            sense_groups: services.sense_groups.clone(),
            prosody: services.prosody.clone(),
            phone_timelines: services.phone_timelines.clone(),
            lltimeline_resources: services.lltimeline_resources.clone(),
            lltimeline_imports: services.lltimeline_imports.clone(),
            content_package_imports: services.content_package_imports.clone(),
            corpus: services.corpus.clone(),
            difficulty: services.difficulty.clone(),
            lexical_entries: services.lexical_entries.clone(),
            learning_events: services.learning_events.clone(),
            coach_dashboard: services.coach_dashboard.clone(),
            pronunciation_providers: services.pronunciation_providers.clone(),
            lexical_learning: LexicalLearningUseCases::from_services(services),
            learner_profile: LearnerProfileUseCases::new(services.learner_profiles.clone()),
        }
    }

    pub(crate) fn lexical_learning(&self) -> &LexicalLearningUseCases {
        &self.lexical_learning
    }

    pub(crate) fn learner_profile(&self) -> &LearnerProfileUseCases {
        &self.learner_profile
    }

    pub(crate) fn pronunciation(&self) -> PronunciationUseCases {
        PronunciationUseCases::new(
            self.pronunciations.clone(),
            self.subtitle_tracks.clone(),
            self.word_timelines.clone(),
            self.pronunciation_providers.clone(),
        )
    }
}

impl MediaAnalysisUseCases {
    pub fn register_media(&self, input: RegisterMedia) -> Result<MediaItem, ApplicationError> {
        require_text(&input.path, "path")?;
        require_text(&input.fingerprint, "fingerprint")?;
        let now = now_ms();
        let id = MediaId::from_fingerprint("media", &input.fingerprint);
        let created_at_ms = self.media.get(&id)?.map_or(now, |m| m.created_at_ms);
        self.media.upsert(&MediaItem {
            id,
            path: input.path,
            fingerprint: input.fingerprint,
            title: input.title,
            kind: input.kind,
            duration: input.duration_ms.map(TimeMs::new),
            availability: MediaAvailability::Available,
            created_at_ms,
            updated_at_ms: now,
        })
    }

    pub fn read_media(&self, media_id: &MediaId) -> Result<Option<MediaItem>, ApplicationError> {
        self.media.get(media_id)
    }

    /// Media library read model for triage (Phase 3.5 Slice 5): every
    /// registered media with the cached content fit of its primary language
    /// track, the user's explicit triage intent, and the familiar-material
    /// mark. Per-media fit failures degrade to `None` instead of failing the
    /// list — triage only suggests, it never gates (P3/P5 red lines).
    pub fn list_media_library(&self) -> Result<Vec<MediaLibraryEntry>, ApplicationError> {
        let intents: HashMap<MediaId, MediaTriageIntent> =
            self.media.list_triage_intents()?.into_iter().collect();
        let familiar: HashSet<String> = self
            .learning_events
            .list_event_subject_ids(
                LearningEventKind::FamiliarMaterialMarked,
                LearningEventSubjectKind::Media,
            )
            // A services instance without the learning loop configured still
            // serves the library; the familiar supply channel just idles.
            .unwrap_or_default()
            .into_iter()
            .collect();
        self.media
            .list()?
            .into_iter()
            .map(|media| {
                let intent = intents.get(&media.id).copied();
                let familiar_material = familiar.contains(media.id.as_str());
                self.media_library_entry(media, intent, familiar_material)
            })
            .collect()
    }

    /// Stores (or clears, with `None`) the user's explicit triage intent and
    /// returns the refreshed library entry.
    pub fn set_media_triage_intent(
        &self,
        media_id: &MediaId,
        intent: Option<MediaTriageIntent>,
    ) -> Result<MediaLibraryEntry, ApplicationError> {
        let media = self
            .media
            .get(media_id)?
            .ok_or(ApplicationError::NotFound("media"))?;
        self.media.set_triage_intent(media_id, intent, now_ms())?;
        let familiar_material = self
            .learning_events
            .list_event_subject_ids(
                LearningEventKind::FamiliarMaterialMarked,
                LearningEventSubjectKind::Media,
            )
            .unwrap_or_default()
            .iter()
            .any(|id| id == media_id.as_str());
        self.media_library_entry(media, intent, familiar_material)
    }

    fn media_library_entry(
        &self,
        media: MediaItem,
        triage_intent: Option<MediaTriageIntent>,
        familiar_material: bool,
    ) -> Result<MediaLibraryEntry, ApplicationError> {
        // First available track with a language: deterministic and matches
        // the track the workbench would load as primary. Fit stays media
        // level; the track only identifies the transcript (ADR 0018).
        let primary_track = self
            .subtitle_tracks
            .list_tracks_for_media(&media.id)?
            .into_iter()
            .find(|track| {
                track.status == SubtitleTrackStatus::Available && track.language.is_some()
            });
        let primary_track_id = primary_track.as_ref().map(|track| track.id.clone());
        // Cached read path; recomputes only on fingerprint mismatch. Any
        // failure (no word tokens, degraded resources) silently drops the
        // badge rather than the row.
        let fit = primary_track_id
            .as_ref()
            .and_then(|track_id| self.content_fit_for_track(track_id).ok());
        Ok(MediaLibraryEntry {
            media,
            primary_track_id,
            fit,
            triage_intent,
            familiar_material,
        })
    }

    pub fn subtitle_tracks_for_media(
        &self,
        media_id: &MediaId,
    ) -> Result<Vec<SubtitleTrack>, ApplicationError> {
        if self.media.get(media_id)?.is_none() {
            return Err(ApplicationError::NotFound("media item"));
        }
        self.subtitle_tracks.list_tracks_for_media(media_id)
    }

    pub fn archive_subtitle_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<SubtitleTrack, ApplicationError> {
        self.subtitle_tracks
            .set_track_status(track_id, SubtitleTrackStatus::Archived)
    }

    pub fn restore_subtitle_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<SubtitleTrack, ApplicationError> {
        self.subtitle_tracks
            .set_track_status(track_id, SubtitleTrackStatus::Available)
    }

    pub fn delete_subtitle_track(
        &self,
        track_id: &SubtitleTrackId,
    ) -> Result<Option<SubtitleTrack>, ApplicationError> {
        self.subtitle_tracks.delete_track(track_id)
    }

    pub fn read_progress(&self, media_id: &MediaId) -> Result<Option<TimeMs>, ApplicationError> {
        self.progress.load(media_id)
    }

    pub fn update_progress(
        &self,
        media_id: &MediaId,
        position_ms: u64,
    ) -> Result<TimeMs, ApplicationError> {
        if self.media.get(media_id)?.is_none() {
            return Err(ApplicationError::NotFound("media"));
        }
        let position = TimeMs::new(position_ms);
        self.progress.save(media_id, position)?;
        Ok(position)
    }
}
