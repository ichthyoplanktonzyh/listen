---
status: accepted
---

# Maintain the changelog only at release time

Root `CHANGELOG.md` remains the historical release ledger, but ordinary
feature, fix, refactor, planning, and documentation branches do not update it.
Git commits and pull requests already retain task-level history; forcing every
parallel task to edit the same large file caused conflicts and duplicated facts
without improving releases.

The release owner updates `CHANGELOG.md` once from merged pull requests when
publishing a contract, runtime, or product version. Core release notes emphasize
API/contract/runtime compatibility, migrations, security, and operationally
meaningful behavior. Existing changelog history remains unchanged.
