# Structure

| Path | Current responsibility |
|---|---|
| `crates/domain` | stable domain records and invariants |
| `crates/application` | use cases, repositories, provider-neutral ports |
| `crates/api-http` | loopback composition, routes, handshake, health |
| `crates/api-events` | event envelopes |
| `crates/persistence-sqlite` | SQLite repositories and migrations |
| `crates/subtitle-core` | subtitle parsing/tokenization |
| `crates/diagnosis-core` | deterministic diagnosis |
| `crates/speech-analysis` | timing, speech, phonetic analysis |
| `crates/*-provider` | dictionary, embedding, LLM, realtime, syntax adapters |
| `crates/local-runtime` | local capability/runtime lifecycle |
| `crates/writing-feedback` | writing feedback behavior |
| `contracts` | canonical HTTP/event/player/resource schemas |
| `scripts/timeline-production` | production pipeline |
| `scripts/forced-align` | alignment research tooling |
| `scripts/syntactic-analysis` | syntax capability tooling |
| `scripts/release_artifacts.py` | deterministic release packaging/verification |
| `testdata` | committed license-clear fixtures |
| `docs/decisions` | append-only ADRs |
| `.planning` | current core project memory |

Paths under `.planning/archive/monorepo-baseline` are historical and never used
to infer current physical structure.
