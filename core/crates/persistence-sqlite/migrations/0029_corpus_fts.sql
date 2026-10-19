-- FTS5 companion index for phrase/chunk text search over the rebuildable
-- corpus projection, replacing the LIKE '%…%' full scan. Rows mirror
-- corpus_occurrences by rowid. Triggers keep repository-level DML coherent;
-- delete_track additionally clears rows explicitly before the FK cascade so
-- coherence never depends on cascade-fired triggers.
CREATE VIRTUAL TABLE corpus_occurrences_fts USING fts5(source_snapshot);

CREATE TRIGGER corpus_occurrences_fts_ai AFTER INSERT ON corpus_occurrences BEGIN
  INSERT INTO corpus_occurrences_fts(rowid, source_snapshot)
    VALUES (new.rowid, new.source_snapshot);
END;

CREATE TRIGGER corpus_occurrences_fts_ad AFTER DELETE ON corpus_occurrences BEGIN
  DELETE FROM corpus_occurrences_fts WHERE rowid = old.rowid;
END;

CREATE TRIGGER corpus_occurrences_fts_au AFTER UPDATE ON corpus_occurrences BEGIN
  DELETE FROM corpus_occurrences_fts WHERE rowid = old.rowid;
  INSERT INTO corpus_occurrences_fts(rowid, source_snapshot)
    VALUES (new.rowid, new.source_snapshot);
END;

INSERT INTO corpus_occurrences_fts(rowid, source_snapshot)
  SELECT rowid, source_snapshot FROM corpus_occurrences;
