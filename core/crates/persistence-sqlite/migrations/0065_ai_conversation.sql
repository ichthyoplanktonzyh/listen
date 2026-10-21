-- Fresh listening + conversation store. This extension is intentionally
-- incompatible with schema v64 and belongs to the separate listen-ai.sqlite.
CREATE TABLE IF NOT EXISTS transcription_models (
    id TEXT PRIMARY KEY,
    provider_id TEXT NOT NULL,
    descriptor_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS recording_assets (
    id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    duration_ms INTEGER NOT NULL CHECK (duration_ms > 0),
    created_at_ms INTEGER NOT NULL,
    asset_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS realtime_provider_profiles (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    adapter_kind TEXT NOT NULL,
    base_url TEXT NOT NULL,
    model_id TEXT NOT NULL,
    voice TEXT NOT NULL,
    auth_ref TEXT,
    created_at_ms INTEGER NOT NULL,
    profile_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS realtime_conversation_sessions (
    id TEXT PRIMARY KEY,
    profile_id TEXT NOT NULL REFERENCES realtime_provider_profiles(id) ON DELETE RESTRICT,
    language TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at_ms INTEGER NOT NULL,
    ended_at_ms INTEGER,
    session_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_realtime_sessions_started
    ON realtime_conversation_sessions(started_at_ms DESC, id);

CREATE TABLE IF NOT EXISTS realtime_conversation_turns (
    id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL REFERENCES realtime_conversation_sessions(id) ON DELETE CASCADE,
    sequence INTEGER NOT NULL,
    role TEXT NOT NULL,
    status TEXT NOT NULL,
    recording_asset_id TEXT REFERENCES recording_assets(id) ON DELETE RESTRICT,
    turn_json TEXT NOT NULL,
    UNIQUE(session_id, sequence)
);

CREATE INDEX IF NOT EXISTS idx_realtime_turns_session
    ON realtime_conversation_turns(session_id, sequence);

CREATE TRIGGER IF NOT EXISTS trg_realtime_terminal_turn_immutable
BEFORE UPDATE ON realtime_conversation_turns
WHEN OLD.status IN ('finalized', 'interrupted', 'failed')
 AND NEW.turn_json <> OLD.turn_json
BEGIN
    SELECT RAISE(ABORT, 'terminal realtime turn is immutable');
END;
