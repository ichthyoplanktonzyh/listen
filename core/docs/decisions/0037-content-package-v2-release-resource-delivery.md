# ADR 0037: Separate Package Release, resource, blob, and delivery identity

- Status: Accepted
- Date: 2026-08-09

Content Package v2 represents exactly one immutable Package Release of one
Learning Edition for one Material Revision. The canonical release manifest,
each resource descriptor, and each payload blob have independent content
identities; a `.listenpkg` carrier may embed all, some, or none of the referenced
blob bytes without changing the Package Release identity. This preserves a
small deterministic installation unit while allowing Base Resources to be
reused across editions and allowing full, referenced, and hybrid delivery.

V2 does not extend v1's required audio/video fingerprint, duration, or Subtitle
Text Track assumptions. A valid release may begin from text, audio, video, or a
mixed material; Base and Assistance Resources are explicit roles, language tags
never default to English, external locations are untrusted acquisition hints,
and installation only produces candidates. Learning Edition Adoption is a
separate Learner intent which may follow installation behind one user-facing
action but can never be declared by package data. V1 remains a separate
supported legacy contract rather than being reinterpreted as v2.

We rejected independent layer packages plus a composition solver for the first
v2 slice because exact content-addressed resource references already provide
reuse without introducing dependency resolution policy. We also rejected a
full OCI registry model and an unconstrained claims network: v2 borrows their
descriptor and content-store ideas but keeps one closed release manifest as the
consumer interface. This decision supersedes only ADR 0036's placeholder
language for the post-v1 identity model; its open-ecosystem and future-registry
decision remains accepted.
