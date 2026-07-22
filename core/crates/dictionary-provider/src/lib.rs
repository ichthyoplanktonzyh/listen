// Dictionary/pronunciation providers, one module per upstream resource.
// lib.rs only assembles and re-exports (mechanical decomposition).

mod cedict;
mod ecdict;
mod edict;
mod free_dictionary;
mod support;
#[cfg(test)]
mod tests;

pub use cedict::{ChineseDictionaryProvider, ChinesePronunciationProvider};
pub use ecdict::EcdictProvider;
pub use edict::JapaneseDictionaryProvider;
pub use free_dictionary::FreeDictionaryProvider;
