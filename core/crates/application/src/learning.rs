use crate::*;

impl AppServices {
    pub fn update_word_learning_content(
        &self,
        id: &WordProfileId,
        user_definition: Option<String>,
        personal_note: Option<String>,
    ) -> Result<WordDetails, ApplicationError> {
        let details = self.vocabulary.update_learning_content(
            id,
            clean_optional(user_definition),
            clean_optional(personal_note),
            now_ms(),
        )?;
        self.lexical.upsert_lexical_entry(
            &lexical_from_word(&details.profile),
            None,
            WordChangeSource::UserSelection,
        )?;
        Ok(details)
    }

    pub fn import_external_vocabulary(
        &self,
        input: &ExternalVocabularyImport,
    ) -> Result<ExternalVocabularyImportSummary, ApplicationError> {
        LanguageCode::parse(input.language.clone())?;
        let summary = self.vocabulary.import_external(input, now_ms())?;
        for entry in &input.entries {
            if let Some(profile) = self.read_word_profile(&input.language, &entry.word)? {
                self.lexical.upsert_lexical_entry(
                    &lexical_from_word(&profile),
                    None,
                    WordChangeSource::Import,
                )?;
            }
        }
        Ok(summary)
    }
}
