-- Local realtime cascade profiles do not have a provider credential. Rebuild
-- the parent table so auth_ref can honestly be NULL while preserving existing
-- remote profiles and the session foreign key target.
CREATE TABLE realtime_provider_profiles_v53 (
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

INSERT INTO realtime_provider_profiles_v53
    (id, display_name, adapter_kind, base_url, model_id, voice, auth_ref, created_at_ms, profile_json)
SELECT
    id, display_name, adapter_kind, base_url, model_id, voice, auth_ref, created_at_ms, profile_json
FROM realtime_provider_profiles;

DROP TABLE realtime_provider_profiles;
ALTER TABLE realtime_provider_profiles_v53 RENAME TO realtime_provider_profiles;
