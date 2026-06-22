use crate::*;

impl AppServices {
    pub fn diagnose_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentenceDiagnosis, ApplicationError> {
        let sentence = self
            .subtitles
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let lemmas = sentence
            .tokens
            .iter()
            .filter_map(|token| token.normalized.clone())
            .collect::<Vec<_>>();
        let language = self.sentence_language(sentence_id)?;
        let profiles = self.read_word_profiles(language.as_str(), &lemmas)?;
        let observations = self.observations.list_by_sentence(sentence_id)?;
        let mut diagnosis = diagnosis_core::diagnose(&sentence, &profiles, &observations);
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
