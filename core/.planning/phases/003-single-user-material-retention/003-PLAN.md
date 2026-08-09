# Single-user Material Retention Plan

## Contract And Domain

1. Add explicit nullable Personal Library membership evidence to the media
   read model.
2. Let registration request retained or temporary membership while defaulting
   an omitted value to retained for compatibility.
3. Add idempotent retain and unretain learner-intent operations for a registered
   media item.
4. Define not-found and invalid-request failures without leaking local paths.

## Application And Persistence

1. Keep registration independent from library projection policy.
2. Make `listMediaLibrary` return retained items only.
3. Add a forward migration that marks every existing media row retained.
4. Preserve the original retention timestamp across repeated retained
   registration and repeated retain operations.
5. Make unretain remove membership only; every dependent learner-owned or
   resource record must remain queryable.

## HTTP

1. Route the new operations through `application`; route handlers own no
   retention policy.
2. Keep method/path parity exact with the canonical OpenAPI contract.
3. Cover omitted/default retain behavior as well as explicit temporary
   registration.

## Acceptance

- A new registration with explicit temporary intent can be read by media ID
  but is absent from `listMediaLibrary`.
- Retaining that item makes it appear exactly once in the library.
- Retaining again is idempotent and preserves the original membership time.
- Unretaining removes it from the library but leaves media, progress, subtitle
  and representative learner-owned records intact.
- Retaining and unretaining perform no source-file operation; the original path
  remains a separately observable local binding.
- Unretaining again is idempotent.
- Registration with no retain field behaves as before and appears in the
  library.
- Every pre-migration media row remains in the library after upgrade.
- The change is contract-minor; API generation and runtime version remain
  unchanged until release packaging decides otherwise.
- Focused domain/application/persistence/HTTP tests, contract validation,
  formatting and strict Rust gates pass without credentials or model credit.

## Handoff

Core will hand App the exact contract version, methods/paths, request/response
examples, migration semantics, Core commit and immutable artifact identities.
The App integration must prove ordinary open, folder scanning and acquisition
stay temporary; only explicit Keep retains, after a verified managed copy or an
explicit reference-in-place choice. A later enrichment/adoption slice will
expose one **generate and use** intent and show an Edition choice only for real
alternatives or updates.
