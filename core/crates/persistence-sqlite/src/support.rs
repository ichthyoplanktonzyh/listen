use application::ApplicationError;
use domain::DomainError;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum PersistenceError {
    #[error(transparent)]
    Sqlite(#[from] rusqlite::Error),
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(
        "database schema version {found} is unsupported; this build requires a fresh listening-coach store (schema version {expected})"
    )]
    UnsupportedSchemaVersion { found: u32, expected: u32 },
    #[error("database has no schema version but already contains data; refusing to modify it")]
    NonEmptyUnversionedDatabase,
}

pub(crate) fn json<T: serde::Serialize + ?Sized>(value: &T) -> Result<String, ApplicationError> {
    serde_json::to_string(value).map_err(|e| ApplicationError::Repository(e.to_string()))
}

pub(crate) fn from_json<T: serde::de::DeserializeOwned>(value: &str) -> rusqlite::Result<T> {
    serde_json::from_str(value).map_err(|e| {
        rusqlite::Error::FromSqlConversionFailure(
            value.len(),
            rusqlite::types::Type::Text,
            Box::new(e),
        )
    })
}

pub(crate) fn domain_sql(error: DomainError) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(error))
}

pub(crate) fn repo(error: rusqlite::Error) -> ApplicationError {
    ApplicationError::Repository(error.to_string())
}
