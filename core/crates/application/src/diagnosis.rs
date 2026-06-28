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
        let entries =
            self.read_lexical_entries_by_forms(language.as_str(), LexicalEntryKind::Word, &lemmas)?;
        let observations = self
            .learning_assets
            .list_lexical_observations_by_sentence(sentence_id)?;
        let mut diagnosis = diagnosis_core::diagnose(&sentence, &entries, &observations);
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
