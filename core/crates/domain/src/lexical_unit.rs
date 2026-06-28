//! Lexical learning unit (Phase 2.6, ADR 0012 R2).
//!
//! `LexicalUnit` is the new identity model for vocabulary learning objects in
//! any language. Identity is two orthogonal axes — **granularity** and
//! **normalization** — plus an opaque `normalized_key` produced by a per-language
//! normalizer (no substring / affix-stripping assumption; Arabic roots are
//! non-concatenative). It models only the vocabulary learning object, never
//! real-audio chunking, which stays with the timeline resources / `ListeningUnit`
//! view.

use serde::{Deserialize, Serialize};

use crate::{LanguageCode, LanguageLearningProfile};

/// A vocabulary learning object identity, language-relative.
///
/// `granularity` and `normalization` are open namespaced strings (see the
/// associated `GRANULARITY_*` / `NORMALIZATION_*` constants); unknown kinds are
/// carried through, never matched exhaustively.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LexicalUnit {
    pub language: LanguageCode,
    /// Granularity kind, e.g. `core.word`, `core.char`, `core.phrase`.
    pub granularity: String,
    /// Normalization kind, e.g. `core.lemma`, `core.surface`, `core.root`.
    pub normalization: String,
    /// Opaque normalizer output used for identity. No substring assumption.
    pub normalized_key: String,
    /// Surface form as displayed.
    pub display_form: String,
}

impl LexicalUnit {
    pub const GRANULARITY_CHAR: &'static str = "core.char";
    pub const GRANULARITY_WORD: &'static str = "core.word";
    pub const GRANULARITY_PHRASE: &'static str = "core.phrase";
    pub const GRANULARITY_MORPHEME: &'static str = "core.morpheme";

    pub const NORMALIZATION_SURFACE: &'static str = "core.surface";
    pub const NORMALIZATION_LEMMA: &'static str = "core.lemma";
    pub const NORMALIZATION_CITATION: &'static str = "core.citation";
    pub const NORMALIZATION_ROOT: &'static str = "core.root";

    pub fn new(
        language: LanguageCode,
        granularity: impl Into<String>,
        normalization: impl Into<String>,
        normalized_key: impl Into<String>,
        display_form: impl Into<String>,
    ) -> Self {
        Self {
            language,
            granularity: granularity.into(),
            normalization: normalization.into(),
            normalized_key: normalized_key.into(),
            display_form: display_form.into(),
        }
    }

    /// Build a word-granularity unit for a surface form using the profile's
    /// declared normalization and a baseline normalized key.
    ///
    /// A real per-language normalizer provider (English lemmatization via the
    /// dictionary provider, future Chinese, ...) may supply a different opaque
    /// key via [`LexicalUnit::new`]; this is the default when no provider key is
    /// available.
    pub fn word_from_profile(profile: &LanguageLearningProfile, surface: &str) -> Self {
        let normalization = profile.lexical_normalization.clone();
        let normalized_key = baseline_normalized_key(&normalization, surface);
        Self::new(
            profile.language.clone(),
            Self::GRANULARITY_WORD,
            normalization,
            normalized_key,
            surface,
        )
    }

    /// Build a character-granularity unit — the Chinese fallback granularity.
    pub fn character(language: LanguageCode, surface: &str) -> Self {
        Self::new(
            language,
            Self::GRANULARITY_CHAR,
            Self::NORMALIZATION_SURFACE,
            surface.trim(),
            surface,
        )
    }

    /// Stable identity string used to derive a persistent id.
    ///
    /// Word granularity uses the compact `language:normalized_key` identity.
    /// Non-word granularities namespace the key, so Chinese characters never
    /// collide with Chinese words or English lemmas.
    pub fn identity(&self) -> String {
        if self.granularity == Self::GRANULARITY_WORD {
            format!("{}:{}", self.language.as_str(), self.normalized_key)
        } else {
            format!(
                "{}:{}:{}",
                self.language.as_str(),
                self.granularity,
                self.normalized_key
            )
        }
    }
}

/// Baseline normalized key for a normalization kind. `core.lemma` lowercases and
/// trims (matching the existing English `normalize_lemma`); every other kind
/// keeps the trimmed surface, leaving real citation/root normalization to a
/// per-language provider.
pub fn baseline_normalized_key(normalization: &str, surface: &str) -> String {
    match normalization {
        LexicalUnit::NORMALIZATION_LEMMA => surface.trim().to_lowercase(),
        _ => surface.trim().to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::profile_for;

    fn lang(code: &str) -> LanguageCode {
        LanguageCode::parse(code).unwrap()
    }

    #[test]
    fn english_word_is_lemma_normalized_with_stable_identity() {
        let unit = LexicalUnit::word_from_profile(&profile_for(&lang("en")), "Going");
        assert_eq!(unit.granularity, LexicalUnit::GRANULARITY_WORD);
        assert_eq!(unit.normalization, LexicalUnit::NORMALIZATION_LEMMA);
        assert_eq!(unit.normalized_key, "going");
        assert_eq!(unit.identity(), "en:going");
    }

    #[test]
    fn chinese_word_keeps_surface_and_assumes_no_lemma() {
        let unit = LexicalUnit::word_from_profile(&profile_for(&lang("zh")), "咖啡");
        assert_eq!(unit.granularity, LexicalUnit::GRANULARITY_WORD);
        assert_eq!(unit.normalization, LexicalUnit::NORMALIZATION_SURFACE);
        assert_eq!(unit.normalized_key, "咖啡");
        assert_eq!(unit.identity(), "zh:咖啡");
    }

    #[test]
    fn chinese_char_does_not_collide_with_word_or_other_languages() {
        let word = LexicalUnit::word_from_profile(&profile_for(&lang("zh")), "咖啡");
        let ch = LexicalUnit::character(lang("zh"), "咖");
        assert_eq!(ch.granularity, LexicalUnit::GRANULARITY_CHAR);
        assert_eq!(ch.identity(), "zh:core.char:咖");
        // Character granularity is namespaced, so it never pollutes the word
        // vocabulary or another language's lemmas.
        assert_ne!(ch.identity(), word.identity());
        let en_word = LexicalUnit::word_from_profile(&profile_for(&lang("en")), "ka");
        assert_ne!(word.identity(), en_word.identity());
    }

    #[test]
    fn baseline_normalizer_lowercases_only_for_lemma() {
        assert_eq!(
            baseline_normalized_key(LexicalUnit::NORMALIZATION_LEMMA, "  Going "),
            "going"
        );
        assert_eq!(
            baseline_normalized_key(LexicalUnit::NORMALIZATION_SURFACE, "  咖啡 "),
            "咖啡"
        );
        // An unknown normalization kind degrades to a trimmed surface key.
        assert_eq!(
            baseline_normalized_key("ar.templatic", " kataba "),
            "kataba"
        );
    }
}
