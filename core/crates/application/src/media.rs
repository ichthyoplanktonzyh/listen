use std::collections::{HashMap, HashSet};

use crate::*;

impl AppServices {
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
