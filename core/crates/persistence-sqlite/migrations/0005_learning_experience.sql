ALTER TABLE word_profiles ADD COLUMN user_definition TEXT;
ALTER TABLE word_profiles ADD COLUMN personal_note TEXT;
ALTER TABLE word_profiles ADD COLUMN learning_updated_at_ms INTEGER NOT NULL DEFAULT 0;
