-- Generalize the rebuildable production projection to multiple immutable
-- attempt sources without inventing semantic-task identities for realtime turns.
DROP TRIGGER IF EXISTS production_corpus_documents_fts_insert;
DROP TRIGGER IF EXISTS production_corpus_documents_fts_delete;
DROP INDEX IF EXISTS production_corpus_document_rubric_idx;
DROP INDEX IF EXISTS production_corpus_document_time_idx;
DROP INDEX IF EXISTS production_corpus_entry_key_idx;

ALTER TABLE production_corpus_entries RENAME TO production_corpus_entries_v39;
ALTER TABLE production_corpus_documents RENAME TO production_corpus_documents_v39;

CREATE TABLE production_corpus_documents (
  id TEXT PRIMARY KEY,
  language TEXT NOT NULL,
  channel TEXT NOT NULL,
  assistance TEXT NOT NULL,
  attempt_id TEXT REFERENCES semantic_task_attempts(id),
  rubric_id TEXT,
  realtime_turn_id TEXT REFERENCES realtime_conversation_turns(id) ON DELETE CASCADE,
  realtime_session_id TEXT REFERENCES realtime_conversation_sessions(id) ON DELETE CASCADE,
  response_revision INTEGER NOT NULL,
  activity_kind TEXT NOT NULL,
  media_id TEXT,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  response_text TEXT NOT NULL,
  produced_at_ms INTEGER NOT NULL,
  CHECK ((attempt_id IS NOT NULL AND rubric_id IS NOT NULL AND realtime_turn_id IS NULL AND realtime_session_id IS NULL)
      OR (attempt_id IS NULL AND rubric_id IS NULL AND realtime_turn_id IS NOT NULL AND realtime_session_id IS NOT NULL)),
  UNIQUE(attempt_id, response_revision),
  UNIQUE(realtime_turn_id, response_revision)
);

INSERT INTO production_corpus_documents
  (id,language,channel,assistance,attempt_id,rubric_id,response_revision,activity_kind,
   media_id,start_ms,end_ms,response_text,produced_at_ms)
SELECT id,language,channel,assistance,attempt_id,rubric_id,response_revision,
       trim(task_kind, '"'),media_id,start_ms,end_ms,response_text,produced_at_ms
FROM production_corpus_documents_v39;

CREATE TABLE production_corpus_entries (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES production_corpus_documents(id) ON DELETE CASCADE,
  normalized_key TEXT NOT NULL,
  display_text TEXT NOT NULL,
  start_char INTEGER NOT NULL,
  end_char INTEGER NOT NULL
);

INSERT INTO production_corpus_entries
SELECT * FROM production_corpus_entries_v39;

DROP TABLE production_corpus_entries_v39;
DROP TABLE production_corpus_documents_v39;

CREATE INDEX production_corpus_document_rubric_idx ON production_corpus_documents(rubric_id);
CREATE INDEX production_corpus_document_turn_idx ON production_corpus_documents(realtime_turn_id);
CREATE INDEX production_corpus_document_time_idx ON production_corpus_documents(language, produced_at_ms DESC);
CREATE INDEX production_corpus_entry_key_idx ON production_corpus_entries(normalized_key, document_id);

CREATE TRIGGER production_corpus_documents_fts_insert
AFTER INSERT ON production_corpus_documents BEGIN
  INSERT INTO production_corpus_documents_fts(document_id, language, response_text)
  VALUES (new.id, new.language, new.response_text);
END;

CREATE TRIGGER production_corpus_documents_fts_delete
AFTER DELETE ON production_corpus_documents BEGIN
  DELETE FROM production_corpus_documents_fts WHERE document_id = old.id;
END;
