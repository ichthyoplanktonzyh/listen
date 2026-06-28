use std::collections::HashMap;
use std::process::Command;
use std::sync::OnceLock;

use domain::DetectedPhone;
use serde::Deserialize;

pub const PROVIDER_ID: &str = "wav2vec2-ctc-phoneme";
pub const PROVIDER_VERSION: &str = "fb-espeak-v1";

#[derive(Debug, Deserialize)]
struct SidecarOutput {
    phones: Vec<SidecarPhone>,
}

#[derive(Debug, Deserialize)]
struct SidecarPhone {
    symbol: String,
    start_ms: u64,
    end_ms: u64,
    confidence: Option<f32>,
}

#[derive(Debug)]
pub struct RecognizedPhones {
    pub phones: Vec<DetectedPhone>,
    pub phone_set: String,
}

pub fn recognize_phones(
    audio_path: &str,
    model_dir: &str,
    start_ms: u64,
    end_ms: u64,
    model_revision: &str,
) -> Result<RecognizedPhones, String> {
    let script = sidecar_script_path().ok_or("wav2vec2 phoneme sidecar script not found")?;
    let python = sidecar_python();
    let mut command = Command::new(&python);
    command.env("PATH", sidecar_path_env());
    let output = command
        .arg(&script)
        .arg("--model-dir")
        .arg(model_dir)
        .arg("--audio")
        .arg(audio_path)
        .arg("--start-ms")
        .arg(start_ms.to_string())
        .arg("--end-ms")
        .arg(end_ms.to_string())
        .output()
        .map_err(|e| format!("failed to run sidecar: {e}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("sidecar failed ({}): {stderr}", output.status));
    }
    let sidecar: SidecarOutput = serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("failed to parse sidecar output: {e}"))?;
    let map = ipa_to_arpabet_map();
    let skip = skip_tokens();
    let mut phones = Vec::new();
    for sp in &sidecar.phones {
        if skip.contains(&sp.symbol.as_str()) {
            continue;
        }
        let (arpabet, display_ipa) = map_ipa_phone(&sp.symbol, map);
        phones.push(DetectedPhone {
            symbol: arpabet,
            display_ipa,
            phone_set: "arpabet".into(),
            start_ms: sp.start_ms,
            end_ms: sp.end_ms,
            confidence: sp.confidence,
            token_index: None,
            provider_id: PROVIDER_ID.into(),
            provider_version: PROVIDER_VERSION.into(),
            model_revision: model_revision.into(),
        });
    }
    Ok(RecognizedPhones {
        phones,
        phone_set: "arpabet".into(),
    })
}

fn map_ipa_phone(ipa: &str, map: &HashMap<&str, (&str, &str)>) -> (String, String) {
    if let Some(&(arpabet, display)) = map.get(ipa) {
        (arpabet.to_uppercase(), display.into())
    } else {
        (ipa.to_uppercase(), ipa.into())
    }
}

fn sidecar_python() -> String {
    if let Ok(path) = std::env::var("LLPLAYERNEXT_PYTHON") {
        if std::path::Path::new(&path).is_file() {
            return path;
        }
    }
    let mut dirs: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            dirs.push(parent.into());
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        dirs.push(cwd);
    }
    for start in &dirs {
        let mut dir = start.as_path();
        loop {
            let candidate = dir.join(".venv/bin/python3");
            if candidate.is_file() {
                return candidate.to_string_lossy().into_owned();
            }
            match dir.parent() {
                Some(parent) if parent != dir => dir = parent,
                _ => break,
            }
        }
    }
    "python3".into()
}

fn sidecar_path_env() -> String {
    let mut value = std::env::var("PATH").unwrap_or_default();
    for dir in ["/usr/local/bin", "/opt/homebrew/bin"] {
        if std::path::Path::new(dir).is_dir() && !value.split(':').any(|entry| entry == dir) {
            value = if value.is_empty() {
                dir.into()
            } else {
                format!("{dir}:{value}")
            };
        }
    }
    value
}

fn sidecar_script_path() -> Option<String> {
    if let Ok(path) = std::env::var("LLPLAYERNEXT_PHONEME_SIDECAR") {
        if std::path::Path::new(&path).is_file() {
            return Some(path);
        }
    }
    let name = "wav2vec2-phoneme-cli.py";
    let mut dirs: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            dirs.push(parent.into());
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        dirs.push(cwd);
    }
    for start in &dirs {
        let mut dir = start.as_path();
        loop {
            let candidate = dir.join("scripts").join(name);
            if candidate.is_file() {
                return Some(candidate.to_string_lossy().into_owned());
            }
            match dir.parent() {
                Some(parent) if parent != dir => dir = parent,
                _ => break,
            }
        }
    }
    None
}

fn skip_tokens() -> &'static [&'static str] {
    &["|", " ", "[UNK]", "[PAD]", "<s>", "</s>"]
}

fn ipa_to_arpabet_map() -> &'static HashMap<&'static str, (&'static str, &'static str)> {
    static MAP: OnceLock<HashMap<&str, (&str, &str)>> = OnceLock::new();
    MAP.get_or_init(|| {
        // (ipa_input) → (arpabet_symbol_lowercase, display_ipa)
        // Longest keys first in multi-char composites — iteration order
        // doesn't matter for HashMap, but the sidecar emits single tokens.
        HashMap::from([
            // --- vowels ---
            ("ɑ", ("aa", "ɑ")),
            ("ɑː", ("aa", "ɑː")),
            ("æ", ("ae", "æ")),
            ("ə", ("ax", "ə")),
            ("əː", ("ax", "əː")),
            ("ɛ", ("eh", "ɛ")),
            ("ɛː", ("eh", "ɛː")),
            ("ɜ", ("er", "ɜ")),
            ("ɜː", ("er", "ɜː")),
            ("ɝ", ("er", "ɝ")),
            ("ɪ", ("ih", "ɪ")),
            ("i", ("iy", "i")),
            ("iː", ("iy", "iː")),
            ("ʊ", ("uh", "ʊ")),
            ("u", ("uw", "u")),
            ("uː", ("uw", "uː")),
            ("ʌ", ("ah", "ʌ")),
            ("ɔ", ("ao", "ɔ")),
            ("ɔː", ("ao", "ɔː")),
            ("ɒ", ("aa", "ɒ")),
            ("ɒː", ("aa", "ɒː")),
            ("ɚ", ("er", "ɚ")),
            // --- diphthongs ---
            ("aʊ", ("aw", "aʊ")),
            ("aɪ", ("ay", "aɪ")),
            ("ɔɪ", ("oy", "ɔɪ")),
            ("oɪ", ("oy", "oɪ")),
            ("eɪ", ("ey", "eɪ")),
            ("oʊ", ("ow", "oʊ")),
            ("əʊ", ("ow", "əʊ")),
            // --- consonants ---
            ("b", ("b", "b")),
            ("d", ("d", "d")),
            ("ð", ("dh", "ð")),
            ("ɾ", ("dx", "ɾ")),
            ("f", ("f", "f")),
            ("g", ("g", "g")),
            ("ɡ", ("g", "ɡ")),
            ("h", ("hh", "h")),
            ("k", ("k", "k")),
            ("l", ("l", "l")),
            ("m", ("m", "m")),
            ("n", ("n", "n")),
            ("ŋ", ("ng", "ŋ")),
            ("p", ("p", "p")),
            ("ɹ", ("r", "ɹ")),
            ("r", ("r", "r")),
            ("s", ("s", "s")),
            ("ʃ", ("sh", "ʃ")),
            ("t", ("t", "t")),
            ("θ", ("th", "θ")),
            ("v", ("v", "v")),
            ("w", ("w", "w")),
            ("j", ("y", "j")),
            ("z", ("z", "z")),
            ("ʒ", ("zh", "ʒ")),
            ("ʔ", ("q", "ʔ")),
            // --- affricates (espeak composites) ---
            ("ʧ", ("ch", "tʃ")),
            ("ʤ", ("jh", "dʒ")),
            ("tʃ", ("ch", "tʃ")),
            ("dʒ", ("jh", "dʒ")),
            // --- espeak-specific ---
            ("ᵻ", ("ih", "ɪ")),
            ("ɐ", ("ah", "ʌ")),
            ("əl", ("el", "əl")),
            // --- rhotic composites ---
            ("ɑːɹ", ("aa", "ɑːɹ")),
            ("ɔːɹ", ("ao", "ɔːɹ")),
        ])
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_common_ipa_vowels_to_arpabet() {
        let map = ipa_to_arpabet_map();
        let (arpabet, display) = map_ipa_phone("ə", map);
        assert_eq!(arpabet, "AX");
        assert_eq!(display, "ə");
    }

    #[test]
    fn maps_flap_to_dx() {
        let map = ipa_to_arpabet_map();
        let (arpabet, display) = map_ipa_phone("ɾ", map);
        assert_eq!(arpabet, "DX");
        assert_eq!(display, "ɾ");
    }

    #[test]
    fn maps_espeak_specific_symbols() {
        let map = ipa_to_arpabet_map();
        let (arpabet, _) = map_ipa_phone("ᵻ", map);
        assert_eq!(arpabet, "IH");
        let (arpabet, _) = map_ipa_phone("ɐ", map);
        assert_eq!(arpabet, "AH");
    }

    #[test]
    fn unknown_ipa_passes_through_uppercased() {
        let map = ipa_to_arpabet_map();
        let (arpabet, display) = map_ipa_phone("x̃", map);
        assert_eq!(arpabet, "X̃");
        assert_eq!(display, "x̃");
    }

    #[test]
    fn skip_tokens_are_filtered() {
        let skip = skip_tokens();
        assert!(skip.contains(&"|"));
        assert!(skip.contains(&"[PAD]"));
        assert!(!skip.contains(&"ə"));
    }
}
