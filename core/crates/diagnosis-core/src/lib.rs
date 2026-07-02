use std::collections::{HashMap, HashSet};

use domain::{
    DiagnosisHint, DiagnosisKind, LearningStatus, LexicalEntry, LexicalObservation,
    ObservationResult, SentenceDiagnosis, SubtitleSentence, SubtitleTokenKind,
};

/// Diagnose why a sentence may be hard to understand from the learner's
/// vocabulary state. The hint kinds (meaning vs recognition barrier) sit on the
/// comprehension axis and are language-agnostic. Per-language listening *reasons*
/// are layered on by the caller (see `AppServices::diagnose_sentence`), keeping
/// this core free of language-specific knowledge.
///
/// `lexical_keys` maps a token's `normalized` form to the authoritative lexical
/// entry key (provider lemmatization, user overrides). Token normalization is
/// surface-level lowercasing, while `LexicalEntry.normalized_form` comes from
/// the language's normalization provider — the two only coincide for
/// uninflected words, so the caller must supply the mapping ("went" -> "go").
/// Tokens missing from the map fall back to their own normalized form.
pub fn diagnose(
    sentence: &SubtitleSentence,
    entries: &[LexicalEntry],
    observations: &[LexicalObservation],
    lexical_keys: &HashMap<String, String>,
) -> SentenceDiagnosis {
    let by_key = entries
        .iter()
        .map(|entry| (entry.normalized_form.as_str(), entry))
        .collect::<HashMap<_, _>>();
    let not_recognized = observations
        .iter()
        .filter(|observation| observation.result == ObservationResult::NotRecognizedInContext)
        .map(|observation| &observation.lexical_entry_id)
        .collect::<HashSet<_>>();
    let lemmas = sentence
        .tokens
        .iter()
        .filter(|token| token.kind == SubtitleTokenKind::Word)
        .filter_map(|token| token.normalized.as_deref())
        .collect::<HashSet<_>>();
    let mut meaning = Vec::new();
    let mut recognition = Vec::new();
    let mut unclassified = Vec::new();
    for lemma in &lemmas {
        let key = lexical_keys
            .get(*lemma)
            .map(String::as_str)
            .unwrap_or(*lemma);
        match by_key
            .get(key)
            .and_then(|entry| entry.status.map(|s| (entry, s)))
        {
            Some((entry, LearningStatus::UnknownMeaning)) => meaning.push(entry.id.clone()),
            Some((entry, LearningStatus::KnownNotRecognized)) => recognition.push(entry.id.clone()),
            Some((entry, LearningStatus::KnownRecognized))
                if not_recognized.contains(&entry.id) =>
            {
                recognition.push(entry.id.clone());
            }
            Some(_) => {}
            None => unclassified.push((*lemma).to_owned()),
        }
    }
    let mut hints = Vec::new();
    if !meaning.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::MeaningBarrier,
            message: "Some words may block understanding because their meanings are unknown."
                .into(),
            lexical_entry_ids: meaning,
            reasons: Vec::new(),
        });
    }
    if !recognition.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::RecognitionBarrier,
            message: "Some known words may not yet be recognized reliably in speech.".into(),
            lexical_entry_ids: recognition,
            // Language reasons are layered on by the caller; empty here.
            reasons: Vec::new(),
        });
    }
    if !unclassified.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::InsufficientInformation,
            message: "Classify the remaining words before drawing a firm conclusion.".into(),
            lexical_entry_ids: vec![],
            reasons: Vec::new(),
        });
    } else if hints.is_empty() && !lemmas.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::OtherFactors,
            message: "Vocabulary does not explain the difficulty; consider grammar, speed, context, or attention.".into(),
            lexical_entry_ids: vec![],
            reasons: Vec::new(),
        });
    }
    SentenceDiagnosis {
        sentence_id: sentence.id.clone(),
        hints,
        unclassified_lemmas: unclassified,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::*;

    /// Most tests use tokens whose normalized form equals the entry key, so no
    /// provider mapping is needed; inflection-mapping tests pass a real map.
    fn diagnose_plain(
        sentence: &SubtitleSentence,
        entries: &[LexicalEntry],
        observations: &[LexicalObservation],
    ) -> SentenceDiagnosis {
        diagnose(sentence, entries, observations, &HashMap::new())
    }

    fn sentence() -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("sentence").unwrap(),
            index: 0,
            start: TimeMs::ZERO,
            end: TimeMs::new(1000),
            original_text: "alpha beta".into(),
            display_text: "alpha beta".into(),
            tokens: ["alpha", "beta"]
                .into_iter()
                .enumerate()
                .map(|(index, word)| SubtitleToken {
                    index: index as u32,
                    kind: SubtitleTokenKind::Word,
                    text: word.into(),
                    normalized: Some(word.into()),
                    start_char: 0,
                    end_char: 0,
                })
                .collect(),
        }
    }

    fn entry(word: &str, status: LearningStatus) -> LexicalEntry {
        LexicalEntry {
            id: LexicalEntryId::parse(word).unwrap(),
            unit: LexicalUnit::new(
                LanguageCode::parse("en").unwrap(),
                LexicalUnit::GRANULARITY_WORD,
                "core.lemma",
                word,
                word,
            ),
            language: LanguageCode::parse("en").unwrap(),
            kind: LexicalEntryKind::Word,
            canonical_form: word.into(),
            normalized_form: word.into(),
            display_form: word.into(),
            status: Some(status),
            user_definition: None,
            personal_note: None,
            normalization_provider: "test".into(),
            normalization_version: "v1".into(),
            user_corrected: false,
            updated_at_ms: 0,
            learning_updated_at_ms: 0,
        }
    }

    fn entry_without_status(word: &str) -> LexicalEntry {
        LexicalEntry {
            id: LexicalEntryId::parse(word).unwrap(),
            unit: LexicalUnit::new(
                LanguageCode::parse("en").unwrap(),
                LexicalUnit::GRANULARITY_WORD,
                "core.lemma",
                word,
                word,
            ),
            language: LanguageCode::parse("en").unwrap(),
            kind: LexicalEntryKind::Word,
            canonical_form: word.into(),
            normalized_form: word.into(),
            display_form: word.into(),
            status: None,
            user_definition: None,
            personal_note: None,
            normalization_provider: "test".into(),
            normalization_version: "v1".into(),
            user_corrected: false,
            updated_at_ms: 0,
            learning_updated_at_ms: 0,
        }
    }

    fn observation(word: &str, result: ObservationResult) -> LexicalObservation {
        LexicalObservation {
            id: LexicalObservationId::parse(format!("obs-{word}")).unwrap(),
            lexical_entry_id: LexicalEntryId::parse(word).unwrap(),
            sentence_id: SubtitleSentenceId::parse("sentence").unwrap(),
            original_form: word.into(),
            result,
            created_at_ms: 0,
        }
    }

    fn sentence_with_tokens(tokens: &[(&str, SubtitleTokenKind)]) -> SubtitleSentence {
        SubtitleSentence {
            id: SubtitleSentenceId::parse("sentence").unwrap(),
            index: 0,
            start: TimeMs::ZERO,
            end: TimeMs::new(1000),
            original_text: tokens.iter().map(|(t, _)| *t).collect::<Vec<_>>().join(" "),
            display_text: tokens.iter().map(|(t, _)| *t).collect::<Vec<_>>().join(" "),
            tokens: tokens
                .iter()
                .enumerate()
                .map(|(index, (word, kind))| SubtitleToken {
                    index: index as u32,
                    kind: *kind,
                    text: (*word).into(),
                    normalized: if *kind == SubtitleTokenKind::Word {
                        Some((*word).into())
                    } else {
                        None
                    },
                    start_char: 0,
                    end_char: 0,
                })
                .collect(),
        }
    }

    // ── Lexical key mapping (provider lemmatization) ────────────────

    #[test]
    fn inflected_token_resolves_through_lexical_key_map() {
        // Token "went" (surface-normalized) must classify against the "go"
        // entry when the caller supplies the provider lemma mapping.
        let sent = sentence_with_tokens(&[("went", SubtitleTokenKind::Word)]);
        let entries = [entry("go", LearningStatus::KnownNotRecognized)];
        let keys = HashMap::from([("went".to_owned(), "go".to_owned())]);
        let result = diagnose(&sent, &entries, &[], &keys);
        assert!(result.unclassified_lemmas.is_empty());
        assert_eq!(result.hints.len(), 1);
        assert_eq!(result.hints[0].kind, DiagnosisKind::RecognitionBarrier);
        assert_eq!(result.hints[0].lexical_entry_ids, vec![entries[0].id.clone()]);
    }

    #[test]
    fn inflected_token_without_key_map_stays_unclassified_by_surface_form() {
        // Without the mapping the token cannot be classified; it must surface
        // as its own normalized form so the UI shows the word the user heard.
        let sent = sentence_with_tokens(&[("went", SubtitleTokenKind::Word)]);
        let entries = [entry("go", LearningStatus::KnownNotRecognized)];
        let result = diagnose_plain(&sent, &entries, &[]);
        assert_eq!(result.unclassified_lemmas, vec!["went".to_owned()]);
    }

    // ── MeaningBarrier ──────────────────────────────────────────────

    #[test]
    fn unknown_meaning_triggers_meaning_barrier() {
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::UnknownMeaning)],
            &[],
        );
        assert_eq!(result.hints[0].kind, DiagnosisKind::MeaningBarrier);
        assert_eq!(result.hints[0].lexical_entry_ids.len(), 1);
        assert!(
            result.hints[0]
                .lexical_entry_ids
                .contains(&LexicalEntryId::parse("alpha").unwrap())
        );
    }

    #[test]
    fn multiple_unknown_meanings_grouped_in_one_hint() {
        let result = diagnose_plain(
            &sentence(),
            &[
                entry("alpha", LearningStatus::UnknownMeaning),
                entry("beta", LearningStatus::UnknownMeaning),
            ],
            &[],
        );
        let meaning_hint = result
            .hints
            .iter()
            .find(|h| h.kind == DiagnosisKind::MeaningBarrier)
            .unwrap();
        assert_eq!(meaning_hint.lexical_entry_ids.len(), 2);
    }

    // ── RecognitionBarrier ──────────────────────────────────────────

    #[test]
    fn known_not_recognized_triggers_recognition_barrier() {
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::KnownNotRecognized)],
            &[],
        );
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::RecognitionBarrier)
        );
    }

    #[test]
    fn known_recognized_but_not_in_context_triggers_recognition_barrier() {
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::KnownRecognized)],
            &[observation(
                "alpha",
                ObservationResult::NotRecognizedInContext,
            )],
        );
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::RecognitionBarrier)
        );
    }

    #[test]
    fn known_recognized_without_observation_no_recognition_barrier() {
        // KnownRecognized only triggers recognition barrier when the
        // observation says NotRecognizedInContext.
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::KnownRecognized)],
            &[],
        );
        assert!(
            !result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::RecognitionBarrier)
        );
    }

    #[test]
    fn observation_not_recognized_but_status_not_known_recognized_no_barrier() {
        // If the profile has UnknownMeaning, the NotRecognizedInContext
        // observation should not trigger a RecognitionBarrier — the word
        // first needs meaning.
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::UnknownMeaning)],
            &[observation(
                "alpha",
                ObservationResult::NotRecognizedInContext,
            )],
        );
        assert!(
            !result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::RecognitionBarrier)
        );
    }

    // ── InsufficientInformation ─────────────────────────────────────

    #[test]
    fn unclassified_words_trigger_insufficient_information() {
        let result = diagnose_plain(&sentence(), &[], &[]);
        assert_eq!(result.hints[0].kind, DiagnosisKind::InsufficientInformation);
        assert_eq!(result.unclassified_lemmas.len(), 2);
    }

    #[test]
    fn profile_without_status_treated_as_unclassified() {
        let result = diagnose_plain(&sentence(), &[entry_without_status("alpha")], &[]);
        // alpha has a profile but no status → treated as unclassified
        assert!(result.unclassified_lemmas.contains(&"alpha".to_owned()));
        // beta is also unclassified (no profile)
        assert!(result.unclassified_lemmas.contains(&"beta".to_owned()));
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::InsufficientInformation)
        );
    }

    #[test]
    fn partial_classification_shows_insufficient_information() {
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::KnownRecognized)],
            &[],
        );
        // beta is unclassified → InsufficientInformation
        assert_eq!(result.unclassified_lemmas, vec!["beta"]);
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::InsufficientInformation)
        );
    }

    // ── OtherFactors ────────────────────────────────────────────────

    #[test]
    fn all_words_classified_without_barriers_suggests_other_factors() {
        let result = diagnose_plain(
            &sentence(),
            &[
                entry("alpha", LearningStatus::KnownRecognized),
                entry("beta", LearningStatus::KnownRecognized),
            ],
            &[],
        );
        assert_eq!(result.hints[0].kind, DiagnosisKind::OtherFactors);
        assert_eq!(result.unclassified_lemmas.len(), 0);
    }

    // ── Mixed scenarios ─────────────────────────────────────────────

    #[test]
    fn mixed_meaning_and_recognition_barriers() {
        let result = diagnose_plain(
            &sentence(),
            &[
                entry("alpha", LearningStatus::UnknownMeaning),
                entry("beta", LearningStatus::KnownNotRecognized),
            ],
            &[],
        );
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::MeaningBarrier)
        );
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::RecognitionBarrier)
        );
    }

    // ── Non-word token filtering ────────────────────────────────────

    #[test]
    fn non_word_tokens_are_ignored() {
        let sent = sentence_with_tokens(&[
            ("hello", SubtitleTokenKind::Word),
            (",", SubtitleTokenKind::Punctuation),
            ("world", SubtitleTokenKind::Word),
        ]);
        let result = diagnose_plain(
            &sent,
            &[
                entry("hello", LearningStatus::KnownRecognized),
                entry("world", LearningStatus::KnownRecognized),
            ],
            &[],
        );
        // Only word tokens are classified; no unclassified lemmas
        assert_eq!(result.unclassified_lemmas.len(), 0);
        assert_eq!(result.hints[0].kind, DiagnosisKind::OtherFactors);
    }

    #[test]
    fn sentence_with_only_punctuation_produces_no_hints() {
        let sent = sentence_with_tokens(&[
            (".", SubtitleTokenKind::Punctuation),
            ("!", SubtitleTokenKind::Punctuation),
        ]);
        let result = diagnose_plain(&sent, &[], &[]);
        // No word tokens → no lemmas → no hints, no unclassified
        assert!(result.hints.is_empty());
        assert!(result.unclassified_lemmas.is_empty());
    }

    // ── Edge cases ──────────────────────────────────────────────────

    #[test]
    fn no_profiles_no_observations_all_unclassified() {
        let result = diagnose_plain(&sentence(), &[], &[]);
        assert_eq!(result.unclassified_lemmas.len(), 2);
        assert_eq!(result.hints[0].kind, DiagnosisKind::InsufficientInformation);
        assert!(result.hints[0].lexical_entry_ids.is_empty());
    }

    #[test]
    fn sentence_id_is_preserved_in_diagnosis() {
        let result = diagnose_plain(&sentence(), &[], &[]);
        assert_eq!(
            result.sentence_id,
            SubtitleSentenceId::parse("sentence").unwrap()
        );
    }

    #[test]
    fn unknown_meaning_plus_unclassified_produces_both_hints() {
        // One word known-but-unknown-meaning, one word completely unclassified
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::UnknownMeaning)],
            &[],
        );
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::MeaningBarrier)
        );
        assert!(
            result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::InsufficientInformation)
        );
    }

    #[test]
    fn known_recognized_with_different_observation_not_triggered() {
        // Observation results other than NotRecognizedInContext should not
        // trigger a RecognitionBarrier.
        let result = diagnose_plain(
            &sentence(),
            &[entry("alpha", LearningStatus::KnownRecognized)],
            &[observation("alpha", ObservationResult::RecognizedInContext)],
        );
        assert!(
            !result
                .hints
                .iter()
                .any(|h| h.kind == DiagnosisKind::RecognitionBarrier)
        );
    }

    #[test]
    fn duplicate_lemmas_do_not_create_duplicate_hints() {
        // A sentence with "the the" — same lemma twice
        let sent = sentence_with_tokens(&[
            ("the", SubtitleTokenKind::Word),
            ("the", SubtitleTokenKind::Word),
        ]);
        let result = diagnose_plain(&sent, &[entry("the", LearningStatus::UnknownMeaning)], &[]);
        // Only one MeaningBarrier hint, even though "the" appears twice
        let meaning_count = result
            .hints
            .iter()
            .filter(|h| h.kind == DiagnosisKind::MeaningBarrier)
            .count();
        assert_eq!(meaning_count, 1);
        // The lexical_entry_ids should contain the profile id once
        let meaning_hint = result
            .hints
            .iter()
            .find(|h| h.kind == DiagnosisKind::MeaningBarrier)
            .unwrap();
        assert_eq!(meaning_hint.lexical_entry_ids.len(), 1);
    }
}
