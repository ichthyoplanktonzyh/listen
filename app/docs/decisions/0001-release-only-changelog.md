---
status: accepted
---

# Maintain the changelog only at release time

Root `CHANGELOG.md` remains the historical release ledger, but ordinary
feature, fix, refactor, planning, and documentation branches do not update it.
Git commits and pull requests already retain task-level history; forcing every
parallel frontend task to edit the same file caused conflicts, duplicated
planning, and spent agent context without improving the product.

The release owner updates `CHANGELOG.md` once from merged pull requests when
publishing an app version. App release notes emphasize user-visible features,
fixes, compatibility, migrations, and known limitations. Existing changelog
history remains unchanged.
