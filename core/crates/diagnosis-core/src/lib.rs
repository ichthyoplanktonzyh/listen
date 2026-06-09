use std::collections::{HashMap, HashSet};

use domain::{
    DiagnosisHint, DiagnosisKind, ObservationResult, SentenceDiagnosis, SubtitleSentence,
    SubtitleTokenKind, WordObservation, WordProfile, WordStatus,
};

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
        });
    }
    if !recognition.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::RecognitionBarrier,
            message: "Some known words may not yet be recognized reliably in speech.".into(),
            word_profile_ids: recognition,
        });
    }
    if !unclassified.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::InsufficientInformation,
            message: "Classify the remaining words before drawing a firm conclusion.".into(),
            word_profile_ids: vec![],
        });
    } else if hints.is_empty() && !lemmas.is_empty() {
        hints.push(DiagnosisHint {
            kind: DiagnosisKind::OtherFactors,
            message: "Vocabulary does not explain the difficulty; consider grammar, speed, context, or attention.".into(),
            word_profile_ids: vec![],
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
        }
    }

    #[test]
    fn distinguishes_barriers_and_information_gaps() {
        let result = diagnose(
            &sentence(),
            &[profile("alpha", WordStatus::UnknownMeaning)],
            &[],
        );
        assert_eq!(result.hints[0].kind, DiagnosisKind::MeaningBarrier);
        assert_eq!(result.hints[1].kind, DiagnosisKind::InsufficientInformation);
    }

    #[test]
    fn suggests_other_factors_when_words_do_not_explain_difficulty() {
        let result = diagnose(
            &sentence(),
            &[
                profile("alpha", WordStatus::KnownRecognized),
                profile("beta", WordStatus::KnownRecognized),
            ],
            &[],
        );
        assert_eq!(result.hints[0].kind, DiagnosisKind::OtherFactors);
    }
}
