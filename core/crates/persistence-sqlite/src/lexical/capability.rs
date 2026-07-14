//! Capability profile/state read+write helpers for lexical assets.
//! Split out of `lexical.rs` (mechanical decomposition).

use application::ApplicationError;
use domain::*;
use rusqlite::{OptionalExtension, params};

use crate::{from_json, json, repo};

pub(super) fn sense_key(sense_id: Option<&LexicalSenseId>) -> &str {
    sense_id.map_or("", LexicalSenseId::as_str)
}

pub(super) fn read_capability_profile(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
) -> Result<Option<LexicalCapabilityProfile>, ApplicationError> {
    let exists = conn
        .query_row(
            "SELECT 1 FROM lexical_entries WHERE id=?1",
            [lexical_entry_id.as_str()],
            |_| Ok(()),
        )
        .optional()
        .map_err(repo)?
        .is_some();
    if !exists {
        return Ok(None);
    }
    let mut profile = LexicalCapabilityProfile::unassessed(lexical_entry_id.clone());
    profile.sense_id = sense_id.cloned();
    let mut statement = conn
        .prepare(
            "SELECT capability,projection_json,override_json
             FROM lexical_capability_states
             WHERE lexical_entry_id=?1 AND sense_id=?2",
        )
        .map_err(repo)?;
    let rows = statement
        .query_map(
            params![lexical_entry_id.as_str(), sense_key(sense_id)],
            |row| {
                Ok((
                    from_json::<LexicalCapability>(&row.get::<_, String>(0)?)?,
                    row.get::<_, Option<String>>(1)?
                        .map(|value| from_json(&value))
                        .transpose()?,
                    row.get::<_, Option<String>>(2)?
                        .map(|value| from_json(&value))
                        .transpose()?,
                ))
            },
        )
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)?;
    for (capability, projection, user_override) in rows {
        *profile.dimension_mut(capability) = CapabilityDimensionState {
            projection,
            user_override,
        };
    }
    Ok(Some(profile))
}

pub(super) fn read_capability_state(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
    capability: LexicalCapability,
) -> Result<Option<CapabilityDimensionState>, ApplicationError> {
    conn.query_row(
        "SELECT projection_json,override_json FROM lexical_capability_states
         WHERE lexical_entry_id=?1 AND sense_id=?2 AND capability=?3",
        params![
            lexical_entry_id.as_str(),
            sense_key(sense_id),
            json(&capability)?
        ],
        |row| {
            Ok(CapabilityDimensionState {
                projection: row
                    .get::<_, Option<String>>(0)?
                    .map(|value| from_json(&value))
                    .transpose()?,
                user_override: row
                    .get::<_, Option<String>>(1)?
                    .map(|value| from_json(&value))
                    .transpose()?,
            })
        },
    )
    .optional()
    .map_err(repo)
}

pub(super) fn write_capability_state(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
    capability: LexicalCapability,
    state: &CapabilityDimensionState,
    changed_at_ms: u64,
) -> Result<(), ApplicationError> {
    if state.projection.is_none() && state.user_override.is_none() {
        conn.execute(
            "DELETE FROM lexical_capability_states
             WHERE lexical_entry_id=?1 AND sense_id=?2 AND capability=?3",
            params![
                lexical_entry_id.as_str(),
                sense_key(sense_id),
                json(&capability)?
            ],
        )
        .map_err(repo)?;
        return Ok(());
    }
    conn.execute(
        "INSERT INTO lexical_capability_states
         (lexical_entry_id,sense_id,capability,projection_json,override_json,updated_at_ms)
         VALUES (?1,?2,?3,?4,?5,?6)
         ON CONFLICT(lexical_entry_id,sense_id,capability) DO UPDATE SET
           projection_json=excluded.projection_json,
           override_json=excluded.override_json,
           updated_at_ms=excluded.updated_at_ms",
        params![
            lexical_entry_id.as_str(),
            sense_key(sense_id),
            json(&capability)?,
            state.projection.as_ref().map(json).transpose()?,
            state.user_override.as_ref().map(json).transpose()?,
            changed_at_ms,
        ],
    )
    .map_err(repo)?;
    Ok(())
}

#[allow(clippy::too_many_arguments)]

pub(super) fn write_capability_history(
    conn: &rusqlite::Connection,
    lexical_entry_id: &LexicalEntryId,
    sense_id: Option<&LexicalSenseId>,
    capability: LexicalCapability,
    previous_state: &CapabilityDimensionState,
    new_state: &CapabilityDimensionState,
    change_kind: CapabilityStateChangeKind,
    changed_at_ms: u64,
) -> Result<(), ApplicationError> {
    let fingerprint = format!(
        "{}:{}:{:?}:{:?}:{}:{}",
        lexical_entry_id.as_str(),
        sense_key(sense_id),
        capability,
        change_kind,
        changed_at_ms,
        json(new_state)?
    );
    let id =
        LexicalCapabilityHistoryId::from_fingerprint("lexical-capability-history", &fingerprint);
    conn.execute(
        "INSERT OR IGNORE INTO lexical_capability_history
         (id,lexical_entry_id,sense_id,capability,previous_state_json,new_state_json,
          change_kind,changed_at_ms)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
        params![
            id.as_str(),
            lexical_entry_id.as_str(),
            sense_key(sense_id),
            json(&capability)?,
            json(previous_state)?,
            json(new_state)?,
            json(&change_kind)?,
            changed_at_ms,
        ],
    )
    .map_err(repo)?;
    Ok(())
}

pub(super) fn capability_history_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<LexicalCapabilityHistory> {
    let sense_id = row.get::<_, String>(2)?;
    Ok(LexicalCapabilityHistory {
        id: LexicalCapabilityHistoryId::parse(row.get::<_, String>(0)?)
            .map_err(crate::domain_sql)?,
        lexical_entry_id: LexicalEntryId::parse(row.get::<_, String>(1)?)
            .map_err(crate::domain_sql)?,
        sense_id: if sense_id.is_empty() {
            None
        } else {
            Some(LexicalSenseId::parse(sense_id).map_err(crate::domain_sql)?)
        },
        capability: from_json(&row.get::<_, String>(3)?)?,
        previous_state: from_json(&row.get::<_, String>(4)?)?,
        new_state: from_json(&row.get::<_, String>(5)?)?,
        change_kind: from_json(&row.get::<_, String>(6)?)?,
        changed_at_ms: row.get(7)?,
    })
}

pub(super) fn merge_capability_dimension(
    local: &CapabilityDimensionState,
    imported: &CapabilityDimensionState,
) -> CapabilityDimensionState {
    let projection = match (&local.projection, &imported.projection) {
        (None, p) => p.clone(),
        (p, None) => p.clone(),
        (Some(l), Some(i)) => {
            if i.updated_at_ms > l.updated_at_ms {
                Some(i.clone())
            } else {
                Some(l.clone())
            }
        }
    };
    let user_override = match (&local.user_override, &imported.user_override) {
        (None, o) => o.clone(),
        (o @ Some(_), None) => o.clone(),
        (Some(l), Some(i)) => {
            if i.updated_at_ms > l.updated_at_ms {
                Some(i.clone())
            } else {
                Some(l.clone())
            }
        }
    };
    CapabilityDimensionState {
        projection,
        user_override,
    }
}
