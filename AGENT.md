# Listen Project Documentation Guide

This repository contains project-level documentation only.

## Authority

- The owner decides product direction, priorities, and product tradeoffs.
- `PRODUCT.md`, `DOMAIN.md`, `CONTEXT-MAP.md`, `JOURNEYS.md`,
  `DEVELOPMENT.md`, `ROADMAP.md`, and `STATE.md` have distinct authority.
- Do not copy executable schemas, API definitions, lock identities, source-tree
  descriptions, or transient branch status into this repository.
- Code and executable tests outrank descriptive implementation documentation.

## Maintenance

- Put each fact in one canonical document and link to it elsewhere.
- Keep `STATE.md` short and update it only at meaningful project transitions.
- Keep `ROADMAP.md` outcome-based; tasks belong in issues or Supervisor plans.
- Add a decision record only for a durable cross-repository decision. Local
  implementation decisions stay in the owning code repository.
- Do not describe publicly visible source as open source without an explicit
  license grant.
- Preserve unrelated changes. Use focused Conventional Commit subjects.
