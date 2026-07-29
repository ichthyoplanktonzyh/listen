//! Shared local-machine primitives used by multiple runtime workflows.
//!
//! Tool discovery and audio extraction policy belong to the runtime as a
//! whole. Keeping them here prevents one workflow from reaching into another
//! coordinator's implementation.

use std::path::{Path, PathBuf};

use application::ApplicationError;
use sha2::{Digest, Sha256};

pub(crate) fn support_dir() -> PathBuf {
    std::env::var_os("LLPLAYERNEXT_SUPPORT_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").expect("HOME is required"))
                .join("Library/Application Support/LLPlayerNext")
        })
}

pub(crate) fn ffmpeg_wav_args(
    media_path: String,
    audio_track: Option<u32>,
    out_wav: &Path,
) -> Vec<String> {
    let mut args = vec!["-y".into(), "-i".into(), media_path, "-vn".into()];
    if let Some(track) = audio_track {
        args.extend(["-map".into(), format!("0:a:{track}")]);
    }
    args.extend([
        "-ac".into(),
        "1".into(),
        "-ar".into(),
        "16000".into(),
        "-c:a".into(),
        "pcm_s16le".into(),
        out_wav.to_string_lossy().into_owned(),
    ]);
    args
}

pub(crate) fn resolve_tool(env_name: &str, name: &str) -> Option<PathBuf> {
    if let Some(path) = std::env::var_os(env_name)
        .map(PathBuf::from)
        .filter(|path| path.is_file())
    {
        return Some(path);
    }
    let executable = std::env::current_exe().ok()?;
    resolve_bundled_tool(name, &executable, &std::env::current_dir().ok()?)
}

pub(crate) fn resolve_forced_align_command() -> Option<(PathBuf, PathBuf)> {
    let research_root = std::env::var_os("LLPLAYERNEXT_FA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").expect("HOME is required"))
                .join("Library/Caches/LLPlayerNext/research/forced-align")
        });
    let python = research_root.join("venv/bin/python");
    if !python.is_file() {
        return None;
    }
    let script = resolve_forced_align_script()?;
    Some((python, script))
}

fn resolve_forced_align_script() -> Option<PathBuf> {
    if let Some(path) = std::env::var_os("LLPLAYERNEXT_FA_SCRIPT")
        .map(PathBuf::from)
        .filter(|path| path.is_file())
    {
        return Some(path);
    }
    let mut roots = Vec::new();
    if let Ok(current_dir) = std::env::current_dir() {
        roots.push(current_dir);
    }
    if let Ok(executable) = std::env::current_exe()
        && let Some(parent) = executable.parent()
    {
        roots.push(parent.to_path_buf());
    }
    for root in roots {
        let mut directory = Some(root.as_path());
        while let Some(path) = directory {
            let candidate = path.join("scripts/forced-align/align-cli.py");
            if candidate.is_file() {
                return Some(candidate);
            }
            directory = path.parent();
        }
    }
    None
}

pub(crate) fn resolve_bundled_tool(
    name: &str,
    executable: &Path,
    current_dir: &Path,
) -> Option<PathBuf> {
    let executable_parent = executable.parent()?;
    let mut candidates = vec![
        executable_parent.join(name),
        executable_parent.join("../Resources/runtime").join(name),
        PathBuf::from(format!("/opt/homebrew/bin/{name}")),
        PathBuf::from(format!("/usr/local/bin/{name}")),
    ];
    candidates.extend(runtime_candidates_from(executable_parent, name));
    candidates.extend(runtime_candidates_from(current_dir, name));
    candidates.into_iter().find(|path| path.is_file())
}

fn runtime_candidates_from(start: &Path, name: &str) -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    let mut directory = start;
    loop {
        candidates.push(directory.join("third_party/runtime/macos-arm64").join(name));
        let Some(parent) = directory.parent() else {
            break;
        };
        if parent == directory {
            break;
        }
        directory = parent;
    }
    candidates
}

pub(crate) fn file_id(value: &str) -> String {
    value
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect()
}

pub(crate) fn io_error(error: std::io::Error) -> ApplicationError {
    ApplicationError::Repository(error.to_string())
}

pub(crate) fn hash_file(path: &Path) -> Result<String, ApplicationError> {
    use std::io::Read;
    let mut file = std::fs::File::open(path)
        .map_err(|error| ApplicationError::Repository(error.to_string()))?;
    let mut digest = Sha256::new();
    let mut buffer = [0_u8; 1024 * 1024];
    loop {
        let read = file
            .read(&mut buffer)
            .map_err(|error| ApplicationError::Repository(error.to_string()))?;
        if read == 0 {
            break;
        }
        digest.update(&buffer[..read]);
    }
    Ok(hex::encode(digest.finalize()))
}
