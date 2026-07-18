-- Phase 3.15.8: derived semantic vectors. No authoritative source text or
-- learning evidence lives here; the entire table is disposable/rebuildable.
CREATE TABLE semantic_embedding_index (
  source_kind TEXT NOT NULL,
  source_id TEXT NOT NULL,
  language TEXT NOT NULL,
  channel TEXT,
  text_sha256 TEXT NOT NULL,
  model_fingerprint TEXT NOT NULL,
  dimension INTEGER NOT NULL CHECK (dimension > 0),
  vector_f32le BLOB NOT NULL,
  indexed_at_ms INTEGER NOT NULL,
  PRIMARY KEY (model_fingerprint, source_kind, source_id)
);

CREATE INDEX idx_semantic_embedding_space
  ON semantic_embedding_index(model_fingerprint, language, source_kind, channel);
