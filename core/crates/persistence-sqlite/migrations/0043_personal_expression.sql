-- Phase 3.16 durable personal expression assets.
-- Source media identifiers live only inside immutable JSON snapshots: there is
-- deliberately no FK to media/subtitle tables and therefore no source cascade.
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

CREATE INDEX idx_user_sentence_patterns_language_updated
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

CREATE INDEX idx_personal_expression_attempts_pattern_time
ON personal_expression_attempts(pattern_id, completed_at_ms DESC);
