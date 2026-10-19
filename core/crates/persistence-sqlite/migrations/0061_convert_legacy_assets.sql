-- One-time conversion of legacy `material_assets` rows into the canonical
-- Phase 1 media rendition table. Runs only while the legacy union table still
-- exists (see `migrate`); the v59 backfill and media-registration sync keep
-- writing that table, so a database upgraded directly from v60 or a historical
-- fixture rebuilt to v58 both reach this conversion exactly once.
--
-- The legacy snapshot never carried a media type, so the kind derives it
-- deterministically; producer facts do not exist there. `INSERT OR IGNORE`
-- keeps a re-entrant run from duplicating rows already converted.

INSERT OR IGNORE INTO material_media_renditions
    (revision_id, rendition_id, origin, kind, media_type, fingerprint,
     availability, media_sha256, media_byte_size, media_id, producer_json,
     compatibility_json)
SELECT
    revision_id,
    asset_id,
    'source',
    json_extract(asset_json, '$.kind'),
    CASE json_extract(asset_json, '$.kind')
        WHEN 'video' THEN 'video/mp4'
        ELSE 'audio/mpeg'
    END,
    json_extract(asset_json, '$.fingerprint'),
    json_extract(asset_json, '$.availability'),
    NULL,
    NULL,
    json_extract(asset_json, '$.media_id'),
    NULL,
    NULL
FROM material_assets
WHERE asset_kind = 'media_rendition';

DROP TABLE IF EXISTS material_assets;
