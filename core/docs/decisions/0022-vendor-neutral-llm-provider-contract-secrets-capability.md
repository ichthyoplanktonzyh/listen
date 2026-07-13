# ADR 0022: Vendor-neutral LLM Provider — Contract, Secrets, and Capability Semantics

- Date: 2026-07-12
- Status: Accepted for Phase 3.12
- Context: Phase 3.11–3.18 shared context §3.3 (vendor neutrality) / §3.4
  (secrets & degradation) / §3.5 (judge qualification) / §3.6 (seam reservation);
  final discussion (`.planning/discuss/four-channel-product-and-vendor-neutral-llm-final.zh.md`)
  §7/§8/§9; ADR 0021 (four-layer separation). GitHub reference survey
  (2026-07-12): rust-genai, LiteLLM, aichat.

## Context

Phases 3.13–3.15 will drive rubric generation and semantic judgment through an
external LLM. The domain must accept remote or local models as a semantic
capability source **without binding to any vendor, SDK, model name, or wire
format**. A survey of mature projects shows two philosophies: rust-genai
defines its own neutral types and maps each provider natively, while LiteLLM
normalizes everything to the OpenAI wire format. The latter, used as an
internal contract, would recapture the domain in one provider's shape — exactly
what final §7.1 forbids. No mature project stores keys in the OS keychain
(genai uses env vars; aichat uses a plaintext config file), and none probes a
custom endpoint's real structured-output support — they trust configuration.

## Decision

### 1. Two-layer neutral seam; no wire type above the adapter

- `LlmChatAdapter` (application) is the **wire seam**: one implementation per
  protocol family, translating a neutral `StructuredChatRequest` to/from the
  provider and mapping failures to the standardized error taxonomy.
- `SemanticRubricProvider` / `SemanticJudgeProvider` (application) are the
  **application seams** that `AppServices` consumes.
- A single generic composition `LlmSemanticProvider<A: LlmChatAdapter>` builds
  the prompt + output schema and parses results into drafts **once**, over any
  adapter. Swapping the adapter cannot change semantics — that is the neutrality
  proof (`crates/llm-provider/tests/contract.rs`).

Rejected: exposing OpenAI `messages`, Anthropic content blocks, or Gemini
`contents/parts` on an application trait; normalizing all providers to one
vendor's wire format as the internal contract (final §7.1).

### 2. Providers return content drafts, never identity

`generate_rubric` / `judge` return `RubricDraft` / `JudgmentDraft` — content
only. Identity fingerprints, rubric-version binding, source/response snapshot
hashes, and every Phase 3.11 validator stay in the server-side use case
(`record_llm_judgment`). A vendor layer therefore can never mint identity,
forge comparability, or bypass validation (ADR 0021).

Rejected: adapters returning `SemanticRubric` / `SemanticJudgment` with ids.

### 3. First batch: two heterogeneous protocols; incremental thereafter

Neutrality is proven by two **structurally heterogeneous** protocols passing
the same contract suite: OpenAI Chat Completions-compatible (Bearer auth, flat
`messages`, native `response_format` json-schema; covers local OpenAI-compatible
services) and Anthropic Messages (`x-api-key` + `anthropic-version`, top-level
`system`, content-block array, structured output via `tool_use`). OpenAI
Responses and Gemini native are deferred (Slice 4) and add only an adapter.

`WritingFeedbackProvider` is **not** created: dictogloss/summary feedback is
judged through `SemanticJudgeProvider` over the corresponding `SemanticTaskKind`.
A separate trait waits for Phase 3.15 to reveal its real shape (§3.6 seam
discipline: additive response shapes may be reserved; identity/semantic
generalizations wait for a real consumer).

### 4. Secrets: OS keychain + opaque reference, stricter than any reference

`LlmProviderProfile` carries an opaque `LlmAuthRef`, never a secret. The raw key
is written once through a `SecretStore` (OS keychain in production; in-memory for
tests/headless) and resolved only at dispatch time. It never enters a profile,
SQLite row, log line, or portable bundle. The keychain implementation is
platform-specific and injected by the composition root.

Rejected: environment variables (genai) and plaintext config (aichat) — both
weaker than shared context §3.4 requires.

### 5. Capability is a claim with provenance; local endpoints must be probed

`ProviderCapability` fields are `CapabilityClaim::{Declared, Probed, Unknown}`.
Only `Probed { supported: true }` is usable for a hard requirement. Protocol
compatibility is **not** capability equivalence: OpenAI-compatible and local
endpoints (Ollama, LM Studio) must have structured output *measured* via
`probe_structured_output`, not assumed. The capability taxonomy borrows
LiteLLM's model-catalog fields; the probe discipline is deliberately stricter
than any surveyed project.

Rejected: static declaration only.

### 6. Standardized, secret-free error taxonomy; honest degradation

`LlmProviderError` is a closed taxonomy — offline, auth, rate_limit, timeout,
refusal, truncated, schema_invalid, unsupported_capability, protocol. No variant
carries a credential or reflected response body; `auth` is payload-free so a key
can never be echoed. On any provider error the use case propagates it and
**writes no judgment** — a truncated or refused answer never becomes a stored
verdict (final §7.4).

### 7. Phase 3.12 grants no display qualification

An LLM judgment is stored as an unqualified `heuristic_proxy`. Phase 3.12 adds
**no** observation writer, **no** capability projection writer, and lights up
**no** learning surface. Display eligibility is decided only by Phase 3.12.1
holdout qualification (shared context §3.5); `source_kind=llm_judgment` and
`validation_class` remain orthogonal.

## Consequences

- Adding a provider is adapter-only work; the rubric/judgment domain contract
  and all four-layer separation guarantees are unchanged.
- Switching provider changes no domain JSON and no stored semantics; historical
  judgments keep their original provider/model/prompt provenance.
- Deleting or disabling a key leaves core tasks working and degrades semantic
  feedback honestly; keys never reach plain storage; errors never echo secrets.
- The keychain `SecretStore` implementation, the api-http routes for
  provider-backed rubric/judgment, and the minimal settings UI are follow-on
  slices; this ADR fixes the contract they must honor.
