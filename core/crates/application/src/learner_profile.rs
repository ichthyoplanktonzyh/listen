use serde::{Deserialize, Serialize};

use crate::*;

/// The single local learner row. The app is single-user; a fixed id keeps the
/// profile a durable singleton without inventing account identity.
const LOCAL_LEARNER_ID: &str = "local-learner";

/// One profile read model (Phase 3.9): the three language axes stay separate —
/// UI language is owned by client settings (snapshotted here for the coach
/// dashboard), learning language is per-track (Phase 2.11), and L1 is the only
/// axis this profile owns durably. Consumers (diagnosis layer, 3.10) read this
/// view instead of poking three different stores.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct LearnerProfileView {
    /// The learner's native language, if declared. `None` means the learner
    /// never set it; every L1-aware surface must degrade to baseline then.
    pub l1_language: Option<LanguageCode>,
    /// Client-reported UI language snapshot. Authority stays in client
    /// settings; this is display/statistics context only.
    pub ui_language: Option<LanguageCode>,
    /// Reserved: the learning language is currently derived per subtitle
    /// track, so this stays `None` until a product decision pins an active L2.
    pub active_l2_language: Option<LanguageCode>,
    pub updated_at_ms: Option<u64>,
}

impl AppServices {
    fn local_learner_id() -> LearnerProfileId {
        LearnerProfileId::parse(LOCAL_LEARNER_ID).expect("static learner id is valid")
    }

    pub fn learner_profile_view(&self) -> Result<LearnerProfileView, ApplicationError> {
        let profile = self
            .learner_profiles
            .get_learner_profile(&Self::local_learner_id())?;
        Ok(match profile {
            Some(profile) => LearnerProfileView {
                l1_language: profile.l1_language,
                ui_language: Some(profile.ui_language),
                active_l2_language: profile.active_l2_language,
                updated_at_ms: Some(profile.updated_at_ms),
            },
            None => LearnerProfileView {
                l1_language: None,
                ui_language: None,
                active_l2_language: None,
                updated_at_ms: None,
            },
        })
    }

    /// Internal L1 read for the diagnosis layer. Missing profile or missing L1
    /// both read as `None` — never an error — so baseline diagnosis is
    /// unaffected for learners who never opened the setting.
    pub(crate) fn learner_l1(&self) -> Result<Option<LanguageCode>, ApplicationError> {
        Ok(self
            .learner_profiles
            .get_learner_profile(&Self::local_learner_id())?
            .and_then(|profile| profile.l1_language))
    }

    /// Set (or clear, with `None`) the learner's L1. `ui_language` is the
    /// client's current UI language, stored as a snapshot for 3.10; it is not
    /// authoritative and defaults to `en` when the client omits it.
    pub fn set_learner_l1(
        &self,
        l1_language: Option<&str>,
        ui_language: Option<&str>,
    ) -> Result<LearnerProfileView, ApplicationError> {
        let l1_language = l1_language
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(LanguageCode::parse)
            .transpose()?;
        let ui_language = ui_language
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(LanguageCode::parse)
            .transpose()?;
        let id = Self::local_learner_id();
        let existing = self.learner_profiles.get_learner_profile(&id)?;
        let now = now_ms();
        let profile = LearnerProfile {
            id,
            ui_language: ui_language
                .or_else(|| existing.as_ref().map(|profile| profile.ui_language.clone()))
                .unwrap_or_else(|| LanguageCode::parse("en").expect("static code is valid")),
            l1_language,
            active_l2_language: existing
                .as_ref()
                .and_then(|profile| profile.active_l2_language.clone()),
            created_at_ms: existing
                .as_ref()
                .map(|profile| profile.created_at_ms)
                .unwrap_or(now),
            updated_at_ms: now,
        };
        let saved = self.learner_profiles.save_learner_profile(&profile)?;
        Ok(LearnerProfileView {
            l1_language: saved.l1_language,
            ui_language: Some(saved.ui_language),
            active_l2_language: saved.active_l2_language,
            updated_at_ms: Some(saved.updated_at_ms),
        })
    }
}
