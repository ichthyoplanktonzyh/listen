mod coach_dashboard;
mod connection;
mod content_fit;
mod corpus;
mod dictionary;
mod learner_profile;
mod learning_loop;
mod lexical;
mod media;
mod migrations;
mod phonetic_analysis;
mod progress;
mod recording;
mod semantic_task;
mod subtitles;
mod support;
mod transcription;

pub use connection::SqliteRepository;
#[cfg(test)]
pub(crate) use migrations::backfill_legacy_observations;
pub use migrations::{MIGRATION_VERSION, migrate};
pub use support::PersistenceError;
pub(crate) use support::{domain_sql, from_json, json, repo};

#[cfg(test)]
mod tests;
