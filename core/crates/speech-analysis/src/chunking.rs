//! Stable chunk-analysis capability interface.
//!
//! Detection and partition implementations cooperate internally, while callers
//! learn one product capability instead of three implementation file layouts.

pub use crate::chunk_detection::{
    BoundaryMarker, ChunkBoundary, ChunkDetectionConfig, ChunkDetectionResult, ChunkGroup,
    CombinedChunkGroup, CombinedChunkResult, annotate_acoustic_with_text, combine_chunks,
    compute_raw_gaps, detect_chunk_boundaries, detect_chunk_boundaries_default,
    detect_chunk_boundaries_for_track,
};
pub use crate::chunk_partition::{
    BoundaryDiagnostic, ChunkBoundaryEvidence, ChunkBoundarySource, ChunkPartitionConfig,
    ChunkTimingQuality, DisplayChunk, DisplayChunkBoundary, PARTITIONER_ID, PARTITIONER_VERSION,
    PunctuationReliability, SentenceChunkDiagnostics, SentenceChunkPartition, partition_sentence,
    partition_sentence_with_all_evidence, partition_sentence_with_diagnostics,
    partition_sentence_with_rich_acoustic_evidence,
};
pub use crate::learned_prosodic_provider::{LearnedProsodicProviderInfo, embedded_provider_info};
pub use crate::text_chunk_detection::{
    PhraseSpan, SourceCounts, SpanSource, TextChunkBoundary, TextChunkDetectionResult,
    TextChunkEvidence, TextChunkGroup, detect_text_chunks,
};
