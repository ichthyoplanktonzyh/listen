-- Phase 1 durable learning materials: typed text documents and media
-- renditions bundled into immutable revisions of a learner-facing material.
--
-- `learning_materials` is the durable identity; `material_revisions` are
-- immutable content snapshots; `material_assets` attach typed assets to a
-- revision in a deterministic order; `material_media_bindings` records that a
-- material uses a media id. The binding deliberately has no foreign key to
-- `media_items`: a material may reference media that is not registered, and
-- media registration changes must never cascade into durable learning records.
--
-- `current_revision_id` is DEFERRED because the material/revision reference is
-- circular: a material points at its current revision while every revision
-- points back at its material. Deferring the forward edge lets a material and
-- its first revision be inserted in either order inside one transaction.
-- RESTRICT (never CASCADE or SET NULL) keeps learner history durable when a
-- referenced revision or material is deleted.
--
-- `retained_at_ms` is nullable Personal Library membership evidence; the
-- timestamp checks mirror the domain invariants: updates never precede
-- creation, and retention, when present, sits between creation and the latest
-- update. `asset_kind` admits exactly the two typed asset shapes and
-- `asset_json` must always be valid JSON.
--
-- A PRIMARY KEY on a SQLite rowid table does not imply NOT NULL, so every
-- identifier column is declared NOT NULL explicitly: a NULL identifier is
-- never a valid row.
CREATE TABLE IF NOT EXISTS learning_materials (
  id TEXT PRIMARY KEY NOT NULL,
  current_revision_id TEXT NOT NULL
    REFERENCES material_revisions(id)
    ON DELETE RESTRICT
    DEFERRABLE INITIALLY DEFERRED,
  retained_at_ms INTEGER,
  created_at_ms INTEGER NOT NULL,
  updated_at_ms INTEGER NOT NULL,
  CHECK (updated_at_ms >= created_at_ms),
  CHECK (retained_at_ms IS NULL OR retained_at_ms >= created_at_ms),
  CHECK (retained_at_ms IS NULL OR retained_at_ms <= updated_at_ms)
);

CREATE TABLE IF NOT EXISTS material_revisions (
  id TEXT PRIMARY KEY NOT NULL,
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  title TEXT NOT NULL,
  created_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS material_assets (
  revision_id TEXT NOT NULL
    REFERENCES material_revisions(id)
    ON DELETE RESTRICT,
  ordinal INTEGER NOT NULL
    CHECK (ordinal >= 0),
  asset_id TEXT NOT NULL,
  asset_kind TEXT NOT NULL
    CHECK (asset_kind IN ('document_text','media_rendition')),
  asset_json TEXT NOT NULL
    CHECK (json_valid(asset_json)),
  PRIMARY KEY (revision_id, ordinal),
  UNIQUE (revision_id, asset_id)
);

CREATE TABLE IF NOT EXISTS material_media_bindings (
  media_id TEXT PRIMARY KEY NOT NULL,
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_material_revisions_material_id
  ON material_revisions(material_id);

CREATE INDEX IF NOT EXISTS idx_material_media_bindings_material_id
  ON material_media_bindings(material_id);
