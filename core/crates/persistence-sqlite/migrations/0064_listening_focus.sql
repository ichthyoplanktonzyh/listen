-- Fresh listening-focused Core schema. Historical upgrades are intentionally unsupported.

CREATE TABLE background_jobs (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    status TEXT NOT NULL,
    job_json TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE "capability_attempts" (
                   material_id           TEXT NOT NULL REFERENCES learning_materials(id) ON DELETE RESTRICT,
                   attempt_id            TEXT NOT NULL,
                   capability            TEXT NOT NULL CHECK (capability IN ('read', 'listen', 'watch', 'synchronized_read_listen')),
                   status                TEXT NOT NULL CHECK (status IN ('running', 'succeeded', 'failed', 'cancelled', 'superseded')),
                   started_at_ms         INTEGER NOT NULL,
                   finished_at_ms        INTEGER,
                   failure_reason        TEXT,
                   producer_tool_id      TEXT,
                   producer_tool_version TEXT,
                   attempt_sequence      INTEGER NOT NULL DEFAULT 0,
                   PRIMARY KEY (material_id, attempt_id)
                 );

CREATE TABLE corpus_occurrences (
  id TEXT PRIMARY KEY,
  language TEXT NOT NULL,
  kind TEXT NOT NULL,
  normalized_key TEXT,
  display_text TEXT NOT NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  source_snapshot TEXT NOT NULL
);

CREATE VIRTUAL TABLE corpus_occurrences_fts USING fts5(source_snapshot);

CREATE TABLE dictionary_cache (
  id TEXT PRIMARY KEY NOT NULL,
  language TEXT NOT NULL,
  normalized_lemma TEXT NOT NULL,
  provider TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  cached_at_ms INTEGER NOT NULL,
  UNIQUE(language, normalized_lemma, provider)
);

CREATE TABLE hunting_targets (
  id TEXT PRIMARY KEY,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  target_json TEXT NOT NULL,
  UNIQUE(lexical_entry_id)
);

CREATE TABLE learner_profiles (
  id TEXT PRIMARY KEY,
  ui_language TEXT NOT NULL,
  l1_language TEXT,
  active_l2_language TEXT,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE learning_events (
  id TEXT PRIMARY KEY,
  occurred_at_ms INTEGER NOT NULL,
  kind TEXT NOT NULL,
  subject_kind TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  session_id TEXT REFERENCES practice_sessions(id) ON DELETE SET NULL,
  event_json TEXT NOT NULL
);

CREATE TABLE learning_materials (
  id TEXT PRIMARY KEY NOT NULL,
  current_revision_id TEXT NOT NULL
    REFERENCES material_revisions(id)
    ON DELETE RESTRICT
    DEFERRABLE INITIALLY DEFERRED,
  retained_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  CHECK (updated_at_ms >= created_at_ms),
  CHECK (retained_at_ms IS NULL OR retained_at_ms >= created_at_ms),
  CHECK (retained_at_ms IS NULL OR retained_at_ms <= updated_at_ms)
);

CREATE TABLE learning_observations (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sense_id TEXT NOT NULL DEFAULT '',
  capability TEXT NOT NULL,
  task_type TEXT NOT NULL,
  outcome TEXT NOT NULL,
  assistance TEXT NOT NULL,
  surface_form TEXT,
  sentence_id TEXT,
  media_id TEXT,
  origin TEXT NOT NULL,
  source_ref TEXT,
  occurred_at_ms INTEGER NOT NULL
);

CREATE TABLE learning_preparation_runs (
  id TEXT PRIMARY KEY NOT NULL,
  target_key TEXT NOT NULL,
  input_fingerprint TEXT NOT NULL,
  plan_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL
    CHECK (status IN ('queued','running','cancelling','completed','failed','cancelled')),
  revision INTEGER NOT NULL CHECK (revision >= 0),
  retry_of_run_id TEXT REFERENCES learning_preparation_runs(id),
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  run_json TEXT NOT NULL
);

CREATE TABLE lemma_overrides (
  language TEXT NOT NULL,
  original_normalized TEXT NOT NULL,
  corrected_normalized TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(language, original_normalized)
);

CREATE TABLE lexical_capability_history (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sense_id TEXT NOT NULL DEFAULT '',
  capability TEXT NOT NULL,
  previous_state_json TEXT NOT NULL,
  new_state_json TEXT NOT NULL,
  change_kind TEXT NOT NULL,
  changed_at_ms INTEGER NOT NULL
);

CREATE TABLE lexical_capability_states (
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sense_id TEXT NOT NULL DEFAULT '',
  capability TEXT NOT NULL,
  projection_json TEXT,
  override_json TEXT,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(lexical_entry_id, sense_id, capability),
  CHECK(projection_json IS NOT NULL OR override_json IS NOT NULL)
);

CREATE TABLE lexical_entries (
  id TEXT PRIMARY KEY NOT NULL,
  language TEXT NOT NULL,
  kind TEXT NOT NULL,
  granularity TEXT NOT NULL,
  normalization TEXT NOT NULL,
  normalized_key TEXT NOT NULL,
  canonical_form TEXT NOT NULL,
  normalized_form TEXT NOT NULL,
  display_form TEXT NOT NULL,
  status TEXT,
  user_definition TEXT,
  personal_note TEXT,
  normalization_provider TEXT NOT NULL,
  normalization_version TEXT NOT NULL,
  user_corrected INTEGER NOT NULL DEFAULT 0,
  updated_at_ms INTEGER NOT NULL,
  learning_updated_at_ms INTEGER NOT NULL DEFAULT 0,
  UNIQUE(language, granularity, normalization, normalized_key)
);

CREATE TABLE lexical_observations (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  sentence_id_snapshot TEXT NOT NULL,
  original_form TEXT NOT NULL,
  result TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  cleared_at_ms INTEGER,
  UNIQUE(lexical_entry_id, sentence_id)
);

CREATE TABLE lexical_occurrences (
  id TEXT PRIMARY KEY NOT NULL,
  source_key TEXT NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  original_form TEXT NOT NULL,
  sentence_text_snapshot TEXT NOT NULL,
  media_title_snapshot TEXT NOT NULL,
  media_fingerprint_snapshot TEXT NOT NULL,
  start_ms_snapshot INTEGER NOT NULL,
  end_ms_snapshot INTEGER NOT NULL,
  token_start INTEGER,
  token_end INTEGER,
  first_seen_at_ms INTEGER NOT NULL,
  last_seen_at_ms INTEGER NOT NULL,
  encounter_count INTEGER NOT NULL,
  UNIQUE(lexical_entry_id, source_key)
);

CREATE TABLE lexical_sense_folder_occurrences (
    lexical_sense_id TEXT NOT NULL REFERENCES lexical_sense_folders(id) ON DELETE CASCADE,
    lexical_occurrence_id TEXT PRIMARY KEY NOT NULL REFERENCES lexical_occurrences(id) ON DELETE CASCADE
);

CREATE TABLE lexical_sense_folders (
    id TEXT PRIMARY KEY NOT NULL,
    lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
    label TEXT NOT NULL,
    definition TEXT,
    gloss TEXT,
    external_ref TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE lexical_status_history (
  id TEXT PRIMARY KEY NOT NULL,
  lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
  previous_status TEXT,
  new_status TEXT,
  changed_at_ms INTEGER NOT NULL,
  change_source TEXT NOT NULL
);

CREATE TABLE listening_inbox_items (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES practice_sessions(id) ON DELETE SET NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  track_id TEXT REFERENCES subtitle_tracks(id) ON DELETE SET NULL,
  status TEXT NOT NULL,
  captured_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  expires_at_ms INTEGER,
  item_json TEXT NOT NULL
);

CREATE TABLE llm_provider_profiles (
    id                TEXT PRIMARY KEY,
    display_name      TEXT NOT NULL,
    adapter_kind      TEXT NOT NULL,
    base_url          TEXT NOT NULL,
    model_id          TEXT NOT NULL,
    -- Opaque secure-store reference, never the secret. NULL for keyless
    -- (typically local) endpoints.
    auth_ref          TEXT,
    created_at_ms     INTEGER NOT NULL,
    profile_json      TEXT NOT NULL
);

CREATE TABLE llm_sense_group_sentence_checkpoints (
    fingerprint TEXT PRIMARY KEY NOT NULL,
    partition_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE lltimeline_resources (
  track_id TEXT PRIMARY KEY REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  metadata_json TEXT NOT NULL,
  artifacts_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE material_media_bindings (
  media_id TEXT PRIMARY KEY NOT NULL,
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT
);

CREATE TABLE material_media_renditions (
    revision_id       TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    rendition_id      TEXT NOT NULL,
    origin            TEXT NOT NULL CHECK (origin IN ('source', 'derived')),
    kind              TEXT NOT NULL CHECK (kind IN ('audio', 'video')),
    media_type        TEXT NOT NULL,
    fingerprint       TEXT NOT NULL,
    availability      TEXT NOT NULL CHECK (availability IN ('available', 'missing', 'archived')),
    media_sha256      TEXT,
    media_byte_size   INTEGER,
    media_id          TEXT,
    producer_json     TEXT CHECK (producer_json IS NULL OR json_valid(producer_json)),
    compatibility_json TEXT CHECK (compatibility_json IS NULL OR json_valid(compatibility_json)),
    PRIMARY KEY (revision_id, rendition_id)
);

CREATE TABLE material_revisions (
  id TEXT PRIMARY KEY NOT NULL,
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  title TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE material_source_assets (
    revision_id     TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    asset_id        TEXT NOT NULL,
    media_type      TEXT NOT NULL,
    byte_length     INTEGER NOT NULL,
    sha256_digest   TEXT NOT NULL,
    binding_json    TEXT NOT NULL CHECK (json_valid(binding_json)),
    availability_json TEXT NOT NULL CHECK (json_valid(availability_json)),
    created_at_ms   INTEGER NOT NULL,
    PRIMARY KEY (revision_id, asset_id)
);

CREATE TABLE media_items (
  id TEXT PRIMARY KEY NOT NULL,
  path TEXT NOT NULL,
  fingerprint TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  kind TEXT NOT NULL,
  duration_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
, availability TEXT NOT NULL DEFAULT '"available"', retained_at_ms INTEGER);

CREATE TABLE media_triage_intents (
  media_id TEXT NOT NULL PRIMARY KEY,
  intent TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE package_adoptions (
  material_id TEXT PRIMARY KEY NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  material_revision_id TEXT NOT NULL
    REFERENCES material_revisions(id)
    ON DELETE RESTRICT,
  edition_json TEXT NOT NULL
    CHECK (json_valid(edition_json)),
  selected_resource_ids_json TEXT NOT NULL
    CHECK (json_valid(selected_resource_ids_json)),
  exclusive_selections_json TEXT NOT NULL
    CHECK (json_valid(exclusive_selections_json)),
  selected_rendition_ids_json TEXT NOT NULL
    CHECK (json_valid(selected_rendition_ids_json)),
  adopted_at_ms INTEGER NOT NULL
    CHECK (adopted_at_ms >= 0),
  FOREIGN KEY (material_id, release_id)
    REFERENCES package_installations(material_id, release_id)
    ON DELETE RESTRICT
);

CREATE TABLE package_installations (
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  material_revision_id TEXT NOT NULL
    REFERENCES material_revisions(id)
    ON DELETE RESTRICT,
  release_created_at_ms INTEGER NOT NULL
    CHECK (release_created_at_ms >= 0),
  edition_json TEXT NOT NULL
    CHECK (json_valid(edition_json)),
  resources_json TEXT NOT NULL
    CHECK (json_valid(resources_json)),
  renditions_json TEXT NOT NULL
    CHECK (json_valid(renditions_json)),
  installed_at_ms INTEGER NOT NULL
    CHECK (installed_at_ms >= 0),
  PRIMARY KEY (material_id, release_id)
);

CREATE TABLE package_rendition_blobs (
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  rendition_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  digest TEXT NOT NULL,
  size_bytes INTEGER NOT NULL
    CHECK (size_bytes >= 0),
  body BLOB NOT NULL,
  PRIMARY KEY (material_id, release_id, rendition_id),
  FOREIGN KEY (material_id, release_id)
    REFERENCES package_installations(material_id, release_id)
    ON DELETE RESTRICT
);

CREATE TABLE package_resource_payloads (
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  resource_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  schema TEXT NOT NULL,
  digest TEXT NOT NULL,
  size_bytes INTEGER NOT NULL
    CHECK (size_bytes >= 0),
  body BLOB NOT NULL,
  PRIMARY KEY (material_id, release_id, resource_id),
  FOREIGN KEY (material_id, release_id)
    REFERENCES package_installations(material_id, release_id)
    ON DELETE RESTRICT
);

CREATE TABLE pending_secret_cleanups (
    auth_ref TEXT PRIMARY KEY,
    queued_at_ms INTEGER NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('reserved', 'ready'))
);

CREATE TABLE phone_timeline_runs (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  sentence_id TEXT REFERENCES subtitle_sentences(id) ON DELETE SET NULL,
  parent_word_timeline_id TEXT REFERENCES word_timeline_runs(id) ON DELETE SET NULL,
  parent_phonetic_analysis_id TEXT,
  status TEXT NOT NULL,
  timeline_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE phonetic_analyses (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL REFERENCES phonetic_analysis_jobs(id),
  media_id TEXT NOT NULL,
  track_id TEXT NOT NULL,
  sentence_id TEXT,
  provider_id TEXT NOT NULL,
  model_id TEXT NOT NULL,
  analysis_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE phonetic_analysis_jobs (
  id TEXT PRIMARY KEY,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id),
  sentence_id TEXT REFERENCES subtitle_sentences(id),
  input_fingerprint TEXT NOT NULL,
  status TEXT NOT NULL,
  job_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE phonetic_analysis_models (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  descriptor_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE phonetic_finding_feedback (
  finding_id TEXT PRIMARY KEY,
  feedback_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE playback_progress (
  media_id TEXT PRIMARY KEY NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
  position_ms INTEGER NOT NULL CHECK(position_ms >= 0),
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE practice_attempts (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES practice_items(id) ON DELETE CASCADE,
  result TEXT NOT NULL,
  submitted_at_ms INTEGER NOT NULL,
  attempt_json TEXT NOT NULL
);

CREATE TABLE practice_items (
  id TEXT PRIMARY KEY,
  session_id TEXT REFERENCES practice_sessions(id) ON DELETE SET NULL,
  kind TEXT NOT NULL,
  target_kind TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  item_json TEXT NOT NULL
);

CREATE TABLE practice_sessions (
  id TEXT PRIMARY KEY,
  mode TEXT NOT NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  track_id TEXT REFERENCES subtitle_tracks(id) ON DELETE SET NULL,
  started_at_ms INTEGER NOT NULL,
  ended_at_ms INTEGER,
  session_json TEXT NOT NULL
);

CREATE TABLE pronunciation_analysis (
  sentence_id TEXT PRIMARY KEY REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  provider_id TEXT NOT NULL,
  provider_version TEXT NOT NULL,
  analysis_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE pronunciation_cache (
  language TEXT NOT NULL,
  accent TEXT NOT NULL,
  normalized_text TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  provider_version TEXT NOT NULL,
  pronunciation_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(language, accent, normalized_text, provider_id, provider_version)
);

CREATE TABLE prosody_analysis_runs (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  parent_word_timeline_id TEXT REFERENCES word_timeline_runs(id) ON DELETE SET NULL,
  status TEXT NOT NULL,
  analysis_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE review_attempts (
  id TEXT PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES review_items(id) ON DELETE CASCADE,
  reviewed_at_ms INTEGER NOT NULL,
  rating TEXT NOT NULL,
  attempt_json TEXT NOT NULL
);

CREATE TABLE review_items (
  id TEXT PRIMARY KEY,
  source_kind TEXT NOT NULL,
  status TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  item_json TEXT NOT NULL
);

CREATE TABLE review_schedules (
  item_id TEXT PRIMARY KEY REFERENCES review_items(id) ON DELETE CASCADE,
  due_at_ms INTEGER NOT NULL,
  algorithm TEXT NOT NULL,
  schedule_json TEXT NOT NULL
);

CREATE TABLE review_settings (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  new_cards_per_day INTEGER NOT NULL,
  reviews_per_day INTEGER NOT NULL
);

CREATE TABLE semantic_embedding_index (
  source_kind TEXT NOT NULL,
  source_id TEXT NOT NULL,
  language TEXT NOT NULL,
  text_sha256 TEXT NOT NULL,
  model_fingerprint TEXT NOT NULL,
  dimension INTEGER NOT NULL CHECK (dimension > 0),
  vector_f32le BLOB NOT NULL,
  indexed_at_ms INTEGER NOT NULL,
  PRIMARY KEY (model_fingerprint, source_kind, source_id)
);

CREATE TABLE sense_group_analysis_runs (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  parent_word_timeline_id TEXT REFERENCES word_timeline_runs(id) ON DELETE SET NULL,
  status TEXT NOT NULL,
  analysis_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE source_identity_mappings (
    source_id             TEXT NOT NULL,
    item_id               TEXT NOT NULL,
    evidence_json         TEXT NOT NULL CHECK (json_valid(evidence_json)),
    material_id           TEXT NOT NULL REFERENCES learning_materials(id) ON DELETE RESTRICT,
    material_revision_id  TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    mapped_at_ms          INTEGER NOT NULL,
    PRIMARY KEY (source_id, item_id)
);

CREATE TABLE speech_rule_confirmations (
  sentence_id TEXT NOT NULL REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  rule_id TEXT NOT NULL,
  confirmation_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(sentence_id, rule_id)
);

CREATE TABLE subtitle_sentences (
  id TEXT PRIMARY KEY NOT NULL,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  cue_index INTEGER NOT NULL,
  start_ms INTEGER NOT NULL CHECK(start_ms >= 0),
  end_ms INTEGER NOT NULL CHECK(end_ms >= start_ms),
  original_text TEXT NOT NULL,
  display_text TEXT NOT NULL,
  tokens_json TEXT NOT NULL,
  UNIQUE(track_id, cue_index)
);

CREATE TABLE subtitle_tracks (
  id TEXT PRIMARY KEY NOT NULL,
  media_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
  fingerprint TEXT NOT NULL,
  language TEXT,
  source TEXT NOT NULL, status TEXT NOT NULL DEFAULT '"available"',
  UNIQUE(media_id, fingerprint)
);

CREATE TABLE word_timeline_runs (
  id TEXT PRIMARY KEY,
  track_id TEXT NOT NULL REFERENCES subtitle_tracks(id) ON DELETE CASCADE,
  media_id TEXT NOT NULL REFERENCES media_items(id),
  status TEXT NOT NULL,
  timeline_json TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE word_timings (
  sentence_id TEXT PRIMARY KEY REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  timing_source TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  provider_version TEXT NOT NULL,
  timings_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE INDEX corpus_occurrences_language_key_idx
  ON corpus_occurrences(language, normalized_key);

CREATE INDEX corpus_occurrences_track_idx
  ON corpus_occurrences(track_id, start_ms);

CREATE INDEX hunting_targets_status_idx
  ON hunting_targets(status, updated_at_ms DESC);

CREATE INDEX idx_background_jobs_kind_created
    ON background_jobs(kind, created_at_ms, id);

CREATE INDEX idx_background_jobs_kind_status
    ON background_jobs(kind, status);

CREATE INDEX idx_capability_attempts_material
                   ON capability_attempts (material_id);

CREATE INDEX idx_lexical_entries_status
  ON lexical_entries(language, granularity, status, normalized_key);

CREATE INDEX idx_lexical_observation_entry
  ON lexical_observations(lexical_entry_id);

CREATE INDEX idx_lexical_observation_sentence
  ON lexical_observations(sentence_id);

CREATE INDEX idx_lexical_occurrences_recent
  ON lexical_occurrences(lexical_entry_id, last_seen_at_ms DESC);

CREATE INDEX idx_lexical_sense_folders_entry
    ON lexical_sense_folders(lexical_entry_id, created_at_ms);

CREATE INDEX idx_llm_provider_profiles_created
    ON llm_provider_profiles (created_at_ms);

CREATE INDEX idx_llm_sentence_checkpoints_updated
    ON llm_sense_group_sentence_checkpoints(updated_at_ms);

CREATE INDEX idx_material_media_bindings_material_id
  ON material_media_bindings(material_id);

CREATE INDEX idx_material_media_renditions_revision ON material_media_renditions (revision_id);

CREATE INDEX idx_material_revisions_material_id
  ON material_revisions(material_id);

CREATE INDEX idx_media_path ON media_items(path);

CREATE INDEX idx_package_adoptions_release_id
  ON package_adoptions(release_id);

CREATE INDEX idx_package_installations_material_id
  ON package_installations(material_id);

CREATE INDEX idx_package_rendition_blobs_material
  ON package_rendition_blobs(material_id);

CREATE INDEX idx_semantic_embedding_space ON semantic_embedding_index(model_fingerprint, language, source_kind);

CREATE INDEX idx_source_identity_mappings_material ON source_identity_mappings (material_id);

CREATE INDEX idx_subtitle_timeline ON subtitle_sentences(track_id, start_ms, end_ms);

CREATE INDEX learning_events_kind_idx
  ON learning_events(kind, occurred_at_ms DESC);

CREATE INDEX learning_events_occurred_idx
  ON learning_events(occurred_at_ms DESC);

CREATE INDEX learning_events_subject_idx
  ON learning_events(subject_kind, subject_id, occurred_at_ms DESC);

CREATE INDEX learning_observations_entry_capability_idx
  ON learning_observations(lexical_entry_id, capability, occurred_at_ms DESC);

CREATE INDEX learning_observations_occurred_idx
  ON learning_observations(occurred_at_ms DESC);

CREATE UNIQUE INDEX learning_preparation_runs_active_target
  ON learning_preparation_runs(target_key)
  WHERE status IN ('queued','running','cancelling');

CREATE INDEX learning_preparation_runs_target_history
  ON learning_preparation_runs(target_key, created_at_ms DESC, id);

CREATE INDEX lexical_capability_history_entry_idx
  ON lexical_capability_history(lexical_entry_id, sense_id, changed_at_ms DESC);

CREATE INDEX lexical_capability_states_capability_idx
  ON lexical_capability_states(capability, updated_at_ms DESC);

CREATE INDEX listening_inbox_items_media_idx
  ON listening_inbox_items(media_id, captured_at_ms DESC);

CREATE INDEX listening_inbox_items_session_idx
  ON listening_inbox_items(session_id, captured_at_ms DESC);

CREATE INDEX listening_inbox_items_status_idx
  ON listening_inbox_items(status, updated_at_ms DESC);

CREATE UNIQUE INDEX phone_timeline_runs_one_active_per_track_idx
  ON phone_timeline_runs(track_id)
  WHERE status = '"active"';

CREATE INDEX phone_timeline_runs_parent_phonetic_analysis_idx
  ON phone_timeline_runs(parent_phonetic_analysis_id, created_at_ms DESC);

CREATE INDEX phone_timeline_runs_parent_word_timeline_idx
  ON phone_timeline_runs(parent_word_timeline_id, created_at_ms DESC);

CREATE INDEX phone_timeline_runs_sentence_idx
  ON phone_timeline_runs(sentence_id, created_at_ms DESC);

CREATE INDEX phone_timeline_runs_track_idx
  ON phone_timeline_runs(track_id, created_at_ms DESC);

CREATE INDEX phone_timeline_runs_track_status_idx
  ON phone_timeline_runs(track_id, status, updated_at_ms DESC);

CREATE INDEX phonetic_analyses_sentence_idx
  ON phonetic_analyses(sentence_id, created_at_ms DESC);

CREATE INDEX phonetic_analyses_track_idx
  ON phonetic_analyses(track_id, created_at_ms DESC);

CREATE INDEX phonetic_analysis_jobs_input_idx
  ON phonetic_analysis_jobs(input_fingerprint, status);

CREATE INDEX phonetic_analysis_jobs_status_idx
  ON phonetic_analysis_jobs(status, updated_at_ms);

CREATE INDEX practice_attempts_item_idx
  ON practice_attempts(item_id, submitted_at_ms DESC);

CREATE INDEX practice_attempts_result_idx
  ON practice_attempts(result, submitted_at_ms DESC);

CREATE INDEX practice_items_kind_idx
  ON practice_items(kind, created_at_ms DESC);

CREATE INDEX practice_items_session_idx
  ON practice_items(session_id, created_at_ms DESC);

CREATE INDEX practice_sessions_media_idx
  ON practice_sessions(media_id, started_at_ms DESC);

CREATE INDEX practice_sessions_started_idx
  ON practice_sessions(started_at_ms DESC);

CREATE INDEX pronunciation_analysis_provider_idx
  ON pronunciation_analysis(provider_id, provider_version);

CREATE INDEX pronunciation_cache_provider_idx
  ON pronunciation_cache(provider_id, provider_version);

CREATE UNIQUE INDEX prosody_analysis_runs_one_active_per_track_idx
  ON prosody_analysis_runs(track_id)
  WHERE status = '"active"';

CREATE INDEX prosody_analysis_runs_parent_word_timeline_idx
  ON prosody_analysis_runs(parent_word_timeline_id, created_at_ms DESC);

CREATE INDEX prosody_analysis_runs_track_idx
  ON prosody_analysis_runs(track_id, created_at_ms DESC);

CREATE INDEX prosody_analysis_runs_track_status_idx
  ON prosody_analysis_runs(track_id, status, updated_at_ms DESC);

CREATE INDEX review_attempts_item_idx
  ON review_attempts(item_id, reviewed_at_ms DESC);

CREATE INDEX review_items_source_idx
  ON review_items(source_kind, created_at_ms DESC);

CREATE INDEX review_items_status_idx
  ON review_items(status, updated_at_ms DESC);

CREATE INDEX review_schedules_due_idx
  ON review_schedules(due_at_ms ASC);

CREATE UNIQUE INDEX sense_group_analysis_runs_one_active_per_track_idx
  ON sense_group_analysis_runs(track_id)
  WHERE status = '"active"';

CREATE INDEX sense_group_analysis_runs_parent_word_timeline_idx
  ON sense_group_analysis_runs(parent_word_timeline_id, created_at_ms DESC);

CREATE INDEX sense_group_analysis_runs_track_idx
  ON sense_group_analysis_runs(track_id, created_at_ms DESC);

CREATE INDEX sense_group_analysis_runs_track_status_idx
  ON sense_group_analysis_runs(track_id, status, updated_at_ms DESC);

CREATE UNIQUE INDEX word_timeline_runs_one_active_per_track_idx
  ON word_timeline_runs(track_id)
  WHERE status = '"active"';

CREATE INDEX word_timeline_runs_track_idx
  ON word_timeline_runs(track_id, created_at_ms DESC);

CREATE INDEX word_timeline_runs_track_status_idx
  ON word_timeline_runs(track_id, status, updated_at_ms DESC);

CREATE INDEX word_timings_source_idx ON word_timings(timing_source);

CREATE TRIGGER corpus_occurrences_fts_ad AFTER DELETE ON corpus_occurrences BEGIN
  DELETE FROM corpus_occurrences_fts WHERE rowid = old.rowid;
END;

CREATE TRIGGER corpus_occurrences_fts_ai AFTER INSERT ON corpus_occurrences BEGIN
  INSERT INTO corpus_occurrences_fts(rowid, source_snapshot)
    VALUES (new.rowid, new.source_snapshot);
END;

CREATE TRIGGER corpus_occurrences_fts_au AFTER UPDATE ON corpus_occurrences BEGIN
  DELETE FROM corpus_occurrences_fts WHERE rowid = old.rowid;
  INSERT INTO corpus_occurrences_fts(rowid, source_snapshot)
    VALUES (new.rowid, new.source_snapshot);
END;

CREATE TRIGGER validate_lexical_sense_folder_occurrence_parent
BEFORE INSERT ON lexical_sense_folder_occurrences
FOR EACH ROW
WHEN (
    SELECT lexical_entry_id FROM lexical_sense_folders WHERE id = NEW.lexical_sense_id
) != (
    SELECT lexical_entry_id FROM lexical_occurrences WHERE id = NEW.lexical_occurrence_id
)
BEGIN
    SELECT RAISE(ABORT, 'sense folder and occurrence must share lexical entry');
END;

CREATE TRIGGER validate_lexical_sense_folder_occurrence_parent_update
BEFORE UPDATE ON lexical_sense_folder_occurrences
FOR EACH ROW
WHEN (
    SELECT lexical_entry_id FROM lexical_sense_folders WHERE id = NEW.lexical_sense_id
) != (
    SELECT lexical_entry_id FROM lexical_occurrences WHERE id = NEW.lexical_occurrence_id
)
BEGIN
    SELECT RAISE(ABORT, 'sense folder and occurrence must share lexical entry');
END;

INSERT INTO review_settings(singleton, new_cards_per_day, reviews_per_day) VALUES (1, 20, 200);
