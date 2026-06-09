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
