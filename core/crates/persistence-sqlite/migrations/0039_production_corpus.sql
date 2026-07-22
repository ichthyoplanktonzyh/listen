-- Phase 3.15.5 personal production corpus.
--
-- Both tables are rebuildable local projections over append-only semantic
-- attempts. Response text lives once per document; lemma occurrences only cite
-- Unicode-scalar spans. Neither table is learning identity or capability
-- authority and both may be deleted/rebuilt without losing user facts.
CREATE TABLE IF NOT EXISTS production_corpus_documents (
  id TEXT PRIMARY KEY,
  language TEXT NOT NULL,
  channel TEXT NOT NULL,
  assistance TEXT NOT NULL,
  attempt_id TEXT NOT NULL REFERENCES semantic_task_attempts(id),
  rubric_id TEXT NOT NULL,
  response_revision INTEGER NOT NULL,
  task_kind TEXT NOT NULL,
  media_id TEXT,
  start_ms INTEGER NOT NULL,
  end_ms INTEGER NOT NULL,
  response_text TEXT NOT NULL,
  produced_at_ms INTEGER NOT NULL,
  UNIQUE(attempt_id, response_revision)
);

CREATE TABLE IF NOT EXISTS production_corpus_entries (
  id TEXT PRIMARY KEY,
  document_id TEXT NOT NULL REFERENCES production_corpus_documents(id) ON DELETE CASCADE,
  normalized_key TEXT NOT NULL,
  display_text TEXT NOT NULL,
  start_char INTEGER NOT NULL,
  end_char INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS production_corpus_document_rubric_idx
  ON production_corpus_documents(rubric_id);
CREATE INDEX IF NOT EXISTS production_corpus_document_time_idx
  ON production_corpus_documents(language, produced_at_ms DESC);
CREATE INDEX IF NOT EXISTS production_corpus_entry_key_idx
  ON production_corpus_entries(normalized_key, document_id);

CREATE VIRTUAL TABLE IF NOT EXISTS production_corpus_documents_fts USING fts5(
  document_id UNINDEXED,
  language UNINDEXED,
  response_text,
  tokenize = 'unicode61'
);

CREATE TRIGGER IF NOT EXISTS production_corpus_documents_fts_insert
AFTER INSERT ON production_corpus_documents BEGIN
  INSERT INTO production_corpus_documents_fts(document_id, language, response_text)
  VALUES (new.id, new.language, new.response_text);
END;

CREATE TRIGGER IF NOT EXISTS production_corpus_documents_fts_delete
AFTER DELETE ON production_corpus_documents BEGIN
  DELETE FROM production_corpus_documents_fts WHERE document_id = old.id;
END;
