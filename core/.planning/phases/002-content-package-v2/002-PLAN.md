# Content Package v2 Plan

## Core Contract And Inspection

1. Add normative v2 release, resource-descriptor, and delivery schemas plus a
   deterministic archive profile.
2. Commit full text, detached media, and hybrid multilingual example trees.
3. Add v2 models and bounded inspection beside the unchanged v1 interface.
4. Validate canonical identities, dependency closure and acyclicity, required
   compatibility, language roles, rendition references, blob size/hash, safe
   archive paths, and honest delivery classification.
5. Produce a pure Installation Plan that reports candidate, opaque, and missing
   artifacts without persistence or activation.

## Producer And Integration

1. Pin Gen to the v2 contract without copying Core schemas.
2. Add an explicit v2 production option while retaining v1 behavior.
3. Re-envelope existing qualified generated payloads as v2 Base Resources with
   exact dependencies and provenance.
4. Prove deterministic output and run a real Gen v2 package through the Core v2
   inspector and Installation Plan.

## Acceptance

- A text-only release needs no media kind, duration, fingerprint, or subtitle.
- Detached media learning data validates without embedding media bytes and
  reports the exact missing rendition blob.
- A hybrid release distinguishes Base and Assistance Resources and carries
  explicit Content, Target, and Support Language tags.
- Release identity is independent of carrier delivery; resource identity is
  independent of payload location; blob identity is the raw-byte SHA-256.
- Required unknown resources make a release incompatible; optional unknown
  resources remain verified opaque candidates.
- Inspection performs no network or persistence work.
- Installation planning never selects or activates a resource.
- The plan is sufficient for a later material-centered interface to distinguish
  acquisition, installation and explicit Learning Edition Adoption without
  exposing package internals to App.
- V1 tests and import behavior remain unchanged.
- Normal validation is credential-free and spends no model credit.
