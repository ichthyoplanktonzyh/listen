CREATE TABLE subtitle_tracks (
  id TEXT PRIMARY KEY NOT NULL,
  media_id TEXT NOT NULL REFERENCES media_items(id) ON DELETE CASCADE,
  fingerprint TEXT NOT NULL,
  language TEXT,
  source TEXT NOT NULL
  ,UNIQUE(media_id, fingerprint)
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

CREATE INDEX idx_subtitle_timeline ON subtitle_sentences(track_id, start_ms, end_ms);

CREATE TABLE dictionary_cache (
  id TEXT PRIMARY KEY NOT NULL,
  language TEXT NOT NULL,
  normalized_lemma TEXT NOT NULL,
  provider TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  cached_at_ms INTEGER NOT NULL,
  UNIQUE(language, normalized_lemma, provider)
);
