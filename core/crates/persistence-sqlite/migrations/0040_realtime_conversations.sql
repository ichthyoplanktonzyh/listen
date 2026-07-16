-- Phase 3.15.7 realtime speech provider config and local conversation facts.
-- Raw credentials never enter SQLite; profiles contain only opaque auth_ref.
CREATE TABLE IF NOT EXISTS realtime_provider_profiles (
    id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    adapter_kind TEXT NOT NULL,
    base_url TEXT NOT NULL,
    model_id TEXT NOT NULL,
    voice TEXT NOT NULL,
    auth_ref TEXT NOT NULL,
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

-- Terminal turns are facts. Corrections require a new turn/attempt rather than
-- rewriting provider/local transcript provenance in place.
CREATE TRIGGER IF NOT EXISTS trg_realtime_terminal_turn_immutable
BEFORE UPDATE ON realtime_conversation_turns
WHEN OLD.status IN ('finalized', 'interrupted', 'failed')
 AND NEW.turn_json <> OLD.turn_json
BEGIN
    SELECT RAISE(ABORT, 'terminal realtime turn is immutable');
END;
