-- Fresh-store schema for the parked independent reading/writing/speaking and
-- imported-card features. This branch starts with the shared listening schema
-- and adds only semantic-task, output, recording, expression, and Anki facts.

CREATE TABLE semantic_rubrics (
  id TEXT NOT NULL,
  version INTEGER NOT NULL,
  purpose TEXT NOT NULL,
  media_id TEXT,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  source_language TEXT NOT NULL,
  response_language TEXT NOT NULL,
  source_sha256 TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  rubric_json TEXT NOT NULL,
  PRIMARY KEY (id, version)
);
CREATE INDEX semantic_rubrics_media_idx ON semantic_rubrics(media_id, start_ms);

CREATE TABLE semantic_task_attempts (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  rubric_id TEXT NOT NULL,
  rubric_version INTEGER NOT NULL,
  status TEXT NOT NULL,
  started_at_ms INTEGER NOT NULL,
  attempt_json TEXT NOT NULL,
  FOREIGN KEY (rubric_id, rubric_version) REFERENCES semantic_rubrics(id, version)
);
CREATE INDEX semantic_task_attempts_rubric_idx
  ON semantic_task_attempts(rubric_id, rubric_version, started_at_ms DESC);
CREATE INDEX semantic_task_attempts_kind_idx
  ON semantic_task_attempts(kind, started_at_ms DESC);

CREATE TABLE semantic_judgments (
  id TEXT PRIMARY KEY,
  attempt_id TEXT NOT NULL REFERENCES semantic_task_attempts(id),
  response_revision INTEGER NOT NULL,
  rubric_id TEXT NOT NULL,
  rubric_version INTEGER NOT NULL,
  abstained INTEGER NOT NULL,
  created_at_ms INTEGER NOT NULL,
  judgment_json TEXT NOT NULL
);
CREATE INDEX semantic_judgments_attempt_idx
  ON semantic_judgments(attempt_id, created_at_ms);

CREATE TABLE judgment_adjudications (
  id TEXT PRIMARY KEY,
  judgment_id TEXT NOT NULL REFERENCES semantic_judgments(id),
  point_id TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  adjudication_json TEXT NOT NULL
);
CREATE INDEX judgment_adjudications_judgment_idx
  ON judgment_adjudications(judgment_id, occurred_at_ms);

CREATE TRIGGER semantic_rubrics_append_only_update BEFORE UPDATE ON semantic_rubrics BEGIN
  SELECT RAISE(ABORT, 'semantic_rubrics is append-only');
END;
CREATE TRIGGER semantic_rubrics_append_only_delete BEFORE DELETE ON semantic_rubrics BEGIN
  SELECT RAISE(ABORT, 'semantic_rubrics is append-only');
END;
CREATE TRIGGER semantic_task_attempts_append_only_update BEFORE UPDATE ON semantic_task_attempts BEGIN
  SELECT RAISE(ABORT, 'semantic_task_attempts is append-only');
END;
CREATE TRIGGER semantic_task_attempts_append_only_delete BEFORE DELETE ON semantic_task_attempts BEGIN
  SELECT RAISE(ABORT, 'semantic_task_attempts is append-only');
END;
CREATE TRIGGER semantic_judgments_append_only_update BEFORE UPDATE ON semantic_judgments BEGIN
  SELECT RAISE(ABORT, 'semantic_judgments is append-only');
END;
CREATE TRIGGER semantic_judgments_append_only_delete BEFORE DELETE ON semantic_judgments BEGIN
  SELECT RAISE(ABORT, 'semantic_judgments is append-only');
END;
CREATE TRIGGER judgment_adjudications_append_only_update BEFORE UPDATE ON judgment_adjudications BEGIN
  SELECT RAISE(ABORT, 'judgment_adjudications is append-only');
END;
CREATE TRIGGER judgment_adjudications_append_only_delete BEFORE DELETE ON judgment_adjudications BEGIN
  SELECT RAISE(ABORT, 'judgment_adjudications is append-only');
END;

CREATE TABLE reading_positions (
  track_id TEXT PRIMARY KEY,
  media_id TEXT,
  anchor_cue_id TEXT NOT NULL,
  paragraph_index INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL
);

CREATE TABLE writing_feedback_findings (
  id TEXT PRIMARY KEY,
  attempt_id TEXT NOT NULL REFERENCES semantic_task_attempts(id),
  response_revision INTEGER NOT NULL,
  layer TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  finding_json TEXT NOT NULL
);
CREATE INDEX writing_feedback_findings_attempt_idx
  ON writing_feedback_findings(attempt_id, response_revision, created_at_ms, id);
CREATE TABLE writing_finding_dispositions (
  id TEXT PRIMARY KEY,
  finding_id TEXT NOT NULL REFERENCES writing_feedback_findings(id),
  decision TEXT NOT NULL,
  occurred_at_ms INTEGER NOT NULL,
  disposition_json TEXT NOT NULL
);
CREATE INDEX writing_finding_dispositions_finding_idx
  ON writing_finding_dispositions(finding_id, occurred_at_ms, id);
CREATE TABLE writing_drafts (
  rubric_id TEXT PRIMARY KEY,
  updated_at_ms INTEGER NOT NULL,
  draft_json TEXT NOT NULL
);
CREATE TRIGGER writing_feedback_findings_append_only_update
BEFORE UPDATE ON writing_feedback_findings BEGIN
  SELECT RAISE(ABORT, 'writing_feedback_findings is append-only');
END;
CREATE TRIGGER writing_feedback_findings_append_only_delete
BEFORE DELETE ON writing_feedback_findings BEGIN
  SELECT RAISE(ABORT, 'writing_feedback_findings is append-only');
END;
CREATE TRIGGER writing_finding_dispositions_append_only_update
BEFORE UPDATE ON writing_finding_dispositions BEGIN
  SELECT RAISE(ABORT, 'writing_finding_dispositions is append-only');
END;
CREATE TRIGGER writing_finding_dispositions_append_only_delete
BEFORE DELETE ON writing_finding_dispositions BEGIN
  SELECT RAISE(ABORT, 'writing_finding_dispositions is append-only');
END;

CREATE TABLE production_corpus_documents (
  id TEXT PRIMARY KEY,
  language TEXT NOT NULL,
  channel TEXT NOT NULL,
  assistance TEXT NOT NULL,
  attempt_id TEXT NOT NULL REFERENCES semantic_task_attempts(id),
  rubric_id TEXT NOT NULL,
  response_revision INTEGER NOT NULL,
  activity_kind TEXT NOT NULL,
  media_id TEXT,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  response_text TEXT NOT NULL,
  produced_at_ms INTEGER NOT NULL,
  UNIQUE(attempt_id, response_revision)
);
CREATE TABLE production_corpus_entries (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES production_corpus_documents(id) ON DELETE CASCADE,
  normalized_key TEXT NOT NULL,
  display_text TEXT NOT NULL,
  start_char INTEGER NOT NULL,
  end_char INTEGER NOT NULL
);
CREATE INDEX production_corpus_document_rubric_idx
  ON production_corpus_documents(rubric_id);
CREATE INDEX production_corpus_document_time_idx
  ON production_corpus_documents(language, produced_at_ms DESC);
CREATE INDEX production_corpus_entry_key_idx
  ON production_corpus_entries(normalized_key, document_id);
CREATE VIRTUAL TABLE production_corpus_documents_fts USING fts5(
  document_id UNINDEXED,
  language UNINDEXED,
  response_text,
  tokenize = 'unicode61'
);
CREATE TRIGGER production_corpus_documents_fts_insert
AFTER INSERT ON production_corpus_documents BEGIN
  INSERT INTO production_corpus_documents_fts(document_id, language, response_text)
  VALUES (new.id, new.language, new.response_text);
END;
CREATE TRIGGER production_corpus_documents_fts_delete
AFTER DELETE ON production_corpus_documents BEGIN
  DELETE FROM production_corpus_documents_fts WHERE document_id = old.id;
END;

CREATE TABLE user_sentence_patterns (
  id TEXT PRIMARY KEY NOT NULL,
  language TEXT NOT NULL,
  current_version INTEGER NOT NULL CHECK (current_version > 0),
  current_name TEXT NOT NULL,
  current_pattern_text TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  asset_json TEXT NOT NULL
);
CREATE INDEX user_sentence_patterns_language_updated
  ON user_sentence_patterns(language, updated_at_ms DESC);
CREATE TABLE user_sentence_pattern_versions (
  id TEXT PRIMARY KEY NOT NULL,
  pattern_id TEXT NOT NULL REFERENCES user_sentence_patterns(id) ON DELETE CASCADE,
  version INTEGER NOT NULL CHECK (version > 0),
  created_at_ms INTEGER NOT NULL,
  version_json TEXT NOT NULL,
  UNIQUE(pattern_id, version)
);
CREATE TABLE personal_expression_attempts (
  id TEXT PRIMARY KEY NOT NULL,
  pattern_id TEXT NOT NULL REFERENCES user_sentence_patterns(id) ON DELETE CASCADE,
  pattern_version_id TEXT NOT NULL REFERENCES user_sentence_pattern_versions(id) ON DELETE RESTRICT,
  channel TEXT NOT NULL CHECK (channel IN ('speaking', 'writing')),
  assistance TEXT NOT NULL,
  completed_at_ms INTEGER NOT NULL,
  attempt_json TEXT NOT NULL
);
CREATE INDEX personal_expression_attempts_pattern_time
  ON personal_expression_attempts(pattern_id, completed_at_ms DESC);

CREATE TABLE recording_assets (
  id TEXT PRIMARY KEY,
  practice_attempt_id TEXT REFERENCES practice_attempts(id) ON DELETE SET NULL,
  media_id TEXT REFERENCES media_items(id) ON DELETE SET NULL,
  language TEXT NOT NULL,
  file_path TEXT NOT NULL,
  duration_ms INTEGER NOT NULL CHECK (duration_ms > 0),
  created_at_ms INTEGER NOT NULL,
  asset_json TEXT NOT NULL
);
CREATE INDEX recording_assets_attempt_idx ON recording_assets(practice_attempt_id);
CREATE INDEX recording_assets_media_created_idx
  ON recording_assets(media_id, created_at_ms DESC);
CREATE TABLE shadowing_analyses (
  id TEXT PRIMARY KEY,
  recording_id TEXT NOT NULL REFERENCES recording_assets(id) ON DELETE CASCADE,
  attempt_id TEXT NOT NULL REFERENCES practice_attempts(id) ON DELETE CASCADE,
  provider_id TEXT NOT NULL,
  provider_version TEXT NOT NULL,
  reference_audio_sha256 TEXT NOT NULL CHECK (length(reference_audio_sha256) = 64),
  created_at_ms INTEGER NOT NULL,
  analysis_json TEXT NOT NULL
);
CREATE INDEX shadowing_analyses_recording_created_idx
  ON shadowing_analyses(recording_id, created_at_ms DESC);

CREATE TABLE anki_decks (
  deck_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  parent_deck_id TEXT
);
CREATE TABLE anki_review_items (
  item_id TEXT PRIMARY KEY REFERENCES review_items(id) ON DELETE CASCADE,
  guid TEXT NOT NULL,
  note_id INTEGER NOT NULL,
  card_id INTEGER NOT NULL,
  card_ordinal INTEGER NOT NULL DEFAULT 0,
  deck_id TEXT NOT NULL REFERENCES anki_decks(deck_id),
  note_model_id INTEGER NOT NULL,
  note_fields_json TEXT NOT NULL,
  tags_json TEXT NOT NULL,
  media_json TEXT NOT NULL,
  source_package TEXT NOT NULL,
  imported_at_ms INTEGER NOT NULL,
  UNIQUE(guid, card_id),
  UNIQUE(guid, card_ordinal)
);
CREATE INDEX anki_review_items_deck_idx ON anki_review_items(deck_id, item_id);
CREATE TABLE anki_review_history (
  revlog_id INTEGER PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES review_items(id) ON DELETE CASCADE,
  reviewed_at_ms INTEGER NOT NULL,
  rating INTEGER NOT NULL,
  interval INTEGER NOT NULL,
  last_interval INTEGER NOT NULL,
  ease INTEGER NOT NULL,
  time_ms INTEGER NOT NULL,
  review_type INTEGER NOT NULL
);
CREATE INDEX anki_review_history_item_idx ON anki_review_history(item_id, reviewed_at_ms);

CREATE TABLE transcription_models (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  descriptor_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
);
