mod connection;
mod dictionary;
mod lexical;
mod media;
mod migrations;
mod phonetic_analysis;
mod progress;
mod subtitles;
mod support;
mod transcription;
mod vocabulary;

pub use connection::SqliteRepository;
pub use migrations::{MIGRATION_VERSION, migrate};
pub use support::PersistenceError;
pub(crate) use support::{domain_sql, from_json, json, repo};

#[cfg(test)]
mod tests;
