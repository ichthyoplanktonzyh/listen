// Split out of lib.rs (mechanical decomposition).

use crate::cedict::numbered_pinyin_to_marks;
use crate::free_dictionary::parse_free_dictionary_phonetics;
use crate::*;
use application::{DictionaryProvider, LexicalNormalizationProvider};
use domain::{
    LanguageCode, SubtitleSentence, SubtitleSentenceId, SubtitleToken, SubtitleTokenKind, TimeMs,
    normalize_lemma,
};

fn fixture() -> tempfile::NamedTempFile {
    tempfile::Builder::new()
        .prefix("llplayernext-ecdict-")
        .suffix(".csv")
        .tempfile()
        .unwrap()
}

#[test]
fn ecdict_normalizes_inflections_and_finds_phrase_entries() {
    let fixture = fixture();
    let path = fixture.path().to_path_buf();
    {
        use std::io::Write;
        let mut writer = std::io::BufWriter::new(fixture.as_file());
        writeln!(writer, "word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio").unwrap();
        writeln!(
            writer,
            "go,go,move,,,,,,42,55,\"p:went/gone i:going 3:goes\",,"
        )
        .unwrap();
        writeln!(writer, "piece of cake,,easy task,,,,,,,,,,").unwrap();
        writer.flush().unwrap();
        fixture.as_file().sync_all().unwrap();
    }
    let provider = EcdictProvider::with_path(path.clone(), "fixture-v1");
    let language = LanguageCode::parse("en-US").unwrap();
    assert_eq!(
        provider.normalize(&language, "went").unwrap().as_deref(),
        Some("go")
    );
    assert_eq!(provider.provider_id(), "ecdict");
    assert_eq!(provider.version(), "fixture-v1");
    assert_eq!(provider.frequency_rank(&language, "went"), Some(42));

    let words = ["It", "is", "a", "piece", "of", "cake"];
    let sentence = SubtitleSentence {
        id: SubtitleSentenceId::from_fingerprint("sentence", "fixture"),
        index: 0,
        start: TimeMs::new(0),
        end: TimeMs::new(1000),
        original_text: words.join(" "),
        display_text: words.join(" "),
        tokens: words
            .iter()
            .enumerate()
            .map(|(index, value)| SubtitleToken {
                index: index as u32,
                kind: SubtitleTokenKind::Word,
                text: (*value).into(),
                normalized: Some(normalize_lemma(value)),
                start_char: 0,
                end_char: value.len() as u32,
            })
            .collect(),
    };
    let candidates = provider.phrase_candidates(&language, &sentence).unwrap();
    assert_eq!(candidates.len(), 1);
    assert_eq!(candidates[0].normalized_form, "piece of cake");
    assert_eq!(candidates[0].token_start, 3);
    assert_eq!(candidates[0].token_end, 5);
}

#[test]
fn ecdict_reflects_install_replacement_damage_and_removal_without_restart() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("ecdict.data");
    let provider = EcdictProvider::with_path(path.clone(), "fixture-v1");
    let language = LanguageCode::parse("en").unwrap();

    assert_eq!(provider.frequency_rank(&language, "quokka"), None);
    std::fs::write(
        &path,
        "word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio\nquokka,,marsupial,,,,,,71,,,,\n",
    )
    .unwrap();
    assert_eq!(provider.frequency_rank(&language, "quokka"), Some(71));

    std::fs::remove_file(&path).unwrap();
    std::fs::write(
        &path,
        "word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio\nquokka,,animal,,,,,,19,,,,\n",
    )
    .unwrap();
    assert_eq!(provider.frequency_rank(&language, "quokka"), Some(19));

    std::fs::write(&path, "invalid").unwrap();
    assert_eq!(provider.frequency_rank(&language, "quokka"), None);

    std::fs::remove_file(&path).unwrap();
    assert_eq!(provider.frequency_rank(&language, "quokka"), None);
}

#[test]
fn chinese_provider_falls_back_to_seed_without_cedict() {
    // No installed CC-CEDICT: lookups come from the built-in seed.
    let provider = ChineseDictionaryProvider::with_path("/nonexistent/cc-cedict.data".into());
    let info = provider.info();
    assert_eq!(info.id, "cc-cedict");
    assert_eq!(info.supported_languages, vec!["zh".to_string()]);
    assert!(info.offline);

    let lookup = provider.resolve("咖啡").expect("known word resolves");
    assert_eq!(lookup.provider, "cc-cedict");
    assert_eq!(lookup.phonetics.len(), 1);
    assert_eq!(lookup.phonetics[0].text, "kā fēi");
    assert_eq!(lookup.phonetics[0].region.as_deref(), Some("zh"));
    assert_eq!(lookup.definitions.len(), 1);
    assert_eq!(lookup.definitions[0].text, "coffee");

    // Single characters that also stand alone resolve too (char-granularity).
    assert_eq!(
        provider.resolve("好").expect("char resolves").phonetics[0].text,
        "hǎo"
    );
    // Unknown words degrade to None rather than failing.
    assert!(provider.resolve("量子力学").is_none());
}

#[test]
fn chinese_provider_reads_installed_cedict() {
    let fixture = tempfile::Builder::new()
        .prefix("llplayernext-cedict-")
        .suffix(".u8")
        .tempfile()
        .unwrap();
    {
        use std::io::Write;
        let mut writer = std::io::BufWriter::new(fixture.as_file());
        writeln!(writer, "# CC-CEDICT").unwrap();
        writeln!(writer, "你好 你好 [ni3 hao3] /hello/hi/").unwrap();
        writeln!(writer, "電影 电影 [dian4 ying3] /film/movie/").unwrap();
        writeln!(writer, "旅行 旅行 [lu:3 xing2] /to travel/journey/").unwrap();
        writer.flush().unwrap();
        fixture.as_file().sync_all().unwrap();
    }
    let provider = ChineseDictionaryProvider::with_path(fixture.path().to_path_buf());

    // Simplified headword: numbered pinyin becomes tone marks, glosses join.
    let lookup = provider.resolve("电影").expect("simplified resolves");
    assert_eq!(lookup.provider, "cc-cedict");
    assert_eq!(lookup.phonetics[0].text, "diàn yǐng");
    assert_eq!(lookup.definitions[0].text, "film; movie");
    // Traditional headword resolves to the same entry.
    assert_eq!(
        provider
            .resolve("電影")
            .expect("traditional resolves")
            .phonetics[0]
            .text,
        "diàn yǐng"
    );
    // u: becomes ü and carries the tone.
    assert_eq!(
        provider.resolve("旅行").unwrap().phonetics[0].text,
        "lǚ xíng"
    );
    // A word absent from the file still resolves from the built-in seed.
    assert_eq!(
        provider.resolve("咖啡").unwrap().phonetics[0].text,
        "kā fēi"
    );
}

#[test]
fn chinese_provider_reflects_replacement_damage_and_removal() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("cc-cedict.data");
    let provider = ChineseDictionaryProvider::with_path(path.clone());

    assert!(provider.resolve("量子力学").is_none());
    std::fs::write(
        &path,
        "量子力學 量子力学 [liang4 zi3 li4 xue2] /quantum mechanics/\n",
    )
    .unwrap();
    assert_eq!(
        provider.resolve("量子力学").unwrap().definitions[0].text,
        "quantum mechanics"
    );

    std::fs::remove_file(&path).unwrap();
    std::fs::write(
        &path,
        "量子力學 量子力学 [liang4 zi3 li4 xue2] /quantum physics/\n",
    )
    .unwrap();
    assert_eq!(
        provider.resolve("量子力学").unwrap().definitions[0].text,
        "quantum physics"
    );

    std::fs::write(&path, "invalid").unwrap();
    assert!(provider.resolve("量子力学").is_none());
    std::fs::remove_file(&path).unwrap();
    assert!(provider.resolve("量子力学").is_none());
}

#[test]
fn japanese_provider_falls_back_to_seed_without_jmdict() {
    // No installed JMdict/EDICT2: lookups come from the built-in seed.
    let provider = JapaneseDictionaryProvider::with_path("/nonexistent/jmdict.data".into());
    let info = provider.info();
    assert_eq!(info.id, "jmdict");
    assert_eq!(info.supported_languages, vec!["ja".to_string()]);
    assert!(info.offline);

    let lookup = provider.resolve("学生").expect("known word resolves");
    assert_eq!(lookup.provider, "jmdict");
    assert_eq!(lookup.phonetics[0].text, "がくせい");
    assert_eq!(lookup.phonetics[0].region.as_deref(), Some("ja"));
    assert_eq!(lookup.definitions[0].text, "student");
    // Unknown words degrade to None rather than borrowing Chinese.
    assert!(provider.resolve("量子力学").is_none());
}

#[test]
fn japanese_provider_reads_installed_edict() {
    let fixture = tempfile::Builder::new()
        .prefix("llplayernext-jmdict-")
        .suffix(".data")
        .tempfile()
        .unwrap();
    {
        use std::io::Write;
        let mut writer = std::io::BufWriter::new(fixture.as_file());
        writeln!(writer, "# JMdict/EDICT2").unwrap();
        writeln!(writer, "頭 [あたま] /(n) head/(P)/EntL1582710X/").unwrap();
        writeln!(
            writer,
            "見る;観る [みる] /(v1,vt) to see/to look at/EntL1259290X/"
        )
        .unwrap();
        writeln!(writer, "ありがとう /(int) thank you/EntL1000000X/").unwrap();
        writer.flush().unwrap();
        fixture.as_file().sync_all().unwrap();
    }
    let provider = JapaneseDictionaryProvider::with_path(fixture.path().to_path_buf());

    // Kanji headword: reading and gloss parse; (pos) and EntL are stripped.
    let lookup = provider.resolve("頭").expect("kanji resolves");
    assert_eq!(lookup.provider, "jmdict");
    assert_eq!(lookup.phonetics[0].text, "あたま");
    assert_eq!(lookup.definitions[0].text, "head");
    // Kana reading resolves to the same entry.
    assert_eq!(
        provider.resolve("あたま").unwrap().definitions[0].text,
        "head"
    );
    // A ;-separated variant headword resolves; multiple glosses join.
    assert_eq!(
        provider.resolve("観る").unwrap().definitions[0].text,
        "to see; to look at"
    );
    // Kana-only headword carries no separate reading phonetic.
    let thanks = provider.resolve("ありがとう").unwrap();
    assert_eq!(thanks.definitions[0].text, "thank you");
    assert!(thanks.phonetics.is_empty());
    // A word absent from the file still resolves from the built-in seed.
    assert_eq!(
        provider.resolve("学生").unwrap().phonetics[0].text,
        "がくせい"
    );
}

#[test]
fn japanese_provider_reflects_replacement_damage_and_removal() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("jmdict.data");
    let provider = JapaneseDictionaryProvider::with_path(path.clone());

    assert!(provider.resolve("量子力学").is_none());
    std::fs::write(
        &path,
        "量子力学 [りょうしりきがく] /(n) quantum mechanics/\n",
    )
    .unwrap();
    assert_eq!(
        provider.resolve("量子力学").unwrap().definitions[0].text,
        "quantum mechanics"
    );

    std::fs::remove_file(&path).unwrap();
    std::fs::write(&path, "量子力学 [りょうしりきがく] /(n) quantum physics/\n").unwrap();
    assert_eq!(
        provider.resolve("量子力学").unwrap().definitions[0].text,
        "quantum physics"
    );

    std::fs::write(&path, "invalid").unwrap();
    assert!(provider.resolve("量子力学").is_none());
    std::fs::remove_file(&path).unwrap();
    assert!(provider.resolve("量子力学").is_none());
}

#[test]
fn numbered_pinyin_tone_placement_follows_standard_rules() {
    assert_eq!(numbered_pinyin_to_marks("ni3 hao3"), "nǐ hǎo");
    assert_eq!(numbered_pinyin_to_marks("xue2 xi2"), "xué xí");
    assert_eq!(numbered_pinyin_to_marks("dou1"), "dōu"); // ou -> mark o
    assert_eq!(numbered_pinyin_to_marks("guo3"), "guǒ"); // else last vowel
    assert_eq!(numbered_pinyin_to_marks("liu2"), "liú"); // iu -> mark u
    assert_eq!(numbered_pinyin_to_marks("lu:3"), "lǚ"); // u: -> ü
    assert_eq!(numbered_pinyin_to_marks("de5"), "de"); // neutral tone, no mark
}

#[test]
fn free_dictionary_phonetics_preserve_pronunciation_audio() {
    let entry = serde_json::json!({
        "phonetics": [
            {"text": "/həˈloʊ/", "audio": "//example.test/hello-us.mp3"},
            {"text": "/hɛˈləʊ/", "audio": ""}
        ]
    });
    let values = parse_free_dictionary_phonetics(&entry);
    assert_eq!(values.len(), 2);
    assert_eq!(
        values[0].audio_url.as_deref(),
        Some("https://example.test/hello-us.mp3")
    );
    assert_eq!(values[1].audio_url, None);
}

#[test]
fn ecdict_phrase_candidates_handle_short_sentences() {
    let mut fixture = fixture();
    let path = fixture.path().to_path_buf();
    use std::io::Write;
    write!(
        fixture,
        "word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio\n\
         piece of cake,,easy task,,,,,,,,,,\n"
    )
    .unwrap();
    fixture.flush().unwrap();
    let provider = EcdictProvider::with_path(path.clone(), "test");
    let sentence = SubtitleSentence {
        id: SubtitleSentenceId::parse("short").unwrap(),
        index: 0,
        start: TimeMs::new(0),
        end: TimeMs::new(1000),
        original_text: "Hello".into(),
        display_text: "Hello".into(),
        tokens: vec![SubtitleToken {
            index: 0,
            kind: SubtitleTokenKind::Word,
            text: "Hello".into(),
            normalized: Some("hello".into()),
            start_char: 0,
            end_char: 5,
        }],
    };
    assert!(
        provider
            .phrase_candidates(&LanguageCode::parse("en").unwrap(), &sentence)
            .unwrap()
            .is_empty()
    );
}
