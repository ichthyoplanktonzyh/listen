# M6 Fault Recovery Verification

- Date: 2026-06-09
- Platform: macOS Apple Silicon

| Failure | Current behavior |
|---|---|
| Dictionary timeout/offline/no result | Five-second timeout or null result; playback, status, and diagnosis remain available |
| Core startup failure | Desktop shows a core-unavailable message; media_kit playback remains usable |
| Port collision | Sidecar requests an OS-assigned loopback port |
| Database migration failure | Startup fails explicitly; pre-migration backup remains available |
| Database unavailable or read-only | Structured repository error with correlation ID is logged |
| Media moved/deleted or decode failure | media_kit error stream is shown in the desktop status area |
| Subtitle content changes | New content fingerprint creates a new track version |
| Duplicate import | Same media and fingerprint return the existing track |

API errors are structured and written to the exportable core log. Backup and
restore instructions are in `docs/release/backup-recovery.md`.
