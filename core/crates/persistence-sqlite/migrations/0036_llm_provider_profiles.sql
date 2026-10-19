-- Phase 3.12 vendor-neutral LLM provider profiles.
--
-- Stores only routing/config metadata and an OPAQUE keychain reference
-- (`auth_ref`). The raw credential never reaches this table: it is written to
-- the OS keychain through a write-only path and resolved at call time by a
-- SecretStore. There is deliberately no secret column, and `profile_json`
-- serializes an `LlmProviderProfile`, which has no secret field by
-- construction (shared context §3.4).
CREATE TABLE IF NOT EXISTS llm_provider_profiles (
    id                TEXT PRIMARY KEY,
    display_name      TEXT NOT NULL,
    adapter_kind      TEXT NOT NULL,
    base_url          TEXT NOT NULL,
    model_id          TEXT NOT NULL,
    -- Opaque secure-store reference, never the secret. NULL for keyless
    -- (typically local) endpoints.
    auth_ref          TEXT,
    created_at_ms     INTEGER NOT NULL,
    profile_json      TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_llm_provider_profiles_created
    ON llm_provider_profiles (created_at_ms);
