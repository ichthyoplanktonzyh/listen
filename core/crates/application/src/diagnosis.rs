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
        // Token normalization is surface-level; entry keys come from the
        // language's normalization provider (lemmatization, user overrides).
        // Resolve each token to its authoritative key once, and hand the same
        // mapping to diagnosis-core so inflected forms ("went") classify
        // against their lemma entry ("go") instead of falling out as
        // unclassified.
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
        let observations = self
            .learning_assets
            .list_lexical_observations_by_sentence(sentence_id)?;
        let mut diagnosis = diagnosis_core::diagnose_with_phrases(
            &sentence,
            &entries,
            &phrase_entries,
            &observations,
            &lexical_keys,
        );
        // Layer the learning language's listening-factor reasons onto the
        // recognition barrier (per-profile possibilities, not audio detections).
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
