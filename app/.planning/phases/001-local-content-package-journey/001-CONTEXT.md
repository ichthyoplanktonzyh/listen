# Local content-package journey

> Status: active
> Authority: owner-approved App journey

## User outcome

A learner who already opened a registered local media rendition can either
choose an existing `.listenpkg` or ask an installed `listen-gen` executable to
produce one. The App imports the package through Core, shows exactly what was
consumed or preserved, and leaves every imported resource as a candidate until
the learner explicitly activates it.

## Journey

1. Open a local media file so the App has both its path and Core media ID.
2. Open Subtitle resources, then Local learning package.
3. Either choose an existing `.listenpkg`, or start configured `listen-gen` for
   the current media.
4. Observe preparing, generator phases, importing, cancellation, retry, and
   typed failures without raw process or transport output entering the UI.
5. Inspect the receipt, warnings, local unsigned provenance, and unknown
   publisher/license facts.
6. Explicitly activate the imported subtitle candidate to use it for learning.

## State semantics

- `idle`: no work has started.
- `preparing`: file selection or generator startup is in progress.
- `generating`: a named machine-protocol phase is in progress.
- `importing`: Core is validating and atomically importing the package.
- `candidateReady`: import completed; no active selection has changed.
- `fingerprintMismatch`: Core rejected the package/media binding before import.
- `failed`: a typed Core or generator failure is available; retry is explicit.
- `cancelled`: the learner cancelled generator work or dismissed file choice.
- `retrying`: the last request is being restarted from its original input.

## Trust and provenance

The first slice is local-only. The App labels the source `unsigned local` and
publisher/license as unknown. Resource review/provenance is displayed only
when a canonical response or machine event supplies it; absence is shown as
unknown, never inferred from package source or generator identity.

## Compatibility and migration

This is additive. Existing Core whole-media transcription, learner recording,
and realtime conversation remain available. The pinned Core release does not
contain the requested import route, so the committed feature can run against
typed fixtures and the documented unreleased-local-Core seam; `backend.lock.json`
must remain unchanged until an immutable compatible Core release exists.
