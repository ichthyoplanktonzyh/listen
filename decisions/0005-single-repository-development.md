# 0005 — Develop Listen in one repository

Status: accepted by the owner on 2026-10-19 (Asia/Shanghai).

## Context

Listen has one active owner and one integrated product, implemented by Flutter
App, Rust Core, and Python Gen. Separate repositories made one feature require
multiple branches, component releases, consumer pin updates, repeated handoffs,
duplicated runbooks, and explicit reconciliation of source states. The module
interfaces remain useful; separate Git repositories do not currently justify
their development cost.

## Decision

Use `ichthyoplanktonzyh/listen` for project documentation and the `app/`,
`core/`, and `gen/` source trees. Keep each native toolchain and Core's Cargo
workspace. Keep canonical schemas under `core/contracts/`.

A feature may update all affected modules and contracts in one branch/PR.
Daily development builds the current source together, including explicitly
identified working-tree snapshots. No component release or committed internal
commit pin is needed before local integration.

Formal product releases are built from one clean Git commit. The build emits
contract/runtime/generator manifests and product locks with exact hashes and
source identity. Generated locks are build output, not source that must be
committed in a second self-referential pin update. Published artifacts remain
immutable. Protocol versions, startup compatibility checks, data/package
migrations, and artifact validation remain explicit.

Preserve App/Core local HTTP, Gen process isolation and its independent CLI,
and the validated Content Package interface. Heavy model environments remain
outside the lightweight Core runtime. This decision does not change product
semantics or declare the Complete Learning Material model implemented.

## History and transition

Import the three code histories with directory prefixes, preserving authorship
and messages. Imported commits receive new SHA identities; retain mappings and
namespace old tags under `legacy/<module>/`. Existing repositories/releases,
issues, PRs, and local worktrees remain available as historical references.
The original repositories are not rewritten or deleted.

Root `STATE.md` and `ROADMAP.md` own active project status and outcomes. Retain
module implementation history and decisions, but replace repository-specific
handoff rules and duplicated full-app runbooks with shared development docs.

This decision supersedes rules requiring separate repository tasks, releases,
and pin handoffs before source integration. It does not supersede module
responsibilities, the product model, or published-format compatibility.
