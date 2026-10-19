# Git Workflow

## Repository Baseline

Milestone 1 is recorded by:

- the initial repository commit;
- annotated tag `v0.2.0`;
- completion report `docs/release/milestone-1.md`.

Generated build artifacts, local databases, dependency caches, and generated
test media remain ignored. Release archives are regenerated from the tagged
source with `scripts/build-macos-mvp.sh`.

## Branches

- `main` contains verified milestone baselines.
- New implementation work uses short-lived `codex/<topic>` or
  `feature/<topic>` branches.
- Merge only after relevant tests and packaged smoke checks pass.

## Commits And Releases

- Keep commits scoped to one behavior or planning change.
- Use imperative commit subjects.
- Do not update `CHANGELOG.md` in ordinary task branches. The release owner
  curates it from merged pull requests when publishing a version.
- Create an annotated semantic-version tag for each releasable milestone.
- Do not commit secrets, user media, local databases, external tool binaries, or
  generated release archives.
