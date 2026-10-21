mod anki;
mod background_jobs;
mod capability_attempts;
mod connection;
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
mod package_lifecycle;
mod personal_expression;
mod phonetic_analysis;
mod production_corpus;
mod progress;
mod reading;
mod recording;
mod secret_cleanup;
mod semantic_embedding;
mod semantic_task;
mod source_identity;
mod subtitles;
mod support;
mod transcription;

pub use connection::SqliteRepository;
pub use migrations::{MIGRATION_VERSION, migrate};
pub use support::PersistenceError;
pub(crate) use support::{domain_sql, from_json, json, repo};

#[cfg(test)]
mod tests;
