# Backup And Recovery

Quit LLPlayerNext before copying or replacing its database.

## Manual Backup

Copy:

```text
~/Library/Application Support/LLPlayerNext/llplayernext.sqlite
```

to a safe location. Keep the file name and timestamp together.

## Restore

1. Quit LLPlayerNext and confirm no `api-http` process remains.
2. Move the current database aside.
3. Copy the selected backup to the standard database path.
4. Launch LLPlayerNext and verify media, progress, and one word profile.

Before every schema upgrade, the sidecar creates
`llplayernext.sqlite.pre-migration.bak`. If migration fails, quit the app,
replace the database with this file, and retain the failed database for
diagnosis.

## Portable Vocabulary Assets

Version 0.3.0 adds `Export vocabulary assets` and `Import vocabulary assets` in
the desktop menu. The versioned JSON file contains word profiles, status
history, source sentence snapshots, and current context observations. It does
not contain media or subtitle files.

Import is idempotent and merges with local assets. Newer profile timestamps win;
equal timestamps retain the local state. Sources and history are deduplicated.
The exported JSON can be restored into an empty database without any original
media or subtitle files.

Milestone 1.8 exports vocabulary asset bundle version 3, which adds unified
word and phrase assets. Version 3 is the current supported recovery format.
Repeated imports preserve newer local state, merge user definitions and notes
by their independent timestamps, deduplicate history, and merge matching source
snapshots using the earliest first-seen time, latest last-seen time, and largest
encounter count.
