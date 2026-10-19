-- 0030 only guarded INSERT; the assign upsert (ON CONFLICT DO UPDATE) and any
-- future direct UPDATE take the UPDATE path, so parent-entry agreement must be
-- enforced there as well.
CREATE TRIGGER validate_lexical_sense_folder_occurrence_parent_update
BEFORE UPDATE ON lexical_sense_folder_occurrences
FOR EACH ROW
WHEN (
    SELECT lexical_entry_id FROM lexical_sense_folders WHERE id = NEW.lexical_sense_id
) != (
    SELECT lexical_entry_id FROM lexical_occurrences WHERE id = NEW.lexical_occurrence_id
)
BEGIN
    SELECT RAISE(ABORT, 'sense folder and occurrence must share lexical entry');
END;
