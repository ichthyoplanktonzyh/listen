use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use api_http::{ApiState, router};
use application::AppServices;
use persistence_sqlite::SqliteRepository;
use rand::Rng;

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
    );
    let token = env::var("LLPLAYERNEXT_API_TOKEN").unwrap_or_else(|_| random_token());
    let app = router(ApiState::new(services, repository, token.clone()));
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
        PathBuf::from(env::var_os("HOME").expect("HOME is required"))
            .join("Library/Application Support/LLPlayerNext/llplayernext.sqlite")
    }
    #[cfg(target_os = "windows")]
    {
        PathBuf::from(env::var_os("LOCALAPPDATA").expect("LOCALAPPDATA is required"))
            .join("LLPlayerNext/llplayernext.sqlite")
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        PathBuf::from(env::var_os("XDG_DATA_HOME").unwrap_or_else(|| {
            PathBuf::from(env::var_os("HOME").expect("HOME is required"))
                .join(".local/share")
                .into_os_string()
        }))
        .join("llplayernext/llplayernext.sqlite")
    }
}

async fn shutdown_signal() {
    let _ = tokio::signal::ctrl_c().await;
}
