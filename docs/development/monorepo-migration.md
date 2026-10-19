# Monorepo migration record

Owner decision: [0005](../../decisions/0005-single-repository-development.md),
accepted 2026-10-19 (Asia/Shanghai).

## Source preservation

The migration is developed on `codex/monorepo-migration` in an isolated managed
worktree. The original four checkouts are retained. Before import, each
repository received an external Git bundle backup, a binary working-tree patch,
and copies of untracked files. The documentation repository's uncommitted model
and decisions were copied into the migration worktree and saved in a separate
checkpoint commit. Its three existing local commits were retained as ancestors.

The three code repositories were fetched and their local main branches matched
origin/main at cutover. The two other App worktrees were clean and retained.
Gen's untracked `.DS_Store` was backed up but excluded from product source.

## History import

`git filter-repo` ran only in disposable clones, adding `app/`, `core/`, and
`gen/` prefixes and namespacing tags under `legacy/<module>/`. Original
repositories were not history-rewritten. Imported authorship/messages remain;
SHA identities change when tree paths change.

- [Import heads](monorepo-import.json) records original and imported main heads.
- [App SHA map](migration/app-commit-map.txt)
- [Core SHA map](migration/core-commit-map.txt)
- [Gen SHA map](migration/gen-commit-map.txt)

The maps include transformed clone refs; the active repository imports main
ancestry and legacy tags. Unmerged feature branches remain in their original
repositories and external bundles; they are not silently merged into product
main. Original repository releases, issues, PRs, artifact identities and links
remain historical authorities for those releases.

Immediately after history import, every tracked file was compared byte-for-byte
against its original checkout: App 809, Core 1,232, Gen 81; all 2,122 matched.
Subsequent migration changes are separate from those three import commits.

## Migration scope

Keep native Flutter, Cargo and Python projects and Core's canonical contract
tree. Change shared source discovery, source identity, current-source launch,
fixture integration, product assembly and release validation. Consolidate the
full-app runbook and active project coordination at the root. Preserve local
HTTP, Gen CLI/process isolation, package/protocol validation, data compatibility
and published artifact immutability. Do not combine product-model realignment
or database schema changes with source-topology migration.

## Validation

Validation is being recorded as checks complete. Compilation, automated
integration and packaged desktop smoke are distinct evidence; no unchecked
stage is treated as passing. No live model calls are part of this migration.

## Cutover

The migration branch and review are the adoption point. The original repositories
and existing local checkouts remain available. Archiving them or deleting local
worktrees is a separate owner action after adoption; this migration does not
perform those actions or overwrite a remote main branch.
