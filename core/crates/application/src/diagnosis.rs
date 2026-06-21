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
        let profiles = self.read_word_profiles("en", &lemmas)?;
        let observations = self.observations.list_by_sentence(sentence_id)?;
        Ok(diagnosis_core::diagnose(
            &sentence,
            &profiles,
            &observations,
        ))
    }
}
