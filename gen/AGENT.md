# Gen implementation guide

Read [the root guide](../AGENT.md) and [DEVELOPMENT.md](../DEVELOPMENT.md).
`gen/` is Listen's independently runnable Python material-production module.
It shares one repository and feature branch with `app/` and `core/`.

## Responsibilities

- Produce reusable learning resources and deterministic Content Package v3.
- Keep provider/model implementations replaceable, qualified, and separate from
  learner state and experience policy.
- Canonical schemas live only in `../core/contracts/content-package/v3/`.
  Read that authority in the same source snapshot; do not copy its schema tree.
- Build/release commands use the fresh Core contract manifest for the same
  source commit. Schema/protocol versions and artifact hashes still matter;
  separate repository releases/pin handoffs are not a development prerequisite.
- Preserve independent CLI, zipapp packaging, Python environment and optional
  heavy provider dependencies. Normal setup does not download models or enable
  paid providers.

## Safety and verification

- Packages contain only declared typed resources and content-addressed blobs;
  exclude local paths, secrets, raw provider responses and learner facts.
- Tests use deterministic fixture/fake providers, never paid/live model calls.
- Preserve honest abstention, provenance, cancellation, process reaping,
  timeouts, bounded output and deterministic packaging.
- Run `python -m unittest discover -s tests -v` from this directory in the
  configured Python >=3.11 environment. Core package compatibility and App
  consumption are exercised by root `./dev test integration`.
- Do not commit virtualenvs, model weights, generated packages, provider
  credentials or local task history. Source availability grants no license.

`CONTEXT.md` adds production-specific terms; root documents own shared product
semantics and active status/roadmap. Do not restore superseded split-repository
workflow rules from historical documents. Preserve unrelated work.
