//! Language learning capability profiles (Phase 2.6).
//!
//! Per ADR 0012, language behavior is declared per language via a profile and a
//! capability matrix, and resolved through providers. Capability `kind`s are
//! **open namespaced strings** (`core.*` + `<lang>.*`) with clean degradation,
//! not exhaustive enums, so adding a language never edits shared `match` arms.
//!
//! The global vocabulary status enum (`WordStatus`) stays language-agnostic and
//! is intentionally *not* part of a profile: it sits on the comprehension axis
//! (meaning x sound) that holds for every language. What varies per language is
//! the diagnosis *reason* taxonomy, declared here as `diagnosis_reasons`.

use serde::{Deserialize, Serialize};

use crate::LanguageCode;

/// Support level for a timeline / resource capability.
///
/// This is a fixed, language-agnostic vocabulary (not a per-language kind), so a
/// closed enum is appropriate here — unlike the open `kind` string fields below.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CapabilitySupport {
    Supported,
    Approximate,
    Unsupported,
}

/// A declared language-learning capability matrix for one learning language.
///
/// All `kind` fields are open namespaced strings (e.g. `core.word`, `zh.tone`,
/// `ja.mora`). Unknown kinds must degrade cleanly at the consumer; they are
/// never matched exhaustively.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LanguageLearningProfile {
    pub language: LanguageCode,
    pub display_name: String,
    /// Writing system, e.g. `latin`, `han`, `cyrillic`, `arabic`.
    pub script: String,
    /// Tokenization strategy kind, e.g. `core.whitespace`,
    /// `zh.word_segmentation`, `core.char`.
    pub tokenization: String,
    /// Lexical unit granularity kinds, e.g. `core.word`, `core.char`,
    /// `core.phrase`, `core.morpheme`.
    pub lexical_granularities: Vec<String>,
    /// Lexical normalization kind, e.g. `core.lemma`, `core.surface`,
    /// `core.citation`, `core.root`. The normalized key is the opaque output of
    /// a per-language normalizer (no substring assumption; see ADR 0012 R2).
    pub lexical_normalization: String,
    /// Listening unit kinds, e.g. `en.stress_group`, `core.chunk`,
    /// `core.syllable`, `zh.tone_syllable`, `ja.mora`.
    pub listening_units: Vec<String>,
    /// Pronunciation system kind, e.g. `en.ipa`, `zh.pinyin`, `core.none`.
    pub pronunciation: String,
    /// Sound feature kinds, e.g. `en.stress`, `zh.tone`, `core.vowel_length`.
    pub sound_features: Vec<String>,
    /// Rhythm / prosody kind, e.g. `en.stress_timed`, `zh.syllable_tone`,
    /// `ja.mora_timed`.
    pub rhythm_prosody: String,
    /// Morphology kind, e.g. `en.analytic`, `zh.analytic`, `ar.templatic`.
    pub morphology: String,
    /// Dictionary provider ids declared for this language.
    pub dictionary_providers: Vec<String>,
    /// Diagnosis reason kinds available for this language (per-profile,
    /// extensible). The global vocabulary status enum stays language-agnostic.
    pub diagnosis_reasons: Vec<String>,
    pub word_timeline: CapabilitySupport,
    pub chunk_timeline: CapabilitySupport,
    pub phone_timeline: CapabilitySupport,
}

fn strings(values: &[&str]) -> Vec<String> {
    values.iter().map(|value| value.to_string()).collect()
}

impl LanguageLearningProfile {
    /// English profile — the regression baseline. The given `language` code is
    /// retained so regional variants (`en-us` / `en-gb`) keep their exact code.
    pub fn english(language: LanguageCode) -> Self {
        Self {
            language,
            display_name: "English".to_string(),
            script: "latin".to_string(),
            tokenization: "core.whitespace".to_string(),
            lexical_granularities: strings(&["core.word"]),
            lexical_normalization: "core.lemma".to_string(),
            listening_units: strings(&[
                "core.sound_pattern",
                "core.chunk",
                "en.stress_group",
                "en.reduced_form",
            ]),
            pronunciation: "en.ipa".to_string(),
            sound_features: strings(&["en.stress", "en.weak_form", "en.linking"]),
            rhythm_prosody: "en.stress_timed".to_string(),
            morphology: "en.analytic".to_string(),
            dictionary_providers: strings(&["free_dictionary", "ecdict"]),
            diagnosis_reasons: strings(&[
                "weak_form",
                "linking",
                "elision",
                "assimilation",
                "fuzzy_boundary",
                "reduced_form",
            ]),
            word_timeline: CapabilitySupport::Supported,
            chunk_timeline: CapabilitySupport::Supported,
            // Phase 2.5 benchmark selected no release phone provider yet.
            phone_timeline: CapabilitySupport::Approximate,
        }
    }

    /// Mandarin Chinese profile — the first non-English implementation target.
    pub fn chinese(language: LanguageCode) -> Self {
        Self {
            language,
            display_name: "Chinese".to_string(),
            script: "han".to_string(),
            tokenization: "zh.word_segmentation".to_string(),
            lexical_granularities: strings(&["core.word", "core.char", "core.phrase"]),
            lexical_normalization: "core.surface".to_string(),
            listening_units: strings(&[
                "core.syllable",
                "zh.tone_syllable",
                "core.word",
                "core.phrase",
            ]),
            pronunciation: "zh.pinyin".to_string(),
            sound_features: strings(&["zh.tone", "zh.neutral_tone", "zh.tone_sandhi", "zh.erhua"]),
            rhythm_prosody: "zh.syllable_tone".to_string(),
            morphology: "zh.analytic".to_string(),
            dictionary_providers: strings(&["cedict"]),
            diagnosis_reasons: strings(&[
                "tone_confusion",
                "word_boundary",
                "homophone",
                "neutral_tone",
                "tone_sandhi",
            ]),
            word_timeline: CapabilitySupport::Supported,
            chunk_timeline: CapabilitySupport::Supported,
            phone_timeline: CapabilitySupport::Unsupported,
        }
    }

    /// Japanese profile — the real second non-English language. It shares the Han
    /// script with Chinese, which is exactly why it validates the dispatch layer:
    /// tokenization (`ja.morphological` — lindera with a character-level fallback),
    /// the JMdict dictionary provider, kana pronunciation and `ja.*` diagnosis
    /// reasons are all selected by profile + provider, touching no dispatcher
    /// branch. `lexical_normalization` stays `core.surface`: Japanese inflection is
    /// not yet unified to a base form (a deferred normalization seam), so
    /// conjugations are distinct surface units.
    pub fn japanese(language: LanguageCode) -> Self {
        Self {
            language,
            display_name: "Japanese".to_string(),
            script: "japanese".to_string(),
            tokenization: "ja.morphological".to_string(),
            lexical_granularities: strings(&["core.word", "core.char", "core.morpheme"]),
            lexical_normalization: "core.surface".to_string(),
            listening_units: strings(&["core.syllable", "ja.mora", "core.word", "core.phrase"]),
            pronunciation: "ja.kana".to_string(),
            sound_features: strings(&["ja.pitch_accent", "ja.mora", "ja.long_vowel", "ja.gemination"]),
            rhythm_prosody: "ja.mora_timed".to_string(),
            morphology: "ja.agglutinative".to_string(),
            dictionary_providers: strings(&["jmdict"]),
            diagnosis_reasons: strings(&[
                "pitch_accent",
                "mora_boundary",
                "long_vowel",
                "gemination",
                "word_boundary",
            ]),
            // Non-English audio -> listening-unit production is deferred
            // (ADR 0012 Future Path); declare these unsupported, not faked.
            word_timeline: CapabilitySupport::Unsupported,
            chunk_timeline: CapabilitySupport::Unsupported,
            phone_timeline: CapabilitySupport::Unsupported,
        }
    }

    /// A minimal degraded profile for a language with no declared support.
    /// Tokenization falls back to whitespace, units to surface words, sound
    /// capabilities to none, and timelines to unsupported — so an unknown
    /// language never fails, it degrades cleanly.
    pub fn degraded(language: LanguageCode) -> Self {
        Self {
            language,
            display_name: "Unsupported language".to_string(),
            script: "unknown".to_string(),
            tokenization: "core.whitespace".to_string(),
            lexical_granularities: strings(&["core.word"]),
            lexical_normalization: "core.surface".to_string(),
            listening_units: Vec::new(),
            pronunciation: "core.none".to_string(),
            sound_features: Vec::new(),
            rhythm_prosody: "core.unknown".to_string(),
            morphology: "core.unknown".to_string(),
            dictionary_providers: Vec::new(),
            diagnosis_reasons: Vec::new(),
            word_timeline: CapabilitySupport::Unsupported,
            chunk_timeline: CapabilitySupport::Unsupported,
            phone_timeline: CapabilitySupport::Unsupported,
        }
    }

    /// Whether a listening-unit kind is declared for this language.
    pub fn supports_listening_unit(&self, kind: &str) -> bool {
        self.listening_units.iter().any(|value| value == kind)
    }

    /// Whether a sound-feature kind is declared for this language.
    pub fn has_sound_feature(&self, kind: &str) -> bool {
        self.sound_features.iter().any(|value| value == kind)
    }
}

/// Language codes with a declared (non-degraded) profile.
pub fn available_languages() -> &'static [&'static str] {
    &["en", "zh", "ja"]
}

/// Resolve the built-in profile for a language code, falling back to a clean
/// degraded profile for any language without declared support.
///
/// Matching is on the primary subtag, so regional variants (`en-us`, `zh-cn`,
/// `zh-hant`, ...) resolve to their base language profile while keeping the
/// exact requested code.
pub fn profile_for(language: &LanguageCode) -> LanguageLearningProfile {
    let primary = language
        .as_str()
        .split('-')
        .next()
        .unwrap_or(language.as_str());
    match primary {
        "en" => LanguageLearningProfile::english(language.clone()),
        "zh" => LanguageLearningProfile::chinese(language.clone()),
        "ja" => LanguageLearningProfile::japanese(language.clone()),
        _ => LanguageLearningProfile::degraded(language.clone()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lang(code: &str) -> LanguageCode {
        LanguageCode::parse(code).unwrap()
    }

    #[test]
    fn english_profile_is_whitespace_and_lemma() {
        let profile = profile_for(&lang("en"));
        assert_eq!(profile.display_name, "English");
        assert_eq!(profile.tokenization, "core.whitespace");
        assert_eq!(profile.lexical_normalization, "core.lemma");
        assert_eq!(profile.word_timeline, CapabilitySupport::Supported);
    }

    #[test]
    fn chinese_profile_segments_and_declares_tone() {
        let profile = profile_for(&lang("zh"));
        assert_eq!(profile.display_name, "Chinese");
        assert_eq!(profile.tokenization, "zh.word_segmentation");
        assert!(profile
            .lexical_granularities
            .contains(&"core.char".to_string()));
        assert!(profile.has_sound_feature("zh.tone"));
        assert!(profile.supports_listening_unit("zh.tone_syllable"));
        assert_eq!(profile.pronunciation, "zh.pinyin");
    }

    #[test]
    fn japanese_profile_is_real_language_and_borrows_nothing_from_chinese() {
        let profile = profile_for(&lang("ja"));
        assert_eq!(profile.display_name, "Japanese");
        // Morphological tokenization + JMdict + kana pronunciation, all its own —
        // selected by profile/provider, sharing the Han script with zh but no code.
        assert_eq!(profile.tokenization, "ja.morphological");
        assert_eq!(profile.pronunciation, "ja.kana");
        assert_eq!(profile.dictionary_providers, vec!["jmdict".to_string()]);
        // It must not borrow Chinese pinyin or CC-CEDICT.
        assert_ne!(profile.pronunciation, "zh.pinyin");
        assert!(!profile.dictionary_providers.contains(&"cedict".to_string()));
        // Japanese declares its own listening axis (mora) and reasons.
        assert!(profile.supports_listening_unit("ja.mora"));
        assert!(profile.has_sound_feature("ja.pitch_accent"));
        assert!(profile
            .diagnosis_reasons
            .contains(&"pitch_accent".to_string()));
        // It must not inherit Chinese tone reasons.
        assert!(!profile
            .diagnosis_reasons
            .contains(&"tone_confusion".to_string()));
    }

    #[test]
    fn regional_variants_resolve_to_base_and_keep_code() {
        let us = profile_for(&lang("en-US"));
        assert_eq!(us.display_name, "English");
        assert_eq!(us.language.as_str(), "en-us");

        let hant = profile_for(&lang("zh-Hant"));
        assert_eq!(hant.display_name, "Chinese");
        assert_eq!(hant.language.as_str(), "zh-hant");
    }

    #[test]
    fn unknown_language_degrades_cleanly() {
        let profile = profile_for(&lang("xx"));
        assert_eq!(profile.tokenization, "core.whitespace");
        assert!(profile.listening_units.is_empty());
        assert_eq!(profile.word_timeline, CapabilitySupport::Unsupported);
        assert_eq!(profile.phone_timeline, CapabilitySupport::Unsupported);
        // Degradation never panics and answers capability queries as false.
        assert!(!profile.supports_listening_unit("anything"));
    }
}
