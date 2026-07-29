CREATE TABLE pending_secret_cleanups (
    auth_ref TEXT PRIMARY KEY,
    queued_at_ms INTEGER NOT NULL,
    state TEXT NOT NULL CHECK (state IN ('reserved', 'ready'))
);
