use std::env;
use std::path::PathBuf;
use std::time::Instant;

use fastembed::similarity::cosine_similarity;
use fastembed::{EmbeddingModel, TextEmbedding, TextInitOptions};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let cache_dir = env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(".fastembed_cache"));
    let started = Instant::now();
    let mut model = TextEmbedding::try_new(
        TextInitOptions::new(EmbeddingModel::AllMiniLML6V2)
            .with_cache_dir(cache_dir)
            .with_show_download_progress(true)
            .with_intra_threads(4),
    )?;
    let load_ms = started.elapsed().as_millis();

    let texts = vec![
        "A very large house stood on the hill.",
        "An enormous home was built on the hillside.",
        "I made coffee before work.",
        "The weather forecast predicts heavy rain.",
        "big",
        "enormous",
        "coffee",
    ];
    let embedded_at = Instant::now();
    let embeddings = model.embed(texts, Some(4))?;
    let embed_ms = embedded_at.elapsed().as_millis();
    let dimension = embeddings.first().map_or(0, Vec::len);

    println!("load_ms={load_ms}");
    println!("embed_ms={embed_ms}");
    println!("count={}", embeddings.len());
    println!("dimension={dimension}");
    println!(
        "large_enormous={:.6}",
        cosine_similarity(&embeddings[0], &embeddings[1])
    );
    println!(
        "large_coffee={:.6}",
        cosine_similarity(&embeddings[0], &embeddings[2])
    );
    println!(
        "large_weather={:.6}",
        cosine_similarity(&embeddings[0], &embeddings[3])
    );
    println!(
        "big_enormous={:.6}",
        cosine_similarity(&embeddings[4], &embeddings[5])
    );
    println!(
        "big_coffee={:.6}",
        cosine_similarity(&embeddings[4], &embeddings[6])
    );
    Ok(())
}
