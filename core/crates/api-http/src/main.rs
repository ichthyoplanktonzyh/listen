use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use api_http::{
    API_VERSION, ApiState, CONTRACT_VERSION, KeychainSecretStore, SyntaxCapabilityManager, router,
};
use application::AppServices;
use application::now_ms;
use embedding_provider::ManagedFastEmbedProvider;
use local_runtime::SpeechSynthesisManager;
use persistence_sqlite::SqliteRepository;
use rand::Rng;
use syntactic_provider::{PythonSyntacticKind, PythonSyntacticProvider};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Installed before anything else: the parent learns our pid the moment it
    // spawns us, so a stop request can arrive long before the server is up.
    // Registering the handler lazily would let those early signals fall through
    // to the default action and kill us instead of shutting us down.
    let interrupt = Interrupt::install()?;
    // Capture the parent identity before any heavyweight initialization. The
    // parent is what the orphan watchdog watches, and an app that exits while
    // we are still starting up must still be detected: sampling the parent
    // later, after a slow startup under load, would already see pid 1 (we have
    // been reparented) and read the sidecar as having no parent to watch.
    let original_parent = original_parent_pid();
    tracing_subscriber::fmt()
        .json()
        .with_writer(std::io::stderr)
        .with_current_span(false)
        .with_span_list(false)
        .init();
    let database_path = database_path();
    if let Some(parent) = database_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let repository = Arc::new(SqliteRepository::open(&database_path)?);
    let semantic_embedding = Arc::new(ManagedFastEmbedProvider::new(semantic_embedding_root()));
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
    .with_corpus_index_repository(repository.clone())
    .with_learner_profile_repository(repository.clone())
    .with_llm_provider_profile_repository(repository.clone())
    .with_material_repository(repository.clone())
    .with_package_lifecycle_repository(repository.clone())
    .with_content_package_candidate_import_repository(repository.clone())
    .with_capability_attempt_repository(repository.clone())
    .with_coach_dashboard_repository(repository.clone())
    .with_difficulty_repository(repository.clone())
    .with_source_identity_repository(repository.clone());
    let services = services.with_semantic_embedding(repository.clone(), semantic_embedding.clone());
    let token = env::var("LLPLAYERNEXT_API_TOKEN").unwrap_or_else(|_| random_token());
    // Startup reconciliation: every capability attempt left running by a
    // previous process is honestly superseded (interrupted), so no capability
    // ever projects `generating` forever after a restart.
    match services
        .material_capability()
        .reconcile_running_attempts(now_ms())
    {
        Ok(0) => {}
        Ok(count) => tracing::info!(
            event = "capability_attempts.reconciled",
            count,
            "superseded running capability attempts from a previous process"
        ),
        Err(error) => {
            tracing::warn!(
                event = "capability_attempts.reconcile_failed",
                error = %error,
                "running capability attempts will be reconciled on the next startup"
            );
        }
    }
    let secret_store = Arc::new(KeychainSecretStore::new());
    let llm_cleanup = services
        .llm_providers()
        .recover_pending_secret_cleanups(secret_store.as_ref());
    if llm_cleanup.is_err() {
        tracing::warn!(
            event = "secret_cleanup.retry_deferred",
            "pending provider credential cleanup will be retried later"
        );
    }
    let mut state =
        ApiState::new(services, repository, token.clone()).with_secret_store(secret_store);
    let syntax_root = syntax_capability_root();
    let install_dir = syntax_root.join("spacy-3.8.13-en_core_web_sm-3.8.0");
    let syntax_provider = Arc::new(PythonSyntacticProvider::new(
        PythonSyntacticKind::Spacy,
        install_dir.join("venv/bin/python"),
        install_dir.join("syntax-sidecar.py"),
    ));
    let syntax_manager = SyntaxCapabilityManager::new(syntax_root, Some(syntax_provider.clone()));
    state = state.with_syntax_capability(syntax_manager.clone(), syntax_manager);
    state = state.with_speech_synthesis(SpeechSynthesisManager::system_default(
        speech_synthesis_cache_root(),
    ));
    state = state.with_semantic_embedding_manager(semantic_embedding);
    let app = router(state);
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
    let address = listener.local_addr()?;

    println!(
        "{}",
        serde_json::json!({
            "event": "api.started",
            "version": env!("CARGO_PKG_VERSION"),
            "runtime_version": env!("CARGO_PKG_VERSION"),
            "contract_version": CONTRACT_VERSION,
            "api_version": API_VERSION,
            "platform": env::consts::OS,
            "address": address.to_string(),
            "token": token,
            "database": database_path,
        })
    );
    let serve_result = axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal(interrupt, original_parent))
        .await;
    serve_result?;
    println!(
        "{}",
        serde_json::json!({
            "event": "api.stopped",
            "version": env!("CARGO_PKG_VERSION"),
            "runtime_version": env!("CARGO_PKG_VERSION"),
            "contract_version": CONTRACT_VERSION,
            "api_version": API_VERSION,
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
        home.join("Library/Application Support/listen/listen-coach.sqlite")
    }
    #[cfg(target_os = "windows")]
    {
        let local_app_data =
            PathBuf::from(env::var_os("LOCALAPPDATA").expect("LOCALAPPDATA is required"));
        local_app_data.join("listen/listen-coach.sqlite")
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        let data_home = PathBuf::from(env::var_os("XDG_DATA_HOME").unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME is required"))
                .join(".local/share")
                .into_os_string()
        }));
        data_home.join("listen/listen-coach.sqlite")
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

fn semantic_embedding_root() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        PathBuf::from(env::var_os("HOME").expect("HOME is required"))
            .join("Library/Application Support/listen/semantic-embedding")
    }
    #[cfg(target_os = "windows")]
    {
        PathBuf::from(env::var_os("LOCALAPPDATA").expect("LOCALAPPDATA is required"))
            .join("listen/semantic-embedding")
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        PathBuf::from(env::var_os("XDG_DATA_HOME").unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME is required"))
                .join(".local/share")
                .into_os_string()
        }))
        .join("listen/semantic-embedding")
    }
}

async fn shutdown_signal(mut interrupt: Interrupt, original_parent: i32) {
    tokio::select! {
        _ = interrupt.recv() => {}
        _ = orphaned(original_parent) => {}
    }
    // Whichever of the two asked us to stop, the graceful drain must not be
    // able to hang the process: a stalled connection outliving the desktop app
    // is the very leak this shutdown path exists to prevent.
    tokio::spawn(async {
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        std::process::exit(0);
    });
}

/// The stop request the desktop app sends from `dispose()`.
///
/// Registered eagerly rather than awaited lazily so the handler exists for the
/// whole process lifetime; see the call site in `main`.
#[cfg(unix)]
struct Interrupt(tokio::signal::unix::Signal);

#[cfg(unix)]
impl Interrupt {
    fn install() -> std::io::Result<Self> {
        Ok(Self(tokio::signal::unix::signal(
            tokio::signal::unix::SignalKind::interrupt(),
        )?))
    }

    async fn recv(&mut self) {
        self.0.recv().await;
    }
}

#[cfg(not(unix))]
struct Interrupt;

#[cfg(not(unix))]
impl Interrupt {
    fn install() -> std::io::Result<Self> {
        Ok(Self)
    }

    async fn recv(&mut self) {
        let _ = tokio::signal::ctrl_c().await;
    }
}

/// Resolves once the process that spawned this sidecar has exited.
///
/// The desktop app closes the sidecar from `dispose()`, which is best-effort:
/// a crash, a force quit, or any SIGKILL never runs it, and the sidecar is
/// then reparented to pid 1 and lingers — leaking a process, a database
/// connection and a port per session. Polling the parent pid catches every one
/// of those exits, including the ones no in-app teardown can observe.
///
/// The original parent identity is captured at the very start of `main`,
/// before heavyweight startup, and passed in here. Comparing the current
/// parent against that snapshot means a sidecar that was legitimately
/// launched with no parent to watch (already reparented, e.g. daemonized) is
/// never mistaken for an orphan, while a parent that exits while the sidecar
/// is still starting up is still detected.
#[cfg(unix)]
async fn orphaned(original_parent: i32) {
    if original_parent <= 1 {
        return std::future::pending().await;
    }
    loop {
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;
        // SAFETY: `getppid` is always safe to call and cannot fail.
        if unsafe { libc::getppid() } != original_parent {
            return;
        }
    }
}

#[cfg(not(unix))]
async fn orphaned(_original_parent: i32) {
    std::future::pending().await
}

/// The identity of the process that launched this sidecar.
///
/// Read immediately, before heavyweight initialization gives the parent a
/// chance to exit and leave us reparented to pid 1.
#[cfg(unix)]
fn original_parent_pid() -> i32 {
    // SAFETY: `getppid` is always safe to call and cannot fail.
    unsafe { libc::getppid() }
}

#[cfg(not(unix))]
fn original_parent_pid() -> i32 {
    0
}
