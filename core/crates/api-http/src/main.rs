use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use api_http::{ApiState, KeychainSecretStore, SyntaxCapabilityManager, router};
use application::AppServices;
use local_runtime::SpeechSynthesisManager;
use persistence_sqlite::SqliteRepository;
use rand::Rng;
use syntactic_provider::{PythonSyntacticKind, PythonSyntacticProvider};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let database_path = database_path();
    if let Some(parent) = database_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let repository = Arc::new(SqliteRepository::open(&database_path)?);
    let services = AppServices::new(
        repository.clone(),
        repository.clone(),
        repository.clone(),
        repository.clone(),
        repository.clone(),
        repository.clone(),
        repository.clone(),
        repository.clone(),
    )
    .with_learning_loop_repositories(
        repository.clone(),
        repository.clone(),
        repository.clone(),
        repository.clone(),
    )
    .with_recording_repository(repository.clone())
    .with_difficulty_repository(repository.clone())
    .with_corpus_index_repository(repository.clone())
    .with_learner_profile_repository(repository.clone())
    .with_reading_position_repository(repository.clone())
    .with_semantic_task_repository(repository.clone())
    .with_production_corpus_repository(repository.clone())
    .with_llm_provider_profile_repository(repository.clone());
    let services = services.with_coach_dashboard_repository(repository.clone());
    let token = env::var("LLPLAYERNEXT_API_TOKEN").unwrap_or_else(|_| random_token());
    let mut state = ApiState::new(services, repository, token.clone())
        .with_secret_store(Arc::new(KeychainSecretStore::new()));
    let syntax_root = syntax_capability_root();
    let install_dir = syntax_root.join("spacy-3.8.13-en_core_web_sm-3.8.0");
    let syntax_provider = Arc::new(PythonSyntacticProvider::new(
        PythonSyntacticKind::Spacy,
        install_dir.join("venv/bin/python"),
        install_dir.join("syntax-sidecar.py"),
    ));
    let syntax_manager = SyntaxCapabilityManager::new(syntax_root, Some(syntax_provider.clone()));
    state = state.with_syntax_capability(syntax_manager, syntax_provider);
    state = state.with_speech_synthesis(SpeechSynthesisManager::system_default(
        speech_synthesis_cache_root(),
    ));
    let app = router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let address = listener.local_addr()?;

    println!(
        "{}",
        serde_json::json!({
            "event": "api.started",
            "version": env!("CARGO_PKG_VERSION"),
            "platform": env::consts::OS,
            "address": address.to_string(),
            "token": token,
            "database": database_path
        })
    );
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    println!(
        "{}",
        serde_json::json!({
            "event": "api.stopped",
            "version": env!("CARGO_PKG_VERSION"),
            "platform": env::consts::OS
        })
    );
    Ok(())
}

fn random_token() -> String {
    let bytes: [u8; 32] = rand::rng().random();
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn database_path() -> PathBuf {
    if let Some(path) = env::var_os("LLPLAYERNEXT_DB") {
        return path.into();
    }
    #[cfg(target_os = "macos")]
    {
        let home = PathBuf::from(env::var_os("HOME").expect("HOME is required"));
        let current = home.join("Library/Application Support/listen/listen.sqlite");
        let legacy = home.join("Library/Application Support/LLPlayerNext/llplayernext.sqlite");
        if current.exists() || !legacy.exists() {
            current
        } else {
            legacy
        }
    }
    #[cfg(target_os = "windows")]
    {
        let local_app_data =
            PathBuf::from(env::var_os("LOCALAPPDATA").expect("LOCALAPPDATA is required"));
        let current = local_app_data.join("listen/listen.sqlite");
        let legacy = local_app_data.join("LLPlayerNext/llplayernext.sqlite");
        if current.exists() || !legacy.exists() {
            current
        } else {
            legacy
        }
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        let data_home = PathBuf::from(env::var_os("XDG_DATA_HOME").unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME is required"))
                .join(".local/share")
                .into_os_string()
        }));
        let current = data_home.join("listen/listen.sqlite");
        let legacy = data_home.join("llplayernext/llplayernext.sqlite");
        if current.exists() || !legacy.exists() {
            current
        } else {
            legacy
        }
    }
}

fn syntax_capability_root() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        PathBuf::from(env::var_os("HOME").expect("HOME is required"))
            .join("Library/Application Support/listen/syntax")
    }
    #[cfg(target_os = "windows")]
    {
        PathBuf::from(env::var_os("LOCALAPPDATA").expect("LOCALAPPDATA is required"))
            .join("listen/syntax")
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        PathBuf::from(env::var_os("XDG_DATA_HOME").unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME is required"))
                .join(".local/share")
                .into_os_string()
        }))
        .join("listen/syntax")
    }
}

fn speech_synthesis_cache_root() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        PathBuf::from(env::var_os("HOME").expect("HOME is required"))
            .join("Library/Caches/listen/speech-synthesis")
    }
    #[cfg(target_os = "windows")]
    {
        PathBuf::from(env::var_os("LOCALAPPDATA").expect("LOCALAPPDATA is required"))
            .join("listen/cache/speech-synthesis")
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        PathBuf::from(env::var_os("XDG_CACHE_HOME").unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME is required"))
                .join(".cache")
                .into_os_string()
        }))
        .join("listen/speech-synthesis")
    }
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}
