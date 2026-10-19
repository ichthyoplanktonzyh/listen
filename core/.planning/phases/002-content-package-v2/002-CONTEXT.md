# Content Package v2 Context

## Decision

The next package generation is a material-centered release contract rather
than an expanded media resource package. One release fixes one Learning Edition
of one Material Revision and names an exact Resource DAG. Release, resource,
blob, Media Rendition, and delivery identity remain distinct.

## First Vertical Slice

Core owns the v2 contract, bounded inspection, compatibility report, and a pure
candidate Installation Plan. Gen owns deterministic v2 production. The first
slice proves three material shapes through committed examples and tests:

1. a full text-only article;
2. learning data for detached media identified by an exact rendition digest;
3. a hybrid multilingual material with reusable Base and Support-Language
   Assistance Resources.

V1 inspection and import remain available unchanged. V2 is selected explicitly
until a published consumer journey chooses it.

The learner-facing guardrail is independent of that rollout: acquisition makes
raw material usable first; package resolution or Gen production may continue in
the background. Package Installation and Learning Edition Adoption are separate
Core intents even when App later composes both behind **start learning**.

## Seam

```text
Gen release specification
  -> deterministic v2 carrier
  -> Core inspect
  -> verified release
  -> pure Installation Plan
  -> later candidate persistence adapter
```

The module interface hides archive limits, canonical JSON, content identities,
dependency closure, embedded-blob inventory, unknown-resource compatibility,
language validation, Base/Assistance rules, and delivery classification.
App receives a plan and actionable missing conditions, never a Resource DAG to
interpret.

## Non-Goals

- no hosted registry, Listing persistence, federation, moderation, or ranking;
- no implicit network fetch, URL trust, or media-rights inference;
- no signature trust policy beyond reserving detached signature space;
- no App or HTTP contract change in this slice;
- no forced projection of text-only material into the current MediaItem and
  LLTimeline persistence model;
- no learner records, active selections, generation jobs, provider runtimes, or
  local paths in a package.
