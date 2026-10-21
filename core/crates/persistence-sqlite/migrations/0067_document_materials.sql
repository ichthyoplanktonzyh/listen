-- Fresh-store extension for the document-material recovery branch.
-- Source assets, media renditions, package lifecycle, and the shared
-- structured-reading resources are created by 0064_listening_focus.sql.

CREATE TABLE material_document_renditions (
    revision_id       TEXT NOT NULL REFERENCES material_revisions(id) ON DELETE RESTRICT,
    rendition_id      TEXT NOT NULL,
    origin            TEXT NOT NULL CHECK (origin IN ('source', 'derived')),
    media_type        TEXT NOT NULL,
    language          TEXT,
    digest            TEXT NOT NULL,
    byte_size         INTEGER NOT NULL CHECK (byte_size >= 0),
    source_asset_id   TEXT,
    producer_json     TEXT CHECK (producer_json IS NULL OR json_valid(producer_json)),
    compatibility_json TEXT CHECK (compatibility_json IS NULL OR json_valid(compatibility_json)),
    PRIMARY KEY (revision_id, rendition_id)
);

CREATE INDEX idx_material_document_renditions_revision
  ON material_document_renditions (revision_id);
