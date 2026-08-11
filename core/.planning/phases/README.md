# Core Phases

Create only backend, contract, production-pipeline, runtime, or release phases
here. Pure frontend phases belong in `listen-app`.

Completed pre-split phases are frozen under
`../archive/monorepo-baseline/phases/`.

Completed phase:

- `001-offline-generation-split`: established the content-package v1 producer,
  candidate-only Core import, consumer cutover, rich resources, and legacy
  production retirement.
- `002-content-package-v2`: established the material-centered v2 Release contract,
  bounded Core inspection and Installation Plan, explicit Gen production, and a
  credential-free cross-repository round trip.
- `003-single-user-material-retention`: separated Temporary Material
  registration from explicit Personal Library membership for media, preserved
  upgraded libraries and learner-owned state, and published contract `3.1.0`
  in `v0.7.0-phase1.1`.
- `004-durable-learning-material`: added the path-free Learning Material
  aggregate, immutable revisions, text/media/mixed assets, material membership
  and media resolution; contract `3.2.0` and SQLite v59 are published in
  `v0.7.0-phase1.2`.

Active phase:

- `005-durable-package-lifecycle` (active): application/domain lifecycle
  landed via `db53cdf` and the SQLite v60 adapter via PR #131 (merge
  `d435606`); the current slice wires the fixed Package Installation / Edition
  Listing / Learning Edition Adoption HTTP surface and the additive OpenAPI
  `3.3.0` contract into the real runtime. Contract `3.3.0` is not yet
  published; App pinning, App client/UI, real three-repository acceptance and
  release/closeout remain subsequent slices, so no `005-CLOSEOUT.md` exists.
