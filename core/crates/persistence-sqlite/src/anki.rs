use std::collections::{BTreeMap, HashMap};
use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::Command;

use application::{
    AnkiExportFidelity, AnkiPackageExportRequest, AnkiPackageExportSummary,
    AnkiPackageImportRequest, AnkiPackageImportSummary, ApplicationError, ReviewChannel,
};
use domain::{
    PracticeAnchor, PracticeAnchorKind, ReviewAttempt, ReviewCardState, ReviewItem, ReviewItemId,
    ReviewItemStatus, ReviewSchedule, ReviewSource, ReviewSourceKind,
};
use rusqlite::{Connection, OpenFlags, OptionalExtension, params};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

use crate::{SqliteRepository, from_json, json as sql_json, repo};

const DAY_MS: u64 = 86_400_000;
const ANKI_SCHEMA: &str = r#"
CREATE TABLE col (
  id integer PRIMARY KEY, crt integer NOT NULL, mod integer NOT NULL,
  scm integer NOT NULL, ver integer NOT NULL, dty integer NOT NULL,
  usn integer NOT NULL, ls integer NOT NULL, conf text NOT NULL,
  models text NOT NULL, decks text NOT NULL, dconf text NOT NULL, tags text NOT NULL
);
CREATE TABLE notes (
  id integer PRIMARY KEY, guid text NOT NULL, mid integer NOT NULL,
  mod integer NOT NULL, usn integer NOT NULL, tags text NOT NULL,
  flds text NOT NULL, sfld integer NOT NULL, csum integer NOT NULL,
  flags integer NOT NULL, data text NOT NULL
);
CREATE TABLE cards (
  id integer PRIMARY KEY, nid integer NOT NULL, did integer NOT NULL,
  ord integer NOT NULL, mod integer NOT NULL, usn integer NOT NULL,
  type integer NOT NULL, queue integer NOT NULL, due integer NOT NULL,
  ivl integer NOT NULL, factor integer NOT NULL, reps integer NOT NULL,
  lapses integer NOT NULL, left integer NOT NULL, odue integer NOT NULL,
  odid integer NOT NULL, flags integer NOT NULL, data text NOT NULL
);
CREATE TABLE revlog (
  id integer PRIMARY KEY, cid integer NOT NULL, usn integer NOT NULL,
  ease integer NOT NULL, ivl integer NOT NULL, lastIvl integer NOT NULL,
  factor integer NOT NULL, time integer NOT NULL, type integer NOT NULL
);
CREATE TABLE graves (usn integer NOT NULL, oid integer NOT NULL, type integer NOT NULL);
CREATE INDEX ix_notes_usn ON notes (usn);
CREATE INDEX ix_cards_usn ON cards (usn);
CREATE INDEX ix_revlog_usn ON revlog (usn);
CREATE INDEX ix_cards_nid ON cards (nid);
CREATE INDEX ix_cards_sched ON cards (did, queue, due);
CREATE INDEX ix_revlog_cid ON revlog (cid);
CREATE INDEX ix_notes_csum ON notes (csum);
"#;

#[derive(Debug)]
struct ImportedCard {
    card_id: i64,
    card_ordinal: i64,
    note_id: i64,
    guid: String,
    model_id: i64,
    deck_id: i64,
    fields: Vec<String>,
    tags: Vec<String>,
    card_type: i32,
    queue: i32,
    due: i64,
    interval: i64,
    reps: u32,
    lapses: u32,
    modified_secs: i64,
    stability: Option<f32>,
    difficulty: Option<f32>,
    last_review_secs: Option<i64>,
}

#[derive(Debug)]
struct ImportedRevlog {
    id: i64,
    card_id: i64,
    ease: i32,
    interval: i64,
    last_interval: i64,
    factor: i64,
    time_ms: i64,
    review_type: i32,
}

#[derive(Debug)]
struct ExportCard {
    item: ReviewItem,
    schedule: ReviewSchedule,
    guid: Option<String>,
    imported_deck_id: Option<String>,
    imported_deck_name: Option<String>,
    imported_fields: Option<Vec<String>>,
    imported_tags: Vec<String>,
    imported_media: Vec<MediaReference>,
    media_path: Option<String>,
    media_kind: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
struct MediaReference {
    name: String,
    path: String,
}

pub(crate) fn import_package(
    repository: &SqliteRepository,
    request: &AnkiPackageImportRequest,
) -> Result<AnkiPackageImportSummary, ApplicationError> {
    let package_path = Path::new(&request.package_path);
    let media_directory = Path::new(&request.media_directory);
    fs::create_dir_all(media_directory).map_err(io_repo)?;
    let temp_dir = task_temp_dir("anki-import")?;
    let result = (|| {
        let (collection_path, media_files, mut warnings) =
            unpack_package(package_path, media_directory, &temp_dir)?;
        let anki = Connection::open_with_flags(
            collection_path,
            OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(repo)?;
        let (collection_created_secs, deck_names) = read_decks(&anki)?;
        let revlog = read_revlog(&anki)?;
        let last_reviews = revlog
            .iter()
            .fold(HashMap::<i64, i64>::new(), |mut map, entry| {
                map.entry(entry.card_id)
                    .and_modify(|value| *value = (*value).max(entry.id / 1_000))
                    .or_insert(entry.id / 1_000);
                map
            });
        let cards = read_cards(&anki, &last_reviews)?;
        let now = now_ms();
        let media_by_name = media_files
            .iter()
            .map(|reference| (reference.name.clone(), reference.clone()))
            .collect::<HashMap<_, _>>();

        let mut conn = repository.connection.lock();
        let tx = conn.transaction().map_err(repo)?;
        let mut card_items = HashMap::<i64, ReviewItemId>::new();
        let mut imported_cards = 0;
        let mut updated_cards = 0;
        let mut skipped_cards = 0;
        let mut used_decks = BTreeMap::<i64, String>::new();

        for (deck_id, deck_name) in &deck_names {
            let parent_deck_id = parent_deck_id(*deck_id, deck_name, &deck_names);
            tx.execute(
                "INSERT INTO anki_decks(deck_id,name,parent_deck_id)
                 VALUES (?1,?2,?3)
                 ON CONFLICT(deck_id) DO UPDATE SET
                   name=excluded.name,parent_deck_id=excluded.parent_deck_id",
                params![deck_id.to_string(), deck_name, parent_deck_id],
            )
            .map_err(repo)?;
        }

        for card in cards {
            let deck_name = deck_names
                .get(&card.deck_id)
                .cloned()
                .unwrap_or_else(|| format!("Imported::{}", card.deck_id));
            used_decks.insert(card.deck_id, deck_name.clone());

            let Some(front) = card.fields.first().cloned() else {
                skipped_cards += 1;
                warnings.push(format!(
                    "card {} was skipped because its note has no fields",
                    card.card_id
                ));
                continue;
            };
            let answer = card
                .fields
                .get(1..)
                .filter(|fields| !fields.is_empty())
                .map(|fields| fields.join("<br>"))
                .unwrap_or_else(|| front.clone());
            let item_id = tx
                .query_row(
                    "SELECT item_id FROM anki_review_items
                     WHERE guid=?1 AND card_ordinal=?2",
                    params![card.guid, card.card_ordinal],
                    |row| ReviewItemId::parse(row.get::<_, String>(0)?).map_err(crate::domain_sql),
                )
                .optional()
                .map_err(repo)?
                .unwrap_or_else(|| {
                    ReviewItemId::from_fingerprint(
                        "anki-review-item",
                        &format!("{}:{}", card.guid, card.card_ordinal),
                    )
                });
            let existed = tx
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM anki_review_items WHERE item_id=?1)",
                    [item_id.as_str()],
                    |row| row.get::<_, bool>(0),
                )
                .map_err(repo)?;
            let created_at_ms = u64::try_from(card.modified_secs)
                .unwrap_or_default()
                .saturating_mul(1_000)
                .max(1);
            let item = ReviewItem {
                id: item_id.clone(),
                source: ReviewSource {
                    kind: ReviewSourceKind::LexicalEntry,
                    id: Some(card.guid.clone()),
                    practice_attempt_id: None,
                    lexical_entry_id: None,
                    media_id: None,
                    track_id: None,
                },
                anchors: vec![PracticeAnchor {
                    kind: PracticeAnchorKind::LexicalEntry,
                    id: format!("anki-card:{}", card.card_id),
                    label: Some(answer),
                    lexical_entry_id: None,
                    sentence_id: None,
                    token_start: None,
                    token_end: None,
                    start_ms: None,
                    end_ms: None,
                }],
                prompt_snapshot: front,
                status: ReviewItemStatus::Active,
                created_at_ms,
                updated_at_ms: now,
            };
            let (due_at_ms, interval_days) = imported_due(&card, collection_created_secs, now);
            let schedule = ReviewSchedule {
                item_id: item_id.clone(),
                algorithm: if card.stability.is_some() && card.difficulty.is_some() {
                    "fsrs_6_anki_import_v1".into()
                } else {
                    "anki_sm2_pending_fsrs_migration".into()
                },
                due_at_ms,
                stability: card.stability,
                difficulty: card.difficulty,
                interval_days,
                lapse_count: card.lapses,
                last_reviewed_at_ms: card
                    .last_review_secs
                    .and_then(|secs| u64::try_from(secs).ok())
                    .map(|secs| secs.saturating_mul(1_000)),
                review_count: card.reps,
            };
            tx.execute(
                "INSERT INTO review_items
                 (id,source_kind,status,created_at_ms,updated_at_ms,item_json)
                 VALUES (?1,?2,?3,?4,?5,?6)
                 ON CONFLICT(id) DO UPDATE SET
                   source_kind=excluded.source_kind,status=excluded.status,
                   updated_at_ms=excluded.updated_at_ms,item_json=excluded.item_json",
                params![
                    item.id.as_str(),
                    sql_json(&item.source.kind)?,
                    sql_json(&item.status)?,
                    item.created_at_ms,
                    item.updated_at_ms,
                    sql_json(&item)?
                ],
            )
            .map_err(repo)?;
            tx.execute(
                "INSERT INTO review_schedules(item_id,due_at_ms,algorithm,schedule_json)
                 VALUES (?1,?2,?3,?4)
                 ON CONFLICT(item_id) DO UPDATE SET
                   due_at_ms=excluded.due_at_ms,algorithm=excluded.algorithm,
                   schedule_json=excluded.schedule_json",
                params![
                    item_id.as_str(),
                    schedule.due_at_ms,
                    schedule.algorithm,
                    sql_json(&schedule)?
                ],
            )
            .map_err(repo)?;
            let referenced_media = sound_names(&card.fields.join("\u{1f}"))
                .into_iter()
                .filter_map(|name| media_by_name.get(&name).cloned())
                .collect::<Vec<_>>();
            tx.execute(
                "INSERT INTO anki_review_items
                 (item_id,guid,note_id,card_id,card_ordinal,deck_id,note_model_id,note_fields_json,
                  tags_json,media_json,source_package,imported_at_ms)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12)
                 ON CONFLICT(item_id) DO UPDATE SET
                   card_id=excluded.card_id,card_ordinal=excluded.card_ordinal,
                   deck_id=excluded.deck_id,note_fields_json=excluded.note_fields_json,
                   tags_json=excluded.tags_json,media_json=excluded.media_json,
                   source_package=excluded.source_package,imported_at_ms=excluded.imported_at_ms",
                params![
                    item_id.as_str(),
                    card.guid,
                    card.note_id,
                    card.card_id,
                    card.card_ordinal,
                    card.deck_id.to_string(),
                    card.model_id,
                    serde_json::to_string(&card.fields).map_err(json_repo)?,
                    serde_json::to_string(&card.tags).map_err(json_repo)?,
                    serde_json::to_string(&referenced_media).map_err(json_repo)?,
                    request.package_path,
                    now
                ],
            )
            .map_err(repo)?;
            card_items.insert(card.card_id, item_id);
            if existed {
                updated_cards += 1;
            } else {
                imported_cards += 1;
            }
        }

        let mut imported_revlog_entries = 0;
        for entry in revlog {
            let Some(item_id) = card_items.get(&entry.card_id) else {
                continue;
            };
            imported_revlog_entries += tx
                .execute(
                    "INSERT OR IGNORE INTO anki_review_history
                     (revlog_id,item_id,reviewed_at_ms,rating,interval,last_interval,
                      ease,time_ms,review_type)
                     VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
                    params![
                        entry.id,
                        item_id.as_str(),
                        entry.id,
                        entry.ease,
                        entry.interval,
                        entry.last_interval,
                        entry.factor,
                        entry.time_ms,
                        entry.review_type
                    ],
                )
                .map_err(repo)? as u32;
        }
        tx.commit().map_err(repo)?;
        Ok(AnkiPackageImportSummary {
            imported_cards,
            updated_cards,
            skipped_cards,
            imported_decks: used_decks.len() as u32,
            imported_revlog_entries,
            imported_media_files: media_files.len() as u32,
            warnings,
        })
    })();
    let _ = fs::remove_dir_all(&temp_dir);
    result
}

pub(crate) fn export_package(
    repository: &SqliteRepository,
    request: &AnkiPackageExportRequest,
) -> Result<AnkiPackageExportSummary, ApplicationError> {
    let output_path = Path::new(&request.package_path);
    if let Some(parent) = output_path
        .parent()
        .filter(|parent| !parent.as_os_str().is_empty())
    {
        fs::create_dir_all(parent).map_err(io_repo)?;
    }
    let temp_dir = task_temp_dir("anki-export")?;
    let result = (|| {
        let cards = read_export_cards(repository)?;
        let mut selected = cards
            .into_iter()
            .filter(|card| export_selected(card, request))
            .collect::<Vec<_>>();
        let mut fidelity = AnkiExportFidelity {
            cards_with_media_slices: 0,
            video_slices_rendered_as_audio: 0,
            media_render_failures: 0,
            omitted_capabilities: vec![
                "shadowing_assessment".into(),
                "four_channel_profile_feedback".into(),
            ],
        };
        let mut warnings = Vec::new();
        let mut packaged_media = BTreeMap::<String, PathBuf>::new();
        let collection_path = temp_dir.join("collection.anki2");
        let anki = Connection::open(&collection_path).map_err(repo)?;
        anki.execute_batch(ANKI_SCHEMA).map_err(repo)?;
        let now = now_ms();
        let now_secs = now / 1_000;
        let collection_created_secs = now_secs - now_secs % 86_400;
        let (models, model_ids) = export_models(now_secs);
        let decks = export_decks(&selected, now_secs);
        anki.execute(
            "INSERT INTO col
             (id,crt,mod,scm,ver,dty,usn,ls,conf,models,decks,dconf,tags)
             VALUES (1,?1,?2,?2,11,0,-1,0,?3,?4,?5,?6,?7)",
            params![
                collection_created_secs,
                now_secs,
                json!({"nextPos": selected.len() + 1, "schedVer": 2}).to_string(),
                models.to_string(),
                decks.to_string(),
                json!({"1":{"id":1,"name":"Default","mod":now_secs,"usn":-1}}).to_string(),
                "{}"
            ],
        )
        .map_err(repo)?;

        let tx = anki.unchecked_transaction().map_err(repo)?;
        let mut card_ids = HashMap::<ReviewItemId, i64>::new();
        for (position, card) in selected.iter_mut().enumerate() {
            let kind = export_card_kind(&card.item);
            let model_id = model_ids[&kind];
            let deck_name = card.imported_deck_name.clone().unwrap_or_else(|| {
                format!("Listen::{}", channel_name(primary_channel(&card.item)))
            });
            let deck_id = card
                .imported_deck_id
                .as_deref()
                .and_then(|value| value.parse::<i64>().ok())
                .unwrap_or_else(|| stable_anki_id(&deck_name, "deck"));
            let note_id = stable_anki_id(card.item.id.as_str(), "note");
            let card_id = stable_anki_id(card.item.id.as_str(), "card");
            card_ids.insert(card.item.id.clone(), card_id);
            let guid = card
                .guid
                .clone()
                .unwrap_or_else(|| short_guid(card.item.id.as_str()));
            let mut fields = card.imported_fields.clone().unwrap_or_else(|| {
                vec![
                    card.item.prompt_snapshot.clone(),
                    export_answer(&card.item),
                    export_metadata(&card.item),
                ]
            });
            while fields.len() < 3 {
                fields.push(String::new());
            }
            for media in &card.imported_media {
                if Path::new(&media.path).is_file() {
                    packaged_media
                        .entry(media.name.clone())
                        .or_insert_with(|| PathBuf::from(&media.path));
                } else {
                    warnings.push(format!("missing imported media: {}", media.name));
                }
            }
            if let Some((start_ms, end_ms)) = media_slice(&card.item) {
                fidelity.cards_with_media_slices += 1;
                let file_name = format!("listen-{}.mp3", &card.item.id.as_str()[..12]);
                let rendered = temp_dir.join(&file_name);
                match card.media_path.as_deref() {
                    Some(source) if render_audio_slice(source, start_ms, end_ms, &rendered) => {
                        if card.media_kind.as_deref() == Some("\"video\"") {
                            fidelity.video_slices_rendered_as_audio += 1;
                        }
                        fields[0].push_str(&format!("<br>[sound:{file_name}]"));
                        packaged_media.insert(file_name, rendered);
                    }
                    _ => {
                        fidelity.media_render_failures += 1;
                        warnings.push(format!(
                            "media slice for card {} could not be rendered",
                            card.item.id.as_str()
                        ));
                    }
                }
            }
            let tags = export_tags(card);
            let field_blob = fields.join("\u{1f}");
            tx.execute(
                "INSERT INTO notes
                 (id,guid,mid,mod,usn,tags,flds,sfld,csum,flags,data)
                 VALUES (?1,?2,?3,?4,-1,?5,?6,?7,?8,0,'')",
                params![
                    note_id,
                    guid,
                    model_id,
                    now_secs,
                    tags,
                    field_blob,
                    fields[0],
                    field_checksum(&fields[0])
                ],
            )
            .map_err(repo)?;
            let (card_type, queue, due) =
                export_due(&card.schedule, collection_created_secs, position as i64 + 1);
            let card_data = json!({
                "s": card.schedule.stability,
                "d": card.schedule.difficulty,
                "dr": 0.9,
                "lrt": card.schedule.last_reviewed_at_ms.map(|value| value / 1000)
            });
            tx.execute(
                "INSERT INTO cards
                 (id,nid,did,ord,mod,usn,type,queue,due,ivl,factor,reps,lapses,
                  left,odue,odid,flags,data)
                 VALUES (?1,?2,?3,0,?4,-1,?5,?6,?7,?8,2500,?9,?10,0,0,0,0,?11)",
                params![
                    card_id,
                    note_id,
                    deck_id,
                    now_secs,
                    card_type,
                    queue,
                    due,
                    card.schedule.interval_days.unwrap_or_default().round() as i64,
                    card.schedule.review_count,
                    card.schedule.lapse_count,
                    card_data.to_string()
                ],
            )
            .map_err(repo)?;
        }
        let exported_revlog_entries =
            export_revlog(repository, &tx, &card_ids, &selected, now_secs)?;
        tx.commit().map_err(repo)?;
        drop(anki);

        let temp_package =
            output_path.with_extension(format!("apkg.tmp-{}-{}", std::process::id(), now));
        write_package(
            &temp_package,
            &collection_path,
            &packaged_media,
            &mut warnings,
        )?;
        fs::rename(&temp_package, output_path).map_err(io_repo)?;
        Ok(AnkiPackageExportSummary {
            exported_cards: selected.len() as u32,
            exported_revlog_entries,
            exported_media_files: packaged_media.len() as u32,
            fidelity,
            warnings,
        })
    })();
    let _ = fs::remove_dir_all(&temp_dir);
    result
}

fn unpack_package(
    package_path: &Path,
    media_directory: &Path,
    temp_dir: &Path,
) -> Result<(PathBuf, Vec<MediaReference>, Vec<String>), ApplicationError> {
    let file = File::open(package_path).map_err(io_repo)?;
    let mut archive = ZipArchive::new(file).map_err(zip_repo)?;
    let collection_name = ["collection.anki21", "collection.anki2"]
        .into_iter()
        .find(|name| archive.by_name(name).is_ok())
        .ok_or_else(|| {
            ApplicationError::Invalid(
                "apkg does not contain collection.anki21 or collection.anki2".into(),
            )
        })?;
    let collection_path = temp_dir.join("collection.anki2");
    {
        let mut source = archive.by_name(collection_name).map_err(zip_repo)?;
        if source.size() > 2 * 1024 * 1024 * 1024 {
            return Err(ApplicationError::Invalid(
                "anki collection exceeds the 2 GiB safety limit".into(),
            ));
        }
        let mut destination = File::create(&collection_path).map_err(io_repo)?;
        std::io::copy(&mut source, &mut destination).map_err(io_repo)?;
    }
    let media_map = archive
        .by_name("media")
        .ok()
        .map(|mut file| {
            let mut body = String::new();
            file.read_to_string(&mut body).map_err(io_repo)?;
            serde_json::from_str::<HashMap<String, String>>(&body).map_err(json_repo)
        })
        .transpose()?
        .unwrap_or_default();
    let mut media = Vec::new();
    let mut warnings = Vec::new();
    for (archive_name, original_name) in media_map {
        let safe_name = Path::new(&original_name)
            .file_name()
            .and_then(|name| name.to_str())
            .filter(|name| !name.is_empty());
        let Some(safe_name) = safe_name else {
            warnings.push(format!("unsafe media name was skipped: {original_name}"));
            continue;
        };
        let destination = media_directory.join(safe_name);
        if destination.exists() {
            warnings.push(format!(
                "existing media was kept instead of overwritten: {safe_name}"
            ));
        } else if let Ok(mut source) = archive.by_name(&archive_name) {
            let mut output = File::create(&destination).map_err(io_repo)?;
            std::io::copy(&mut source, &mut output).map_err(io_repo)?;
        } else {
            warnings.push(format!("media payload is missing: {original_name}"));
            continue;
        }
        media.push(MediaReference {
            name: original_name,
            path: destination.to_string_lossy().into_owned(),
        });
    }
    Ok((collection_path, media, warnings))
}

fn read_decks(anki: &Connection) -> Result<(i64, HashMap<i64, String>), ApplicationError> {
    let (created, decks): (i64, String) = anki
        .query_row("SELECT crt,decks FROM col LIMIT 1", [], |row| {
            Ok((row.get(0)?, row.get(1)?))
        })
        .map_err(repo)?;
    let value: Value = serde_json::from_str(&decks).map_err(json_repo)?;
    let mut names = HashMap::new();
    if let Some(object) = value.as_object() {
        for (id, deck) in object {
            if let (Ok(id), Some(name)) =
                (id.parse::<i64>(), deck.get("name").and_then(Value::as_str))
            {
                names.insert(id, name.to_owned());
            }
        }
    }
    Ok((created, names))
}

fn read_cards(
    anki: &Connection,
    last_reviews: &HashMap<i64, i64>,
) -> Result<Vec<ImportedCard>, ApplicationError> {
    let mut statement = anki
        .prepare(
            "SELECT c.id,c.ord,c.nid,n.guid,n.mid,c.did,n.flds,n.tags,c.type,c.queue,
                    c.due,c.ivl,c.reps,c.lapses,c.mod,c.data
             FROM cards c JOIN notes n ON n.id=c.nid
             ORDER BY c.id",
        )
        .map_err(repo)?;
    statement
        .query_map([], |row| {
            let card_id: i64 = row.get(0)?;
            let data: String = row.get(15)?;
            let data: Value = serde_json::from_str(&data).unwrap_or(Value::Null);
            Ok(ImportedCard {
                card_id,
                card_ordinal: row.get(1)?,
                note_id: row.get(2)?,
                guid: row.get(3)?,
                model_id: row.get(4)?,
                deck_id: row.get(5)?,
                fields: row
                    .get::<_, String>(6)?
                    .split('\u{1f}')
                    .map(str::to_owned)
                    .collect(),
                tags: row
                    .get::<_, String>(7)?
                    .split_whitespace()
                    .map(str::to_owned)
                    .collect(),
                card_type: row.get(8)?,
                queue: row.get(9)?,
                due: row.get(10)?,
                interval: row.get(11)?,
                reps: row.get(12)?,
                lapses: row.get(13)?,
                modified_secs: row.get(14)?,
                stability: data.get("s").and_then(Value::as_f64).map(|v| v as f32),
                difficulty: data.get("d").and_then(Value::as_f64).map(|v| v as f32),
                last_review_secs: data
                    .get("lrt")
                    .and_then(Value::as_i64)
                    .or_else(|| last_reviews.get(&card_id).copied()),
            })
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

fn read_revlog(anki: &Connection) -> Result<Vec<ImportedRevlog>, ApplicationError> {
    let mut statement = anki
        .prepare(
            "SELECT id,cid,ease,ivl,lastIvl,factor,time,type
             FROM revlog ORDER BY id",
        )
        .map_err(repo)?;
    statement
        .query_map([], |row| {
            Ok(ImportedRevlog {
                id: row.get(0)?,
                card_id: row.get(1)?,
                ease: row.get(2)?,
                interval: row.get(3)?,
                last_interval: row.get(4)?,
                factor: row.get(5)?,
                time_ms: row.get(6)?,
                review_type: row.get(7)?,
            })
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

fn imported_due(card: &ImportedCard, collection_created_secs: i64, now: u64) -> (u64, Option<f32>) {
    if card.card_type == 0 || card.queue == 0 {
        return (now, None);
    }
    let due = if card.queue == 1 {
        u64::try_from(card.due)
            .unwrap_or_default()
            .saturating_mul(1_000)
    } else {
        u64::try_from(collection_created_secs)
            .unwrap_or_default()
            .saturating_mul(1_000)
            .saturating_add(
                u64::try_from(card.due)
                    .unwrap_or_default()
                    .saturating_mul(DAY_MS),
            )
    };
    let interval = if matches!(card.card_type, 1 | 3) && card.interval <= 0 {
        Some(0.0)
    } else {
        Some(card.interval.max(0) as f32)
    };
    (due, interval)
}

fn parent_deck_id(deck_id: i64, name: &str, decks: &HashMap<i64, String>) -> Option<String> {
    let parent_name = name.rsplit_once("::")?.0;
    decks
        .iter()
        .find_map(|(id, candidate)| (candidate == parent_name).then(|| id.to_string()))
        .or_else(|| Some(format!("{deck_id}:parent:{parent_name}")))
}

fn sound_names(value: &str) -> Vec<String> {
    let mut rest = value;
    let mut names = Vec::new();
    while let Some(start) = rest.find("[sound:") {
        rest = &rest[start + 7..];
        let Some(end) = rest.find(']') else {
            break;
        };
        names.push(rest[..end].to_owned());
        rest = &rest[end + 1..];
    }
    names
}

fn read_export_cards(repository: &SqliteRepository) -> Result<Vec<ExportCard>, ApplicationError> {
    let conn = repository.connection.lock();
    let mut statement = conn
        .prepare(
            "SELECT item.item_json,schedule.schedule_json,imported.guid,
                    imported.deck_id,deck.name,imported.note_fields_json,
                    imported.tags_json,imported.media_json,media.path,media.kind
             FROM review_items item
             JOIN review_schedules schedule ON schedule.item_id=item.id
             LEFT JOIN anki_review_items imported ON imported.item_id=item.id
             LEFT JOIN anki_decks deck ON deck.deck_id=imported.deck_id
             LEFT JOIN media_items media
               ON media.id=json_extract(item.item_json,'$.source.media_id')
             WHERE item.status=?1
             ORDER BY item.created_at_ms,item.id",
        )
        .map_err(repo)?;
    statement
        .query_map(params![sql_json(&ReviewItemStatus::Active)?], |row| {
            let fields = row
                .get::<_, Option<String>>(5)?
                .map(|value| serde_json::from_str(&value).map_err(json_sql))
                .transpose()?;
            let tags = row
                .get::<_, Option<String>>(6)?
                .map(|value| serde_json::from_str(&value).map_err(json_sql))
                .transpose()?
                .unwrap_or_default();
            let media = row
                .get::<_, Option<String>>(7)?
                .map(|value| serde_json::from_str(&value).map_err(json_sql))
                .transpose()?
                .unwrap_or_default();
            Ok(ExportCard {
                item: from_json(&row.get::<_, String>(0)?)?,
                schedule: from_json(&row.get::<_, String>(1)?)?,
                guid: row.get(2)?,
                imported_deck_id: row.get(3)?,
                imported_deck_name: row.get(4)?,
                imported_fields: fields,
                imported_tags: tags,
                imported_media: media,
                media_path: row.get(8)?,
                media_kind: row.get(9)?,
            })
        })
        .map_err(repo)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(repo)
}

fn export_selected(card: &ExportCard, request: &AnkiPackageExportRequest) -> bool {
    let deck_matches = request.deck_ids.is_empty()
        || card
            .imported_deck_id
            .as_ref()
            .is_some_and(|deck| request.deck_ids.contains(deck));
    let channel_matches = request.channels.is_empty()
        || (card.imported_deck_id.is_none()
            && request.channels.contains(&primary_channel(&card.item)));
    deck_matches && channel_matches
}

fn export_models(now_secs: u64) -> (Value, HashMap<String, i64>) {
    let kinds = [
        "word_recognition",
        "chunk_cloze",
        "phrase_presence",
        "source_sentence_recall",
        "delayed_retelling",
    ];
    let mut models = serde_json::Map::new();
    let mut ids = HashMap::new();
    for kind in kinds {
        let id = stable_anki_id(kind, "model");
        ids.insert(kind.to_owned(), id);
        models.insert(
            id.to_string(),
            json!({
                "id": id, "name": format!("Listen · {kind}"), "type": 0,
                "mod": now_secs, "usn": -1, "sortf": 0,
                "flds": [
                    {"name":"Prompt","ord":0,"sticky":false,"rtl":false,"font":"Arial","size":20},
                    {"name":"Answer","ord":1,"sticky":false,"rtl":false,"font":"Arial","size":20},
                    {"name":"ListenMetadata","ord":2,"sticky":false,"rtl":false,"font":"Arial","size":12}
                ],
                "tmpls": [{
                    "name":"Card 1","ord":0,"qfmt":"{{Prompt}}",
                    "afmt":"{{FrontSide}}<hr id=answer>{{Answer}}","did":null,
                    "bqfmt":"","bafmt":""
                }],
                "css":".card{font-family:Arial;font-size:20px;text-align:center;color:#111;background:#fff}",
                "latexPre":"","latexPost":"","latexsvg":false,"req":[[0,"all",[0]]]
            }),
        );
    }
    (Value::Object(models), ids)
}

fn export_decks(cards: &[ExportCard], now_secs: u64) -> Value {
    let mut decks = serde_json::Map::new();
    for card in cards {
        let name = card
            .imported_deck_name
            .clone()
            .unwrap_or_else(|| format!("Listen::{}", channel_name(primary_channel(&card.item))));
        let components = name.split("::").collect::<Vec<_>>();
        for index in 0..components.len() {
            let deck_name = components[..=index].join("::");
            let is_leaf = index + 1 == components.len();
            let id = if is_leaf {
                card.imported_deck_id
                    .as_deref()
                    .and_then(|value| value.parse::<i64>().ok())
                    .unwrap_or_else(|| stable_anki_id(&deck_name, "deck"))
            } else {
                stable_anki_id(&deck_name, "deck")
            };
            decks.entry(id.to_string()).or_insert_with(|| {
                json!({
                    "id":id,"name":deck_name,"mod":now_secs,"usn":-1,"collapsed":false,
                    "dyn":0,"conf":1,"desc":"","extendNew":0,"extendRev":0
                })
            });
        }
    }
    Value::Object(decks)
}

fn export_card_kind(item: &ReviewItem) -> String {
    match item.source.kind {
        ReviewSourceKind::LexicalEntry => "word_recognition",
        ReviewSourceKind::Chunk => "chunk_cloze",
        ReviewSourceKind::ConnectedSpeech => "phrase_presence",
        ReviewSourceKind::SpeakingAttempt => "delayed_retelling",
        ReviewSourceKind::Sentence => "source_sentence_recall",
        ReviewSourceKind::PracticeFailure | ReviewSourceKind::ListeningInbox => {
            if item
                .anchors
                .iter()
                .any(|anchor| anchor.kind == PracticeAnchorKind::ConnectedSpeech)
            {
                "phrase_presence"
            } else if item
                .anchors
                .iter()
                .any(|anchor| anchor.kind == PracticeAnchorKind::Chunk)
            {
                "chunk_cloze"
            } else if item
                .anchors
                .iter()
                .any(|anchor| anchor.kind == PracticeAnchorKind::LexicalEntry)
            {
                "word_recognition"
            } else {
                "source_sentence_recall"
            }
        }
    }
    .to_owned()
}

fn primary_channel(item: &ReviewItem) -> ReviewChannel {
    match item.source.kind {
        ReviewSourceKind::SpeakingAttempt => ReviewChannel::Speaking,
        ReviewSourceKind::Sentence => ReviewChannel::Reading,
        ReviewSourceKind::PracticeFailure
            if item
                .anchors
                .iter()
                .all(|anchor| anchor.kind == PracticeAnchorKind::Sentence) =>
        {
            ReviewChannel::Writing
        }
        _ => ReviewChannel::Listening,
    }
}

fn channel_name(channel: ReviewChannel) -> &'static str {
    match channel {
        ReviewChannel::Listening => "Listening",
        ReviewChannel::Speaking => "Speaking",
        ReviewChannel::Reading => "Reading",
        ReviewChannel::Writing => "Writing",
    }
}

fn export_answer(item: &ReviewItem) -> String {
    item.anchors
        .iter()
        .find_map(|anchor| anchor.label.clone())
        .unwrap_or_else(|| item.prompt_snapshot.clone())
}

fn export_metadata(item: &ReviewItem) -> String {
    json!({
        "listen_item_id": item.id.as_str(),
        "source_kind": item.source.kind,
        "media_id": item.source.media_id.as_ref().map(|id| id.as_str()),
        "start_ms": item.anchors.iter().find_map(|anchor| anchor.start_ms),
        "end_ms": item.anchors.iter().find_map(|anchor| anchor.end_ms)
    })
    .to_string()
}

fn export_tags(card: &ExportCard) -> String {
    let mut tags = card.imported_tags.clone();
    if card.imported_deck_id.is_none() {
        tags.push(format!(
            "listen::channel::{}",
            channel_name(primary_channel(&card.item)).to_lowercase()
        ));
    }
    tags.sort();
    tags.dedup();
    if tags.is_empty() {
        String::new()
    } else {
        format!(" {} ", tags.join(" "))
    }
}

fn export_due(
    schedule: &ReviewSchedule,
    collection_created_secs: u64,
    new_position: i64,
) -> (i32, i32, i64) {
    match schedule.state() {
        ReviewCardState::New => (0, 0, new_position),
        ReviewCardState::Learning => (1, 1, (schedule.due_at_ms / 1_000) as i64),
        ReviewCardState::Relearning => (3, 1, (schedule.due_at_ms / 1_000) as i64),
        ReviewCardState::Review => {
            let collection_ms = collection_created_secs.saturating_mul(1_000);
            let day = schedule.due_at_ms.saturating_sub(collection_ms) / DAY_MS;
            (2, 2, day as i64)
        }
    }
}

fn export_revlog(
    repository: &SqliteRepository,
    anki: &Connection,
    card_ids: &HashMap<ReviewItemId, i64>,
    cards: &[ExportCard],
    now_secs: u64,
) -> Result<u32, ApplicationError> {
    let conn = repository.connection.lock();
    let mut count = 0;
    for card in cards {
        let card_id = card_ids[&card.item.id];
        let mut imported = conn
            .prepare(
                "SELECT revlog_id,rating,interval,last_interval,ease,time_ms,review_type
                 FROM anki_review_history WHERE item_id=?1 ORDER BY revlog_id",
            )
            .map_err(repo)?;
        let rows = imported
            .query_map([card.item.id.as_str()], |row| {
                Ok((
                    row.get::<_, i64>(0)?,
                    row.get::<_, i32>(1)?,
                    row.get::<_, i64>(2)?,
                    row.get::<_, i64>(3)?,
                    row.get::<_, i64>(4)?,
                    row.get::<_, i64>(5)?,
                    row.get::<_, i32>(6)?,
                ))
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        for (id, ease, interval, last_interval, factor, time_ms, review_type) in rows {
            count += anki
                .execute(
                    "INSERT OR IGNORE INTO revlog
                     (id,cid,usn,ease,ivl,lastIvl,factor,time,type)
                     VALUES (?1,?2,-1,?3,?4,?5,?6,?7,?8)",
                    params![
                        id,
                        card_id,
                        ease,
                        interval,
                        last_interval,
                        factor,
                        time_ms,
                        review_type
                    ],
                )
                .map_err(repo)? as u32;
        }
        let mut attempts = conn
            .prepare(
                "SELECT attempt_json FROM review_attempts
                 WHERE item_id=?1 ORDER BY reviewed_at_ms",
            )
            .map_err(repo)?;
        let attempts = attempts
            .query_map([card.item.id.as_str()], |row| {
                from_json::<ReviewAttempt>(&row.get::<_, String>(0)?)
            })
            .map_err(repo)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(repo)?;
        for attempt in attempts {
            let ease = match attempt.rating {
                domain::ReviewRating::Again => 1,
                domain::ReviewRating::Hard => 2,
                domain::ReviewRating::Good => 3,
                domain::ReviewRating::Easy => 4,
            };
            let interval_days = attempt
                .next_due_at_ms
                .map(|due| due.saturating_sub(attempt.reviewed_at_ms) as f32 / DAY_MS as f32)
                .unwrap_or_default();
            let interval = if interval_days < 1.0 {
                -600
            } else {
                interval_days.round() as i64
            };
            let mut id = i64::try_from(attempt.reviewed_at_ms).unwrap_or(i64::MAX - 10);
            while anki
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM revlog WHERE id=?1)",
                    [id],
                    |row| row.get::<_, bool>(0),
                )
                .map_err(repo)?
            {
                id = id.saturating_add(1);
            }
            count += anki
                .execute(
                    "INSERT INTO revlog
                     (id,cid,usn,ease,ivl,lastIvl,factor,time,type)
                     VALUES (?1,?2,-1,?3,?4,0,0,0,1)",
                    params![id, card_id, ease, interval],
                )
                .map_err(repo)? as u32;
        }
    }
    let _ = now_secs;
    Ok(count)
}

fn media_slice(item: &ReviewItem) -> Option<(u64, u64)> {
    item.source.media_id.as_ref()?;
    item.anchors
        .iter()
        .find_map(|anchor| anchor.start_ms.zip(anchor.end_ms))
        .filter(|(start, end)| end > start)
}

fn render_audio_slice(source: &str, start_ms: u64, end_ms: u64, output: &Path) -> bool {
    let start = format!("{:.3}", start_ms as f64 / 1_000.0);
    let duration = format!("{:.3}", (end_ms - start_ms) as f64 / 1_000.0);
    Command::new("ffmpeg")
        .args([
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-ss",
            &start,
            "-i",
            source,
            "-t",
            &duration,
            "-vn",
            "-codec:a",
            "libmp3lame",
        ])
        .arg(output)
        .status()
        .is_ok_and(|status| status.success())
        && output.is_file()
}

fn write_package(
    output: &Path,
    collection: &Path,
    media: &BTreeMap<String, PathBuf>,
    warnings: &mut Vec<String>,
) -> Result<(), ApplicationError> {
    let file = File::create(output).map_err(io_repo)?;
    let mut zip = ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
    zip.start_file("collection.anki2", options)
        .map_err(zip_repo)?;
    let mut collection_file = File::open(collection).map_err(io_repo)?;
    std::io::copy(&mut collection_file, &mut zip).map_err(io_repo)?;
    let mapping = media
        .keys()
        .enumerate()
        .map(|(index, name)| (index.to_string(), name.clone()))
        .collect::<BTreeMap<_, _>>();
    zip.start_file("media", options).map_err(zip_repo)?;
    zip.write_all(
        serde_json::to_string(&mapping)
            .map_err(json_repo)?
            .as_bytes(),
    )
    .map_err(io_repo)?;
    for (index, (name, path)) in media.iter().enumerate() {
        if !path.is_file() {
            warnings.push(format!("media disappeared during export: {name}"));
            continue;
        }
        zip.start_file(index.to_string(), options)
            .map_err(zip_repo)?;
        let mut media_file = File::open(path).map_err(io_repo)?;
        std::io::copy(&mut media_file, &mut zip).map_err(io_repo)?;
    }
    zip.finish().map_err(zip_repo)?;
    Ok(())
}

fn stable_anki_id(value: &str, namespace: &str) -> i64 {
    let digest = Sha256::digest(format!("{namespace}:{value}"));
    let mut bytes = [0u8; 8];
    bytes.copy_from_slice(&digest[..8]);
    (u64::from_be_bytes(bytes) & 0x3fff_ffff_ffff_ffff) as i64
}

fn short_guid(value: &str) -> String {
    hex::encode(&Sha256::digest(value)[..8])
}

fn field_checksum(value: &str) -> i64 {
    let digest = Sha256::digest(value);
    i64::from(u32::from_be_bytes([
        digest[0], digest[1], digest[2], digest[3],
    ]))
}

fn task_temp_dir(prefix: &str) -> Result<PathBuf, ApplicationError> {
    let path = std::env::temp_dir().join(format!(
        "llplayer-{prefix}-{}-{}",
        std::process::id(),
        now_ms()
    ));
    fs::create_dir(&path).map_err(io_repo)?;
    Ok(path)
}

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(u128::from(u64::MAX)) as u64
}

fn io_repo(error: std::io::Error) -> ApplicationError {
    ApplicationError::Repository(error.to_string())
}

fn zip_repo(error: zip::result::ZipError) -> ApplicationError {
    ApplicationError::Invalid(format!("invalid anki package: {error}"))
}

fn json_repo(error: serde_json::Error) -> ApplicationError {
    ApplicationError::Invalid(format!("invalid anki metadata: {error}"))
}

fn json_sql(error: serde_json::Error) -> rusqlite::Error {
    rusqlite::Error::FromSqlConversionFailure(0, rusqlite::types::Type::Text, Box::new(error))
}

#[cfg(test)]
mod tests {
    use super::*;
    use application::ReviewQueueRepository;
    use tempfile::tempdir;

    #[test]
    fn real_apkg_shape_round_trips_fields_schedule_history_deck_and_media() {
        let root = tempdir().unwrap();
        let source_collection = root.path().join("source.anki2");
        let source_media = root.path().join("voice.mp3");
        fs::write(&source_media, b"fake-mp3").unwrap();
        create_fixture_collection(&source_collection);
        let source_package = root.path().join("source.apkg");
        create_fixture_package(&source_package, &source_collection, &source_media);

        let repository = SqliteRepository::in_memory().unwrap();
        let imported_media = root.path().join("imported-media");
        let summary = import_package(
            &repository,
            &AnkiPackageImportRequest {
                package_path: source_package.to_string_lossy().into_owned(),
                media_directory: imported_media.to_string_lossy().into_owned(),
            },
        )
        .unwrap();
        assert_eq!(summary.imported_cards, 1);
        assert_eq!(summary.imported_decks, 1);
        assert_eq!(summary.imported_revlog_entries, 1);
        assert_eq!(summary.imported_media_files, 1);

        let imported = repository.list_imported_deck_schedules().unwrap();
        assert_eq!(imported.len(), 1);
        assert_eq!(imported[0].name, "Languages::English");
        assert_eq!(imported[0].schedule.stability, Some(12.5));
        assert_eq!(imported[0].schedule.difficulty, Some(4.2));

        let output = root.path().join("roundtrip.apkg");
        let exported = export_package(
            &repository,
            &AnkiPackageExportRequest {
                package_path: output.to_string_lossy().into_owned(),
                deck_ids: Vec::new(),
                channels: Vec::new(),
            },
        )
        .unwrap();
        assert_eq!(exported.exported_cards, 1);
        assert_eq!(exported.exported_revlog_entries, 1);
        assert_eq!(exported.exported_media_files, 1);

        let second_repository = SqliteRepository::in_memory().unwrap();
        let second_summary = import_package(
            &second_repository,
            &AnkiPackageImportRequest {
                package_path: output.to_string_lossy().into_owned(),
                media_directory: root
                    .path()
                    .join("second-media")
                    .to_string_lossy()
                    .into_owned(),
            },
        )
        .unwrap();
        assert_eq!(second_summary.imported_cards, 1);
        assert_eq!(second_summary.imported_revlog_entries, 1);
        let second = second_repository.list_imported_deck_schedules().unwrap();
        assert_eq!(second[0].schedule.stability, Some(12.5));
        assert_eq!(second[0].schedule.difficulty, Some(4.2));
    }

    fn create_fixture_collection(path: &Path) {
        let connection = Connection::open(path).unwrap();
        connection.execute_batch(ANKI_SCHEMA).unwrap();
        let decks = json!({
            "10": {
                "id": 10, "name": "Languages::English", "mod": 1,
                "usn": -1, "collapsed": false, "dyn": 0, "conf": 1
            }
        });
        connection
            .execute(
                "INSERT INTO col
                 (id,crt,mod,scm,ver,dty,usn,ls,conf,models,decks,dconf,tags)
                 VALUES (1,1700000000,1700000000,1700000000,11,0,-1,0,'{}','{}',?1,'{}','{}')",
                [decks.to_string()],
            )
            .unwrap();
        connection
            .execute(
                "INSERT INTO notes
                 (id,guid,mid,mod,usn,tags,flds,sfld,csum,flags,data)
                 VALUES (100,'fixture-guid',20,1700000000,-1,' topic ',
                         ?1,'front',1,0,'')",
                ["front [sound:voice.mp3]\u{1f}back"],
            )
            .unwrap();
        connection
            .execute(
                "INSERT INTO cards
                 (id,nid,did,ord,mod,usn,type,queue,due,ivl,factor,reps,lapses,
                  left,odue,odid,flags,data)
                 VALUES (200,100,10,0,1700000000,-1,2,2,10,12,2500,4,1,0,0,0,0,?1)",
                [json!({"s":12.5,"d":4.2,"lrt":1700000000}).to_string()],
            )
            .unwrap();
        connection
            .execute(
                "INSERT INTO revlog
                 (id,cid,usn,ease,ivl,lastIvl,factor,time,type)
                 VALUES (1700000000000,200,-1,3,12,5,2500,800,1)",
                [],
            )
            .unwrap();
    }

    fn create_fixture_package(package: &Path, collection: &Path, media: &Path) {
        let file = File::create(package).unwrap();
        let mut zip = ZipWriter::new(file);
        let options = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
        zip.start_file("collection.anki21", options).unwrap();
        let mut collection = File::open(collection).unwrap();
        std::io::copy(&mut collection, &mut zip).unwrap();
        zip.start_file("media", options).unwrap();
        zip.write_all(br#"{"0":"voice.mp3"}"#).unwrap();
        zip.start_file("0", options).unwrap();
        let mut media = File::open(media).unwrap();
        std::io::copy(&mut media, &mut zip).unwrap();
        zip.finish().unwrap();
    }
}
