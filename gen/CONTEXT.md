# Listen Gen Context

Canonical Listen product purpose, shared language, context ownership, learner
journeys, development policy, and the project roadmap live in
[`ichthyoplanktonzyh/listen`](https://github.com/ichthyoplanktonzyh/listen).
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

**Release Specification**:
The caller-owned declaration of the exact Material Revision, Learning Edition,
entrypoints, resource roles and languages, and delivery choices required to
assemble one Package Release. Listen Gen validates this specification but does
not infer cross-source material equivalence or Learner adoption.
_Avoid_: Generation Recipe, Package Installation, active selection

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

**Production Input Projection**:
A provider-specific rendering of the exact ordered spans of one Structured
Reading (for example plain text for TTS or Markdown for a text-model
producer), produced inside a Generation Run only. A projection is never
persisted as a Rendition, Resource, or package authority; its hash and
configuration flow into resource provenance so the exact provider input stays
reproducible.
_Avoid_: Extracted document text, canonical intermediate format

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
