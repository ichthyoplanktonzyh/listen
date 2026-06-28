ALTER TABLE subtitle_sentences RENAME TO subtitle_sentences_v2;
ALTER TABLE subtitle_tracks RENAME TO subtitle_tracks_v2;

CREATE TABLE subtitle_tracks (
  id TEXT PRIMARY KEY NOT NULL,
  media_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
  fingerprint TEXT NOT NULL,
  language TEXT,
  source TEXT NOT NULL,
  UNIQUE(media_id, fingerprint)
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

INSERT INTO subtitle_tracks SELECT * FROM subtitle_tracks_v2;
INSERT INTO subtitle_sentences SELECT * FROM subtitle_sentences_v2;

DROP TABLE subtitle_sentences_v2;
DROP TABLE subtitle_tracks_v2;

CREATE INDEX idx_subtitle_timeline ON subtitle_sentences(track_id, start_ms, end_ms);
