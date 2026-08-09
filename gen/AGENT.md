# listen-gen Agent Guide

## First read

- Read `CONTEXT.md` for content-production terminology.
- Shared product semantics and context ownership are canonical in
  `listen-core/PRODUCT.md`, `listen-core/CONTEXT.md`, and
  `listen-core/CONTEXT-MAP.md`.
- `contracts.lock.json` identifies the Content Package contract consumed here;
  shared schemas are never copied into this repository.

## Mission

Provide the content-production path intended to become Listen's open producer:
generate expensive, reusable language-learning resources and package them for
`listen-core`. Keep model/provider implementations replaceable and keep the
exchange contract stable. Do not describe the repository as open source until
the owner has added an explicit license grant.

## Contract ownership

- `listen-core/contracts/content-package/v1` is the only schema authority.
- Do not copy the schema into this repository.
- Update `contracts.lock.json` when the pinned schema identity/version changes.
- Package output must contain only typed, allowlisted resources.

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
