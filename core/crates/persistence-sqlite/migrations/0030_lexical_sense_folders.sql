CREATE TABLE lexical_sense_folders (
    id TEXT PRIMARY KEY NOT NULL,
    lexical_entry_id TEXT NOT NULL REFERENCES lexical_entries(id) ON DELETE CASCADE,
    label TEXT NOT NULL,
    definition TEXT,
    gloss TEXT,
    external_ref TEXT,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX idx_lexical_sense_folders_entry
    ON lexical_sense_folders(lexical_entry_id, created_at_ms);

CREATE TABLE lexical_sense_folder_occurrences (
    lexical_sense_id TEXT NOT NULL REFERENCES lexical_sense_folders(id) ON DELETE CASCADE,
    lexical_occurrence_id TEXT PRIMARY KEY NOT NULL REFERENCES lexical_occurrences(id) ON DELETE CASCADE
);

CREATE TRIGGER validate_lexical_sense_folder_occurrence_parent
BEFORE INSERT ON lexical_sense_folder_occurrences
FOR EACH ROW
WHEN (
    SELECT lexical_entry_id FROM lexical_sense_folders WHERE id = NEW.lexical_sense_id
) != (
    SELECT lexical_entry_id FROM lexical_occurrences WHERE id = NEW.lexical_occurrence_id
)
BEGIN
    SELECT RAISE(ABORT, 'sense folder and occurrence must share lexical entry');
END;
