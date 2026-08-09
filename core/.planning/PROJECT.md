# listen-core Project Scope

This file defines the current repository mission. It does not redefine the
Listen product. Product purpose, shared language, cross-context authority,
learner journeys, development policy, and the project roadmap are canonical in
[`ichthyoplanktonzyh/listen`](https://github.com/ichthyoplanktonzyh/listen).

## Mission

`listen-core` provides the versioned semantic runtime used by Listen:

- Rust domain and application behavior;
- durable learner-owned state and rebuildable corpus projections;
- persistence and provider adapters;
- loopback HTTP and event interfaces;
- canonical wire, event, timeline, and Content Package contracts;
- reproducible Core runtime and contract release artifacts.

It consumes validated Learning Resources without depending on the tools or
models that produced them. Reusable offline content production belongs to
`listen-gen`.

## Consumers

`listen-app` consumes only versioned contracts and immutable Core artifacts.
`listen-gen` consumes the canonical Content Package schema and emits data-only
artifacts that Core can validate and install.

## Repository Principles

- domain and application behavior remain independent of transport and concrete
  providers;
- user intent and observable outcomes define consumer-facing interfaces;
- published contracts and artifacts are immutable and content-addressed;
- Learning Records outlive replaceable media, packages, and generated resources;
- model output retains provenance and never becomes stronger authority than its
  evidence supports;
- expensive reusable generation stays outside the consumer runtime;
- no production workflow depends on sibling checkouts or moving branches.

## Non-Goals

This repository does not own:

- Flutter presentation, navigation, or learner-journey composition;
- reusable offline generation providers and production recipes;
- multi-tenant accounts, community distribution, moderation, or cloud sync
  infrastructure;
- duplicated planning for `listen-app`, `listen-gen`, or the future Community
  And Sync context.
