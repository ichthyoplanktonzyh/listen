# listen-gen Agent Guide

## Development roles

- The owner decides product direction and scope.
- The Supervisor owns architecture, decomposition, Worker selection, review,
  independent validation, documentation, and authorized Git/release delivery.
- Source, test, schema, script, and runtime-configuration changes belong to the
  configured implementation Worker. Worker is a replaceable role; a current
  OpenCode or model choice is execution configuration rather than project
  semantics.
- The cross-repository operating model is canonical in
  `ichthyoplanktonzyh/listen/DEVELOPMENT.md`.

## First read

- Read `CONTEXT.md` for content-production terminology.
- Shared product semantics, context ownership, learner journeys, development
  policy, and the project roadmap are canonical in
  `ichthyoplanktonzyh/listen`.
- `contracts.lock.json` identifies the Content Package contract consumed here;
  shared schemas are never copied into this repository.

## Mission

Provide the content-production path intended to become Listen's open producer:
generate expensive, reusable language-learning resources and package them for
`listen-core`. Keep model/provider implementations replaceable and keep the
exchange contract stable. Do not describe the repository as open source until
the owner has added an explicit license grant.

## Contract ownership

- `listen-core/contracts/content-package/v1` and
  `listen-core/contracts/content-package/v2` are the only schema authorities.
- Do not copy either schema generation into this repository.
- Update `contracts.lock.json` when a pinned schema identity/version changes.
- V1 remains the default compatibility output. V2 is selected explicitly and
  is assembled only from a caller-owned Release Specification.
- Package output must contain only typed, allowlisted resources and declared
  content-addressed blobs.

## Safety and privacy

- Never include local filesystem paths, secrets, raw provider responses, or
  learner facts in a package.
- Unknown LLTimeline artifacts produce warnings; never forward their payloads.
- Tests must be deterministic and must not use paid/live model calls.

## Scope discipline

The compatibility converter is not the production pipeline. Do not copy the
old `timeline-production` tree here. Move generation capabilities in coherent
later slices behind the package contract.

## Git

- Preserve unrelated work.
- Use focused changes and Conventional Commit subjects when asked to commit.
- Do not commit, push, or publish unless explicitly requested.
