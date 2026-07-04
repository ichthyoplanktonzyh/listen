use rusqlite::Connection;

use super::PersistenceError;

pub const MIGRATION_VERSION: u32 = 18;

pub fn migrate(connection: &Connection) -> Result<(), PersistenceError> {
    connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    let current: u32 = connection.query_row("PRAGMA user_version", [], |r| r.get(0))?;
    if current < 1 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0001_media.sql"))?;
        tx.pragma_update(None, "user_version", 1)?;
        tx.commit()?;
    }
    if current < 2 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0002_learning.sql"))?;
        tx.pragma_update(None, "user_version", 2)?;
        tx.commit()?;
    }
    if current < 3 {
        connection.execute_batch("PRAGMA foreign_keys = OFF;")?;
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0003_subtitle_identity.sql"))?;
        tx.pragma_update(None, "user_version", 3)?;
        tx.commit()?;
        connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    }
    if current < 4 {
        connection.execute_batch("PRAGMA foreign_keys = OFF;")?;
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0004_vocabulary_assets.sql"))?;
        tx.pragma_update(None, "user_version", 4)?;
        tx.commit()?;
        connection.execute_batch("PRAGMA foreign_keys = ON;")?;
    }
    if current < 5 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0005_learning_experience.sql"))?;
        tx.pragma_update(None, "user_version", 5)?;
        tx.commit()?;
    }
    if current < 6 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0006_transcription.sql"))?;
        tx.pragma_update(None, "user_version", 6)?;
        tx.commit()?;
    }
    if current < 7 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0007_lexical_entries.sql"))?;
        tx.pragma_update(None, "user_version", 7)?;
        tx.commit()?;
    }
    if current < 8 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0008_pronunciation.sql"))?;
        tx.pragma_update(None, "user_version", 8)?;
        tx.commit()?;
    }
    if current < 9 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0009_phonetic_analysis.sql"))?;
        tx.pragma_update(None, "user_version", 9)?;
        tx.commit()?;
    }
    if current < 10 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0010_word_timelines.sql"))?;
        tx.pragma_update(None, "user_version", 10)?;
        tx.commit()?;
    }
    if current < 11 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0011_lltimeline_resources.sql"))?;
        tx.pragma_update(None, "user_version", 11)?;
        tx.commit()?;
    }
    if current < 12 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0012_subtitle_resource_lifecycle.sql"
        ))?;
        tx.pragma_update(None, "user_version", 12)?;
        tx.commit()?;
    }
    if current < 13 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0013_chunk_timelines.sql"))?;
        tx.pragma_update(None, "user_version", 13)?;
        tx.commit()?;
    }
    if current < 14 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0014_phone_timelines.sql"))?;
        tx.pragma_update(None, "user_version", 14)?;
        tx.commit()?;
    }
    if current < 15 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0015_learning_loop.sql"))?;
        tx.pragma_update(None, "user_version", 15)?;
        tx.commit()?;
    }
    if current < 16 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0016_destructive_lexical_reset.sql"
        ))?;
        tx.pragma_update(None, "user_version", 16)?;
        tx.commit()?;
    }
    if current < 17 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!(
            "../migrations/0017_drop_learning_resources.sql"
        ))?;
        tx.pragma_update(None, "user_version", 17)?;
        tx.commit()?;
    }
    if current < 18 {
        let tx = connection.unchecked_transaction()?;
        tx.execute_batch(include_str!("../migrations/0018_listening_inbox.sql"))?;
        tx.pragma_update(None, "user_version", 18)?;
        tx.commit()?;
    }
    Ok(())
}
