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
The active tree drops one inherited Git link at
`core/.claude/worktrees/refactor+flutter-frontend`: it was a historical agent
checkout pointer, not a runtime dependency, and had no `.gitmodules` entry.
The import history and original checkout remain intact. There are no Git links
in the resulting active product tree.

## Migration scope

Keep native Flutter, Cargo and Python projects and Core's canonical contract
tree. Change shared source discovery, source identity, current-source launch,
fixture integration, product assembly and release validation. Consolidate the
full-app runbook and active project coordination at the root. Preserve local
HTTP, Gen CLI/process isolation, package/protocol validation, data compatibility
and published artifact immutability. Do not combine product-model realignment
or database schema changes with source-topology migration.

## Validation

All validation ran locally on macOS Apple Silicon, without live model calls.
There is no configured GitHub Actions workflow.

| Command / check | Result |
|---|---|
| `./dev setup` | Python 3.11 environment, minimal Gen/Core test dependencies and Flutter packages prepared |
| `./dev check` | Exit 0; Flutter analysis clean; App 1,686 passed / 12 conditional integration skips; App tool suite 37 passed; Rust formatting/Clippy clean and workspace 1,300 passed; full contracts gate passed; Gen 346 passed |
| `python3 -m unittest tools.test_dev -v` | 7 passed, including ignored-file exclusion, exact committed export and probe-environment isolation |
| Core `python3 -m unittest scripts/test_release_artifacts.py` | 7 passed, including matching/mismatched runtime manifest handling |
| `./dev test integration` | 10 passed; all five required named journey assertions confirmed from structured Flutter reports |
| App release-service focused suite | 28 passed; 2 opt-in environment/compiled-define tests skipped in the ordinary focused invocation |
| Generated release-lock compiled-define test | 1 passed with a real generated lock and manifest, production loader mode, and invalid debug override |
| `./dev run` with isolated DB/support paths | Native debug App and Core started, SQLite schema 63 with 102 tables created; Flutter debugger connected; `q` closed the app and sidecar, exit 0 |
| `./dev release` from clean `849acf40083eb425cb4ab3afb96e45a99222f004` | Exit 0; isolated committed export, Core/Gen artifact verification, macOS assembly/signing, extracted-app compiled-lock check, video/audio/DB smoke all passed |

The final release configuration uses a single-line base64 Dart define carrying
the exact generated lock bytes. This was verified by the compiled production
loader and then by the actual extracted application, not only by Python hash
checks. The packaged probe reported source commit
`849acf40083eb425cb4ab3afb96e45a99222f004` and Gen artifact digest
`sha256:bd6e9a19ebf7edb6c3db1f55a6de7317b089eb755445c7e9ae7c37d3c99ff1fb`.
The product ZIP SHA-256 is
`41923a4ad86bb7bd0ae95e4bc4c63a39db55347f38428280290a0842a4b51439`.

Ordinary App skips are explicit opt-in journeys, not claimed integration
passes; the dedicated fixture integration and compiled release probes supply
that evidence. Paid/credentialed model tests remained excluded. The native
build emits existing third-party SDK warnings, but the build, signature and
packaged smoke all succeeded.

Independent GPT-6 Luna Max review verified import path/mode/blob equality,
main-ancestry and legacy-tag mapping, then reviewed source snapshot privacy,
release provenance, artifact/lock integration and packaged startup. Findings
were fixed and re-reviewed; final code review and actual package verification
are separate checks. The original repositories and working-tree edits were
retained throughout.

`git diff --check` passes for migration changes since the three import commits.
The full diff against the documentation-only old main also contains preserved
upstream whitespace/CRLF in imported historical documents, license files and
assets; those byte-preserved baseline files were not normalized gratuitously.

## Cutover

The migration branch and review are the adoption point. The original repositories
and existing local checkouts remain available. Archiving them or deleting local
worktrees is a separate owner action after adoption; this migration does not
perform those actions or overwrite a remote main branch.
