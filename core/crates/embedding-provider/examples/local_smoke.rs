use std::path::PathBuf;

use application::EmbeddingProvider;
use domain::EmbeddingPurpose;
use embedding_provider::ManagedFastEmbedProvider;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cache_dir = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .ok_or("usage: local_smoke <explicit-model-cache-dir>")?;
    let provider = ManagedFastEmbedProvider::new(cache_dir);
    provider.install().await?;
    let descriptor = provider.descriptor().ok_or("model did not become ready")?;
    let vectors = provider
        .embed(
            EmbeddingPurpose::Document,
            &["An enormous hall.".into(), "A very large room.".into()],
        )
        .await?;
    println!(
        "model={} revision={} dimension={} fingerprint={} vectors={}",
        descriptor.model_id,
        descriptor.model_version,
        descriptor.dimension,
        descriptor.model_fingerprint,
        vectors.len()
    );
    Ok(())
}
