CREATE TABLE pronunciation_analysis (
  sentence_id TEXT PRIMARY KEY REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  provider_id TEXT NOT NULL,
  provider_version TEXT NOT NULL,
  analysis_json TEXT NOT NULL,
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

CREATE TABLE speech_rule_confirmations (
  sentence_id TEXT NOT NULL REFERENCES subtitle_sentences(id) ON DELETE CASCADE,
  rule_id TEXT NOT NULL,
  confirmation_json TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  PRIMARY KEY(sentence_id, rule_id)
);

CREATE INDEX pronunciation_analysis_provider_idx
  ON pronunciation_analysis(provider_id, provider_version);
CREATE INDEX word_timings_source_idx ON word_timings(timing_source);
