# Listen Roadmap

> Current stage: scope reduction and consolidation, 2026-10-21.

This roadmap describes current execution priorities. [MODEL.md](MODEL.md),
[PRODUCT.md](PRODUCT.md), and [JOURNEYS.md](JOURNEYS.md) describe the broader
product direction; they do not require simultaneous implementation of every
capability. Previous plans and their task queues are not inherited.

## 1. Reset the documentation system

Completion means:

- README provides one current entry point;
- root product definitions, architecture, development guides, and protocols
  have clear, distinct responsibilities;
- old planning, handoffs, phase reports, retired proposals, and duplicated
  project-level module documents are deleted;
- retained local links resolve, and code/test documentation references point
  to the retained current guides;
- runtime behavior and release artifacts are unchanged.

## 2. Choose the main-branch scope

Inventory implemented features before selecting removals. For each capability,
identify its learner value, maturity, UI entry points, runtime dependencies,
contracts, stored data, and tests.

Completion means the owner has selected the core journey and agreed which
capabilities stay, need repair, or move to separate branches. No old milestone
or feature checklist determines that selection.

## 3. Simplify and deepen the selected journey

Move deferred implementations, their exclusive dependencies, and their tests
out of main in coherent changes. Preserve learner-owned data and required
compatibility; reducing UI scope must not silently erase facts.

Completion means a fresh install can complete the selected journey reliably,
including failure recovery and reopening saved work. Verify the packaged
application as well as the code. Scope expands only after this baseline is
accepted by the owner.
