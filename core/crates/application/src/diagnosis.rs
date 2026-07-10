use crate::*;

impl AppServices {
    pub fn diagnose_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentenceDiagnosis, ApplicationError> {
        let sentence = self
            .subtitle_tracks
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let lemmas = sentence
            .tokens
            .iter()
            .filter_map(|token| token.normalized.clone())
            .collect::<Vec<_>>();
        let language = self.sentence_language(sentence_id)?;
        let mut lexical_keys = std::collections::HashMap::new();
        for lemma in &lemmas {
            if lexical_keys.contains_key(lemma) {
                continue;
            }
            let normalized = self
                .normalize_lexical_form(language.as_str(), lemma)?
                .normalized;
            lexical_keys.insert(lemma.clone(), normalized);
        }
        let keys = lexical_keys
            .values()
            .cloned()
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        let entries = self.learning_assets.lexical_entries_by_keys(
            &language,
            LexicalEntryKind::Word,
            &keys,
        )?;
        let phrase_keys = self
            .phrase_candidates(sentence_id)?
            .into_iter()
            .map(|candidate| candidate.normalized_form)
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        let phrase_entries = self.learning_assets.lexical_entries_by_keys(
            &language,
            LexicalEntryKind::Phrase,
            &phrase_keys,
        )?;
        let mut profiles = std::collections::HashMap::new();
        for entry in entries.iter().chain(phrase_entries.iter()) {
            if let Some(profile) = self
                .learning_assets
                .lexical_capability_profile(&entry.id, None)?
            {
                profiles.insert(entry.id.clone(), profile);
            }
        }
        let observations = self
            .learning_assets
            .list_lexical_observations_by_sentence(sentence_id)?;
        let mut diagnosis = diagnosis_core::diagnose_with_profiles(
            &sentence,
            &entries,
            &phrase_entries,
            &profiles,
            &observations,
            &lexical_keys,
        );
        let reasons = domain::profile_for(&language).diagnosis_reasons;
        if !reasons.is_empty() {
            for hint in &mut diagnosis.hints {
                if hint.kind == domain::DiagnosisKind::RecognitionBarrier {
                    hint.reasons = reasons.clone();
                }
            }
        }
        Ok(diagnosis)
    }
}
