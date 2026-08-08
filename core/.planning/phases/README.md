# Core Phases

Create only backend, contract, production-pipeline, runtime, or release phases
here. Pure frontend phases belong in `listen-app`.

Completed pre-split phases are frozen under
`../archive/monorepo-baseline/phases/`.

Active phase:

- `001-offline-generation-split`: extract the first native offline generation
  vertical behind the content-package v1 contract, add candidate-only atomic
  Core import, cut consumers over, migrate richer resource producers and delete
  the legacy Core production path. Stable sequencing and ownership live in
  `001-offline-generation-split/001-ROADMAP.md`.
