# Concerns

## Active

1. The app has a broad surface and 130 test files; future work must start from
   explicit user journeys rather than adding more unowned UI.
2. `LocalApi` remains a large handwritten compatibility boundary; code
   generation was rejected by the current spike, so typed-parser discipline is
   essential.
3. GitHub-hosted Actions cannot currently start because of billing/spending.
4. The split/release/lock workflow is new and needs repeated real feature use.
5. Packaging baseline is macOS arm64 runtime even though Flutter output may
   contain universal app code.

## Watch

- controller/coordinator overlap and disposal leaks;
- raw wire maps escaping service boundaries;
- oversized widgets or multi-domain files;
- inaccessible focus/motion/layout regressions;
- UI silently treating degraded backend capability as success;
- stale fixtures after a core contract release.
