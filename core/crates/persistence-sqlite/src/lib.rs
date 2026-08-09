mod anki;
mod background_jobs;
mod coach_dashboard;
mod connection;
mod content_fit;
mod corpus;
mod dictionary;
mod learner_profile;
mod learning_loop;
mod learning_material;
mod learning_preparation;
mod lexical;
mod llm_provider;
mod media;
mod migrations;
mod personal_expression;
mod phonetic_analysis;
mod production_corpus;
mod progress;
mod reading;
mod realtime_conversation;
mod recording;
mod secret_cleanup;
mod semantic_embedding;
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
