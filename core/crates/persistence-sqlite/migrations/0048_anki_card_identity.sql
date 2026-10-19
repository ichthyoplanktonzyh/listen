ALTER TABLE anki_review_items
  ADD COLUMN card_ordinal INTEGER NOT NULL DEFAULT 0;

CREATE UNIQUE INDEX anki_review_items_guid_ordinal_idx
  ON anki_review_items(guid, card_ordinal);
