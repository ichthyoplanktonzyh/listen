-- Phase 1 canonical material model (contract 4.0.0).
--
-- Replaces the temporary inline `material_assets` union with the canonical
-- Source Asset + Document/Media Rendition model, adds durable capability
-- attempt and Source Identity tables, and migrates every legacy
-- `media_rendition` asset row into the new media rendition table. The v59
-- backfill and media-registration sync keep writing the old `material_assets`
-- rows on fresh databases; this migration runs after them in upgrade order
-- and owns the one-time conversion.
--
-- Every statement is idempotent: historical regression fixtures deliberately
-- lower only `user_version` on an already-migrated database and re-run the
-- chain, so the schema must be re-entrant. The row conversion itself is
-- guarded in Rust (see `migrate`): it runs only while the legacy
-- `material_assets` table still exists.

CREATE TABLE IF NOT EXISTS material_source_assets (
    revision_id     TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    asset_id        TEXT NOT NULL,
    media_type      TEXT NOT NULL,
    byte_length     INTEGER NOT NULL,
    sha256_digest   TEXT NOT NULL,
    binding_json    TEXT NOT NULL CHECK (json_valid(binding_json)),
    availability_json TEXT NOT NULL CHECK (json_valid(availability_json)),
    created_at_ms   INTEGER NOT NULL,
    PRIMARY KEY (revision_id, asset_id)
);

CREATE TABLE IF NOT EXISTS material_document_renditions (
    revision_id       TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    rendition_id      TEXT NOT NULL,
    origin            TEXT NOT NULL CHECK (origin IN ('source', 'derived')),
    media_type        TEXT NOT NULL,
    language          TEXT,
    text_bytes        BLOB NOT NULL,
    text_sha256       TEXT NOT NULL,
    text_byte_size    INTEGER NOT NULL,
    source_asset_id   TEXT,
    producer_json     TEXT CHECK (producer_json IS NULL OR json_valid(producer_json)),
    compatibility_json TEXT CHECK (compatibility_json IS NULL OR json_valid(compatibility_json)),
    PRIMARY KEY (revision_id, rendition_id)
);

CREATE TABLE IF NOT EXISTS material_media_renditions (
    revision_id       TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    rendition_id      TEXT NOT NULL,
    origin            TEXT NOT NULL CHECK (origin IN ('source', 'derived')),
    kind              TEXT NOT NULL CHECK (kind IN ('audio', 'video')),
    media_type        TEXT NOT NULL,
    fingerprint       TEXT NOT NULL,
    availability      TEXT NOT NULL CHECK (availability IN ('available', 'missing', 'archived')),
    media_sha256      TEXT,
    media_byte_size   INTEGER,
    media_id          TEXT,
    producer_json     TEXT CHECK (producer_json IS NULL OR json_valid(producer_json)),
    compatibility_json TEXT CHECK (compatibility_json IS NULL OR json_valid(compatibility_json)),
    PRIMARY KEY (revision_id, rendition_id)
);

CREATE TABLE IF NOT EXISTS capability_attempts (
    material_id           TEXT NOT NULL REFERENCES learning_materials(id) ON DELETE RESTRICT,
    attempt_id            TEXT NOT NULL,
    capability            TEXT NOT NULL CHECK (capability IN ('read', 'listen', 'watch', 'synchronized_read_listen')),
    status                TEXT NOT NULL CHECK (status IN ('running', 'succeeded', 'failed')),
    started_at_ms         INTEGER NOT NULL,
    finished_at_ms        INTEGER,
    failure_reason        TEXT,
    producer_tool_id      TEXT,
    producer_tool_version TEXT,
    PRIMARY KEY (material_id, attempt_id)
);

CREATE INDEX IF NOT EXISTS idx_capability_attempts_material ON capability_attempts (material_id);

CREATE TABLE IF NOT EXISTS source_identity_mappings (
    source_id             TEXT NOT NULL,
    item_id               TEXT NOT NULL,
    evidence_json         TEXT NOT NULL CHECK (json_valid(evidence_json)),
    material_id           TEXT NOT NULL REFERENCES learning_materials(id) ON DELETE RESTRICT,
    material_revision_id  TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    mapped_at_ms          INTEGER NOT NULL,
    PRIMARY KEY (source_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_source_identity_mappings_material ON source_identity_mappings (material_id);
CREATE INDEX IF NOT EXISTS idx_material_document_renditions_revision ON material_document_renditions (revision_id);
CREATE INDEX IF NOT EXISTS idx_material_media_renditions_revision ON material_media_renditions (revision_id);
