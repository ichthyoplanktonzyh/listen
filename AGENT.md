# Listen Project Documentation Guide

This repository contains project-level documentation only.

## Authority

- The owner decides product direction, priorities, and product tradeoffs.
- `MODEL.md`, `PRODUCT.md`, `DOMAIN.md`, `CONTEXT-MAP.md`, `JOURNEYS.md`,
  `ROADMAP.md`, and `STATE.md` have distinct authority.
- `MODEL.md` owns the project-level theoretical model. Product, domain,
  architecture, journey, roadmap, and state documents must not contradict it.
- Do not copy executable schemas, API definitions, lock identities, source-tree
  descriptions, or transient branch status into this repository.
- Code and executable tests outrank descriptive implementation documentation.

## Maintenance

- Put each fact in one canonical document and link to it elsewhere.
- Treat the owner-approved model in `MODEL.md` as primary when older
  repository wording or execution plans disagree with it. Executable code may
  temporarily lag the model, but documentation must state that drift honestly.
- `DOMAIN.md` and `DOMAIN.zh-CN.md` are one bilingual glossary. English domain
  names remain the stable identifiers used by code and contracts; every domain
  language change must update both files in the same documentation change.
- Keep `STATE.md` short and update it only at meaningful project transitions.
- Keep `ROADMAP.md` outcome-based; tasks belong in issues or Supervisor plans.
- Add a decision record only for a durable cross-repository decision. Local
  implementation decisions stay in the owning code repository.
- Do not describe publicly visible source as open source without an explicit
  license grant.
- Preserve unrelated changes. Use focused Conventional Commit subjects.
