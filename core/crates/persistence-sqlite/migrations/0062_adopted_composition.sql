-- Phase 1 Slice 2 schema cutover (contract 4.0.0): durable adopted
-- composition backing.
--
-- 1. `material_document_renditions` moves from inline text to exact blob
--    facts: `digest` (lowercase hex SHA-256) and `byte_size` replace the
--    stored `text_bytes`/`text_sha256`/`text_byte_size` columns. Existing
--    rows are converted by the Rust migration (SHA-256 of the stored text
--    bytes); the source asset binding column is kept and re-validated.
--
-- 2. `capability_attempts` gains the honest terminal states `cancelled` and
--    `superseded` in the status CHECK and a monotonic per-attempt
--    `attempt_sequence` column so attempt identities never collide within
--    the same millisecond. Existing rows are copied with sequence 0.
--
-- 3. `package_rendition_blobs` stores the exact embedded Document/Media
--    Rendition blob of every present rendition of an installed release, so
--    adopted reading/audio stays readable after the source carrier is
--    deleted. The parent references use RESTRICT like the other package
--    lifecycle tables.
--
-- Every statement is idempotent: historical regression fixtures deliberately
-- lower only `user_version` on an already-migrated database and re-run the
-- chain, so the schema must be re-entrant. The table rebuilds are guarded in
-- Rust (see `migrate`): they run only while the v1 layout still exists.

CREATE TABLE IF NOT EXISTS package_rendition_blobs (
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  rendition_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  digest TEXT NOT NULL,
  size_bytes INTEGER NOT NULL
    CHECK (size_bytes >= 0),
  body BLOB NOT NULL,
  PRIMARY KEY (material_id, release_id, rendition_id),
  FOREIGN KEY (material_id, release_id)
    REFERENCES package_installations(material_id, release_id)
    ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_package_rendition_blobs_material
  ON package_rendition_blobs(material_id);
