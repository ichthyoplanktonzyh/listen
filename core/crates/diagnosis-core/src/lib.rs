use std::collections::{HashMap, HashSet};

use domain::{
    DiagnosisHint, DiagnosisKind, ObservationResult, SentenceDiagnosis, SubtitleSentence,
    SubtitleTokenKind, WordObservation, WordProfile, WordStatus,
};

/// Diagnose why a sentence may be hard to understand from the learner's
/// vocabulary state. The hint kinds (meaning vs recognition barrier) sit on the
/// comprehension axis and are language-agnostic. Per-language listening *reasons*
/// are layered on by the caller (see `AppServices::diagnose_sentence`), keeping
/// this core free of language-specific knowledge.
pub fn diagnose(
    sentence: &SubtitleSentence,
    profiles: &[WordProfile],
    observations: &[WordObservation],
) -> SentenceDiagnosis {
    let by_lemma = profiles
        .iter()
        .map(|profile| (profile.normalized_lemma.as_str(), profile))
        .collect::<HashMap<_, _>>();
    let not_recognized = observations
        .iter()
        .filter(|observation| observation.result == ObservationResult::NotRecognizedInContext)
        .map(|observation| &observation.word_profile_id)
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
        match by_lemma
            .get(lemma)
            .and_then(|profile| profile.status.map(|s| (profile, s)))
        {
            Some((profile, WordStatus::UnknownMeaning)) => meaning.push(profile.id.clone()),
            Some((profile, WordStatus::KnownNotRecognized)) => recognition.push(profile.id.clone()),
            Some((profile, WordStatus::KnownRecognized))
                if not_recognized.contains(&profile.id) =>
            {
                recognition.push(profile.id.clone());
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
            word_profile_ids: meaning,
            reasons: Vec::new(),
        });
    }
    if !recognition.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::RecognitionBarrier,
            message: "Some known words may not yet be recognized reliably in speech.".into(),
            word_profile_ids: recognition,
            // Language reasons are layered on by the caller; empty here.
            reasons: Vec::new(),
        });
    }
    if !unclassified.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::InsufficientInformation,
            message: "Classify the remaining words before drawing a firm conclusion.".into(),
            word_profile_ids: vec![],
            reasons: Vec::new(),
        });
    } else if hints.is_empty() && !lemmas.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::OtherFactors,
            message: "Vocabulary does not explain the difficulty; consider grammar, speed, context, or attention.".into(),
            word_profile_ids: vec![],
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

    fn profile(word: &str, status: WordStatus) -> WordProfile {
        WordProfile {
            id: WordProfileId::parse(word).unwrap(),
            language: LanguageCode::parse("en").unwrap(),
            lemma: word.into(),
            normalized_lemma: word.into(),
            display_form: word.into(),
            status: Some(status),
            updated_at_ms: 0,
            user_definition: None,
            personal_note: None,
            learning_updated_at_ms: 0,
        }
    }

    fn profile_without_status(word: &str) -> WordProfile {
        WordProfile {
            id: WordProfileId::parse(word).unwrap(),
            language: LanguageCode::parse("en").unwrap(),
            lemma: word.into(),
            normalized_lemma: word.into(),
            display_form: word.into(),
            status: None,
            updated_at_ms: 0,
            user_definition: None,
            personal_note: None,
            learning_updated_at_ms: 0,
        }
    }

    fn observation(word: &str, result: ObservationResult) -> WordObservation {
        WordObservation {
            id: WordObservationId::parse(format!("obs-{word}")).unwrap(),
            word_profile_id: WordProfileId::parse(word).unwrap(),
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

    // ── MeaningBarrier ──────────────────────────────────────────────

    #[test]
    fn unknown_meaning_triggers_meaning_barrier() {
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::UnknownMeaning)],
            &[],
        );
        assert_eq!(result.hints[0].kind, DiagnosisKind::MeaningBarrier);
        assert_eq!(result.hints[0].word_profile_ids.len(), 1);
        assert!(
            result.hints[0]
                .word_profile_ids
                .contains(&WordProfileId::parse("alpha").unwrap())
        );
    }

    #[test]
    fn multiple_unknown_meanings_grouped_in_one_hint() {
        let result = diagnose(
            &sentence(),
            &[
                profile("alpha", WordStatus::UnknownMeaning),
                profile("beta", WordStatus::UnknownMeaning),
            ],
            &[],
        );
        let meaning_hint = result
            .hints
            .iter()
            .find(|h| h.kind == DiagnosisKind::MeaningBarrier)
            .unwrap();
        assert_eq!(meaning_hint.word_profile_ids.len(), 2);
    }

    // ── RecognitionBarrier ──────────────────────────────────────────

    #[test]
    fn known_not_recognized_triggers_recognition_barrier() {
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::KnownNotRecognized)],
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
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::KnownRecognized)],
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
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::KnownRecognized)],
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
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::UnknownMeaning)],
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
        let result = diagnose(&sentence(), &[], &[]);
        assert_eq!(result.hints[0].kind, DiagnosisKind::InsufficientInformation);
        assert_eq!(result.unclassified_lemmas.len(), 2);
    }

    #[test]
    fn profile_without_status_treated_as_unclassified() {
        let result = diagnose(&sentence(), &[profile_without_status("alpha")], &[]);
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
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::KnownRecognized)],
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
        let result = diagnose(
            &sentence(),
            &[
                profile("alpha", WordStatus::KnownRecognized),
                profile("beta", WordStatus::KnownRecognized),
            ],
            &[],
        );
        assert_eq!(result.hints[0].kind, DiagnosisKind::OtherFactors);
        assert_eq!(result.unclassified_lemmas.len(), 0);
    }

    // ── Mixed scenarios ─────────────────────────────────────────────

    #[test]
    fn mixed_meaning_and_recognition_barriers() {
        let result = diagnose(
            &sentence(),
            &[
                profile("alpha", WordStatus::UnknownMeaning),
                profile("beta", WordStatus::KnownNotRecognized),
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
        let result = diagnose(
            &sent,
            &[
                profile("hello", WordStatus::KnownRecognized),
                profile("world", WordStatus::KnownRecognized),
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
        let result = diagnose(&sent, &[], &[]);
        // No word tokens → no lemmas → no hints, no unclassified
        assert!(result.hints.is_empty());
        assert!(result.unclassified_lemmas.is_empty());
    }

    // ── Edge cases ──────────────────────────────────────────────────

    #[test]
    fn no_profiles_no_observations_all_unclassified() {
        let result = diagnose(&sentence(), &[], &[]);
        assert_eq!(result.unclassified_lemmas.len(), 2);
        assert_eq!(result.hints[0].kind, DiagnosisKind::InsufficientInformation);
        assert!(result.hints[0].word_profile_ids.is_empty());
    }

    #[test]
    fn sentence_id_is_preserved_in_diagnosis() {
        let result = diagnose(&sentence(), &[], &[]);
        assert_eq!(
            result.sentence_id,
            SubtitleSentenceId::parse("sentence").unwrap()
        );
    }

    #[test]
    fn unknown_meaning_plus_unclassified_produces_both_hints() {
        // One word known-but-unknown-meaning, one word completely unclassified
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::UnknownMeaning)],
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
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::KnownRecognized)],
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
        let result = diagnose(&sent, &[profile("the", WordStatus::UnknownMeaning)], &[]);
        // Only one MeaningBarrier hint, even though "the" appears twice
        let meaning_count = result
            .hints
            .iter()
            .filter(|h| h.kind == DiagnosisKind::MeaningBarrier)
            .count();
        assert_eq!(meaning_count, 1);
        // The word_profile_ids should contain the profile id once
        let meaning_hint = result
            .hints
            .iter()
            .find(|h| h.kind == DiagnosisKind::MeaningBarrier)
            .unwrap();
        assert_eq!(meaning_hint.word_profile_ids.len(), 1);
    }
}
