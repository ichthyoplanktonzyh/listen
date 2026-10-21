# Project State

> Updated: 2026-10-21 (Asia/Shanghai).

## Current focus

The owner has selected **scope reduction and consolidation** as the next stage.
The aim is a smaller, reliable product with greater depth in its core learner
journey. Existing implementation breadth does not establish current priority.

The first step is resetting the documentation system:

- root documents provide the single product, architecture, development, and
  project-coordination entry point;
- old planning, handoffs, phase reports, retired proposals, and release logs
  are removed rather than archived or converted into new requirements;
- necessary current contracts, fixture instructions, and third-party notices
  remain with the files they describe;
- product definitions remain direction, not a claim of implementation or a
  commitment to deliver all capabilities during this stage.

## Implementation baseline

App, Core, and Gen share one repository and ship as one macOS application.
The published [v0.7.0-dev.1 preview](https://github.com/ichthyoplanktonzyh/listen/releases/tag/v0.7.0-dev.1)
targets macOS 26+ on Apple Silicon. Runtime requirements are documented in the
[distribution guide](docs/development/dev-preview-distribution.md).

This documentation reset changes no feature behavior, schema, migration,
learner data, or published release.

## Next work

Inventory current features and their maturity, dependencies, and contribution
to the core learner journey. Agree the main-branch scope with the owner, then
move deferred implementations out of that scope while preserving user data.
No feature is selected for removal by this documentation change.
