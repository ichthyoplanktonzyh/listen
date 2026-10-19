# Core contract request

> **Owner-approved App request.** This describes App needs, not an immutable
> Core release or evidence of completed end-to-end integration.

## Operation

`POST /v1/media/{media_id}/content-packages/import`

Request body:

```json
{"package_path":"/local/path/lesson.listenpkg"}
```

The path is selected by the local learner or is temporary output owned by the
App. Core remains authoritative for path/size/archive/schema limits, exact
media fingerprint validation, atomicity, idempotency, and candidate policy.

Response fields required by the App:

```json
{
  "track": {"id":"track-local-1","media_id":"media-1","source":"content-package","status":"available","sentences":[]},
  "receipt": {
    "manifest_sha256":"sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "resources":[{"resource_id":"sha256:1111111111111111111111111111111111111111111111111111111111111111","kind":"subtitle_text_track","local_ids":["track-local-1"],"outcome":"consumed","reason":null}],
    "warnings":[]
  }
}
```

The operation must never change active resources. Stable, redacted failure
codes must distinguish fingerprint mismatch, invalid archive/schema, authority
limits, conflicts, unavailable media, and retryable infrastructure failures.
The eventual handoff must include canonical OpenAPI, contract/runtime versions,
release commit, artifact URLs/hashes, and compatibility classification.
