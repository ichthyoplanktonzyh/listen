CREATE TABLE IF NOT EXISTS llm_sense_group_sentence_checkpoints (
    fingerprint TEXT PRIMARY KEY NOT NULL,
    partition_json TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_llm_sentence_checkpoints_updated
    ON llm_sense_group_sentence_checkpoints(updated_at_ms);
