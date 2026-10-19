CREATE TABLE review_settings (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  new_cards_per_day INTEGER NOT NULL,
  reviews_per_day INTEGER NOT NULL
);

INSERT INTO review_settings(singleton, new_cards_per_day, reviews_per_day)
VALUES (1, 20, 200);

CREATE TABLE anki_decks (
  deck_id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  parent_deck_id TEXT
);

CREATE TABLE anki_review_items (
  item_id TEXT PRIMARY KEY REFERENCES review_items(id) ON DELETE CASCADE,
  guid TEXT NOT NULL,
  note_id INTEGER NOT NULL,
  card_id INTEGER NOT NULL,
  deck_id TEXT NOT NULL REFERENCES anki_decks(deck_id),
  note_model_id INTEGER NOT NULL,
  note_fields_json TEXT NOT NULL,
  tags_json TEXT NOT NULL,
  media_json TEXT NOT NULL,
  source_package TEXT NOT NULL,
  imported_at_ms INTEGER NOT NULL,
  UNIQUE(guid, card_id)
);

CREATE INDEX anki_review_items_deck_idx
  ON anki_review_items(deck_id, item_id);

CREATE TABLE anki_review_history (
  revlog_id INTEGER PRIMARY KEY,
  item_id TEXT NOT NULL REFERENCES review_items(id) ON DELETE CASCADE,
  reviewed_at_ms INTEGER NOT NULL,
  rating INTEGER NOT NULL,
  interval INTEGER NOT NULL,
  last_interval INTEGER NOT NULL,
  ease INTEGER NOT NULL,
  time_ms INTEGER NOT NULL,
  review_type INTEGER NOT NULL
);

CREATE INDEX anki_review_history_item_idx
  ON anki_review_history(item_id, reviewed_at_ms);
