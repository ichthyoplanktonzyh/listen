# Listen Gen Context

The canonical Listen product purpose, shared glossary, and context map live in
`listen-core` at `PRODUCT.md`, `CONTEXT.md`, and `CONTEXT-MAP.md`.
`contracts.lock.json` identifies the canonical Content Package contract consumed
by this repository.

This glossary adds only concepts owned by content production.

## Production

**Content Producer**:
A person or organization that uses Listen Gen to create reusable Learning
Resources and Content Packages.
_Avoid_: Learner, package publisher

**Generation Input**:
The authorized material assets and existing Learning Resources supplied to one
generation operation.
_Avoid_: Personal Library, provider-native request

**Generation Recipe**:
A portable declaration of requested production capabilities, selected producers,
configuration identities, and dependency order.
_Avoid_: Local command line, model output

**Generation Run**:
One bounded execution of a Generation Recipe against declared Generation Inputs,
with progress, cancellation, warnings, and one terminal outcome.
_Avoid_: Learning Activity, background process

**Generated Resource**:
A candidate Learning Resource emitted by a Generation Run with complete Resource
Provenance.
_Avoid_: Raw provider response, activated resource

**Producer Capability**:
A declared kind of Learning Resource that a configured producer can attempt to
create for specified languages and input resources.
_Avoid_: Provider name, guaranteed output

## Quality And Failure

**Resource Qualification**:
The deterministic checks that decide whether generated output is safe and
complete enough to enter a Content Package.
_Avoid_: Human review, provider success status

**Abstention**:
An honest result stating that a requested resource could not be qualified and
was therefore not emitted.
_Avoid_: Empty resource, fabricated fallback

**Degraded Generation**:
A successful Generation Run that emits every qualified resource it can while
reporting requested resources that were skipped or abstained.
_Avoid_: Silent partial success, failed run

**Generation Failure**:
A terminal outcome in which the requested package cannot be produced safely.
It exposes a stable failure class without leaking secrets or raw provider data.
_Avoid_: Abstention, provider stderr

## Reproducibility

**Deterministic Build**:
A package build whose declared inputs, recipe, producer identities, and fixed
creation metadata produce byte-identical output.
_Avoid_: Similar output, reproducible model quality

**Production Provenance**:
The complete, portable explanation of which inputs, tools, models, versions,
and configurations produced a Generated Resource, excluding local paths,
credentials, and raw provider payloads.
_Avoid_: Debug log, quality guarantee
