pub(super) fn overlaps_token_range(
    left_start: Option<u32>,
    left_end: Option<u32>,
    right_start: Option<u32>,
    right_end: Option<u32>,
) -> bool {
    let (Some(left_start), Some(left_end), Some(right_start), Some(right_end)) =
        (left_start, left_end, right_start, right_end)
    else {
        return false;
    };
    left_start <= right_end && right_start <= left_end
}

pub(super) fn normalize_rhythm_word(value: &str) -> String {
    value
        .chars()
        .filter(|ch| ch.is_ascii_alphanumeric() || *ch == '\'')
        .collect::<String>()
        .to_ascii_lowercase()
}

pub(super) fn is_function_word(value: &str) -> bool {
    matches!(
        value,
        "a" | "an"
            | "the"
            | "and"
            | "or"
            | "but"
            | "to"
            | "of"
            | "in"
            | "on"
            | "at"
            | "about"
            | "for"
            | "from"
            | "with"
            | "as"
            | "by"
            | "is"
            | "am"
            | "are"
            | "was"
            | "were"
            | "be"
            | "been"
            | "being"
            | "do"
            | "does"
            | "did"
            | "have"
            | "has"
            | "had"
            | "can"
            | "could"
            | "will"
            | "would"
            | "should"
            | "may"
            | "might"
            | "must"
            | "not"
            | "i"
            | "you"
            | "he"
            | "she"
            | "it"
            | "we"
            | "they"
            | "that"
            | "this"
            | "these"
            | "those"
            | "who"
            | "whom"
            | "whose"
            | "which"
            | "when"
            | "where"
            | "why"
            | "how"
            | "me"
            | "him"
            | "her"
            | "us"
            | "them"
            | "my"
            | "your"
            | "his"
            | "our"
            | "their"
            | "there"
    )
}

pub(super) fn is_information_function_word(value: &str) -> bool {
    matches!(
        value,
        "no" | "not"
            | "never"
            | "none"
            | "nobody"
            | "nothing"
            | "neither"
            | "nor"
            | "this"
            | "that"
            | "these"
            | "those"
            | "who"
            | "what"
            | "when"
            | "where"
            | "why"
            | "how"
            | "must"
            | "should"
            | "can"
            | "could"
            | "will"
            | "would"
    )
}

pub(super) fn clamp01(value: f32) -> f32 {
    value.clamp(0.0, 1.0)
}

pub(super) fn score_flag(value: bool) -> f32 {
    if value { 1.0 } else { 0.0 }
}

pub(super) fn is_vowel(symbol: &str) -> bool {
    matches!(
        strip_stress(symbol).as_str(),
        "AA" | "AE"
            | "AH"
            | "AO"
            | "AW"
            | "AX"
            | "AY"
            | "EH"
            | "ER"
            | "EY"
            | "IH"
            | "IY"
            | "OW"
            | "OY"
            | "UH"
            | "UW"
    )
}

pub(super) fn strip_stress(symbol: &str) -> String {
    symbol
        .chars()
        .filter(|value| !value.is_ascii_digit())
        .collect::<String>()
        .to_ascii_uppercase()
}

pub(super) fn arpabet_display(symbol: &str) -> String {
    match strip_stress(symbol).as_str() {
        "AA" => "ɑ",
        "AE" => "æ",
        "AH" => "ʌ",
        "AO" => "ɔ",
        "AW" => "aʊ",
        "AX" => "ə",
        "AY" => "aɪ",
        "EH" => "ɛ",
        "ER" => "ɝ",
        "EY" => "eɪ",
        "IH" => "ɪ",
        "IY" => "i",
        "OW" => "oʊ",
        "OY" => "ɔɪ",
        "UH" => "ʊ",
        "UW" => "u",
        "SH" => "ʃ",
        "ZH" => "ʒ",
        "TH" => "θ",
        "DH" => "ð",
        "CH" => "tʃ",
        "JH" => "dʒ",
        "NG" => "ŋ",
        "Y" => "j",
        "HH" => "h",
        "DX" => "ɾ",
        other => other,
    }
    .into()
}
