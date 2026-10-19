# Concerns

## Active

1. Some retained scripts and long-term docs still reference the pre-split
   Flutter/monorepo layout and need a focused standalone-core audit.
2. GitHub-hosted Actions cannot currently start because of billing/spending;
   strict local validation is the operational gate.
3. The current `dart-dio` generator spike failed typing/build quality gates;
   handwritten consumer compatibility remains necessary.
4. Cross-repository release discipline is new and needs repeated use before the
   old monorepo can be safely archived.
5. Runtime artifacts are macOS arm64 only at the current baseline.

## Watch

- contract growth and unused schemas;
- route/schema drift;
- provider-specific behavior leaking through application interfaces;
- heavy research dependency leakage into consumer runtime;
- persistence migrations that weaken durable learning-history invariants.
