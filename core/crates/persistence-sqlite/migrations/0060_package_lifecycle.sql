-- Phase 1 durable package lifecycle: Package Installation facts, exact
-- resource payload bodies, and the current Edition Adoption with its full
-- deterministic selection plan.
--
-- `package_installations` is the immutable installed-release fact store. The
-- primary identity is `(material_id, release_id)`: one release per Material.
-- Every query identity (`material_id`, `release_id`, `material_revision_id`)
-- is a standalone constrained column; the edition and resource/rendition fact
-- lists are path-free JSON snapshots (kept immutable by the repository, which
-- never rewrites them after first persist). `installed_at_ms` is stamped by
-- the repository at first persist and is never part of retry equality.
--
-- `package_resource_payloads` stores the exact raw BLOB of every present
-- resource body under the same `(material_id, release_id)` identity with the
-- kind/schema/digest/size facts needed to re-verify the association. One
-- resource has at most one body (the PK), missing resources have no row, and
-- payload bytes never live inside the installation/adoption JSON snapshots.
--
-- `package_adoptions` is the current adoption authority: at most one row per
-- Material (material_id is the PRIMARY KEY), referencing an installed
-- `(material_id, release_id)`, carrying the material revision, edition, the
-- adopted-at timestamp, and the complete deterministic selection plan
-- (selected_resource_ids, exclusive_selections, selected_rendition_ids) as
-- JSON. A switch to another release replaces the single row atomically; a
-- re-adopt of the same release rewrites nothing.
--
-- Every parent reference uses RESTRICT (never CASCADE or SET NULL): deleting
-- a Material, a revision, or an installation that package lifecycle facts
-- reference must be rejected, never silently cascade into durable state. The
-- composite installation FK is declared on the child table; the same
-- (material_id, release_id) pair is referenced by both payload and adoption
-- rows.
--
-- A PRIMARY KEY on a SQLite rowid table does not imply NOT NULL, so every
-- identifier column is declared NOT NULL explicitly. Timestamps are
-- non-negative. JSON columns carry a `json_valid` CHECK so malformed
-- snapshots cannot be inserted. No path, manifest, delivery hint, raw
-- validation output, or rendition media byte is stored here.
CREATE TABLE IF NOT EXISTS package_installations (
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  material_revision_id TEXT NOT NULL
    REFERENCES material_revisions(id)
    ON DELETE RESTRICT,
  release_created_at_ms INTEGER NOT NULL
    CHECK (release_created_at_ms >= 0),
  edition_json TEXT NOT NULL
    CHECK (json_valid(edition_json)),
  resources_json TEXT NOT NULL
    CHECK (json_valid(resources_json)),
  renditions_json TEXT NOT NULL
    CHECK (json_valid(renditions_json)),
  installed_at_ms INTEGER NOT NULL
    CHECK (installed_at_ms >= 0),
  PRIMARY KEY (material_id, release_id)
);

CREATE INDEX IF NOT EXISTS idx_package_installations_material_id
  ON package_installations(material_id);

CREATE TABLE IF NOT EXISTS package_resource_payloads (
  material_id TEXT NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  resource_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  schema TEXT NOT NULL,
  digest TEXT NOT NULL,
  size_bytes INTEGER NOT NULL
    CHECK (size_bytes >= 0),
  body BLOB NOT NULL,
  PRIMARY KEY (material_id, release_id, resource_id),
  FOREIGN KEY (material_id, release_id)
    REFERENCES package_installations(material_id, release_id)
    ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS package_adoptions (
  material_id TEXT PRIMARY KEY NOT NULL
    REFERENCES learning_materials(id)
    ON DELETE RESTRICT,
  release_id TEXT NOT NULL,
  material_revision_id TEXT NOT NULL
    REFERENCES material_revisions(id)
    ON DELETE RESTRICT,
  edition_json TEXT NOT NULL
    CHECK (json_valid(edition_json)),
  selected_resource_ids_json TEXT NOT NULL
    CHECK (json_valid(selected_resource_ids_json)),
  exclusive_selections_json TEXT NOT NULL
    CHECK (json_valid(exclusive_selections_json)),
  selected_rendition_ids_json TEXT NOT NULL
    CHECK (json_valid(selected_rendition_ids_json)),
  adopted_at_ms INTEGER NOT NULL
    CHECK (adopted_at_ms >= 0),
  FOREIGN KEY (material_id, release_id)
    REFERENCES package_installations(material_id, release_id)
    ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_package_adoptions_release_id
  ON package_adoptions(release_id);
