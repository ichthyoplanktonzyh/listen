use domain::{SubtitleSentence, SubtitleTokenKind};

use super::{PhraseContext, RuleWord};

pub(super) fn has_punctuation_boundary(sentence: &SubtitleSentence, start: u32, end: u32) -> bool {
    sentence.tokens.iter().any(|token| {
        token.index > start && token.index < end && token.kind == SubtitleTokenKind::Punctuation
    })
}

pub(super) fn phrase_context_allows(
    context: PhraseContext,
    words: &[RuleWord],
    pair_index: usize,
    sentence: &SubtitleSentence,
) -> bool {
    match context {
        PhraseContext::Always => true,
        PhraseContext::FollowedByLikelyVerb => followed_by_likely_verb(words, pair_index, sentence),
        PhraseContext::GoingToInfinitive => {
            followed_by_likely_verb(words, pair_index, sentence)
                && !is_conservative_destination(words.get(pair_index + 2))
        }
        PhraseContext::WantToInfinitive => {
            followed_by_likely_verb(words, pair_index, sentence)
                && !starts_with_wh_extraction(words, pair_index)
        }
        PhraseContext::UsedToInfinitive => {
            followed_by_likely_verb(words, pair_index, sentence)
                && !pair_index
                    .checked_sub(1)
                    .and_then(|index| words.get(index))
                    .is_some_and(|word| is_be_form(&word.normalized))
        }
    }
}

fn followed_by_likely_verb(
    words: &[RuleWord],
    pair_index: usize,
    sentence: &SubtitleSentence,
) -> bool {
    let Some(second) = words.get(pair_index + 1) else {
        return false;
    };
    let Some(complement) = words.get(pair_index + 2) else {
        return false;
    };
    !has_punctuation_boundary(sentence, second.token_index, complement.token_index)
        && !looks_like_non_verbal_complement(complement)
}

fn looks_like_non_verbal_complement(word: &RuleWord) -> bool {
    const BLOCKED: &[&str] = &[
        "a", "an", "any", "her", "him", "his", "it", "its", "me", "my", "our", "some", "that",
        "the", "their", "them", "these", "this", "those", "us", "which", "whose", "you", "your",
    ];
    BLOCKED.contains(&word.normalized.as_str()) || looks_like_proper_name(&word.text)
}

fn looks_like_proper_name(text: &str) -> bool {
    text.chars().next().is_some_and(char::is_uppercase)
}

fn is_conservative_destination(word: Option<&RuleWord>) -> bool {
    const AMBIGUOUS_DESTINATIONS: &[&str] = &[
        "airport",
        "bed",
        "church",
        "class",
        "college",
        "court",
        "dinner",
        "downtown",
        "home",
        "hospital",
        "jail",
        "lunch",
        "market",
        "office",
        "prison",
        "school",
        "station",
        "store",
        "town",
        "university",
        "work",
    ];
    word.is_some_and(|word| AMBIGUOUS_DESTINATIONS.contains(&word.normalized.as_str()))
}

fn starts_with_wh_extraction(words: &[RuleWord], pair_index: usize) -> bool {
    const WH_WORDS: &[&str] = &[
        "how", "what", "when", "where", "which", "who", "whom", "whose",
    ];
    words
        .iter()
        .take(pair_index)
        .any(|word| WH_WORDS.contains(&word.normalized.as_str()))
}

fn is_be_form(word: &str) -> bool {
    matches!(
        word,
        "am" | "are" | "be" | "been" | "being" | "is" | "was" | "were"
    )
}

pub(super) fn weak_form_context_allows(
    words: &[RuleWord],
    index: usize,
    sentence: &SubtitleSentence,
) -> bool {
    let word = &words[index];
    let Some(next) = words.get(index + 1) else {
        return false;
    };
    if has_punctuation_boundary(sentence, word.token_index, next.token_index) {
        return false;
    }
    if index == 0 && matches!(word.normalized.as_str(), "he" | "her" | "him" | "his") {
        return false;
    }
    if word.normalized == "the" && next.first_phone().is_some_and(crate::arpabet_is_vowel) {
        return false;
    }
    true
}
