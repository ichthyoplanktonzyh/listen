# ADR 0023: Shared Syntactic Analysis Provider and Rebuildable Artifact Boundary

- Date: 2026-07-13
- Status: Accepted for Phase 3.9.1; the `ChunkTimeline` current-fact claims below
  are superseded by R5 (2026-08-09), which retired the legacy `ChunkTimeline`
  family. The syntactic-provider boundary decision itself remains current.
- Context: ADR 0010, ADR 0011, ADR 0016, ADR 0020, and Phase 3.9.1 Slice 0

## Context

Reference B, SenseGroup, and future Construction occurrence matching all need
syntactic context. Letting each consumer infer that context independently would
create three incompatible heuristic stacks. Binding the shared layer to Stanza,
spaCy, UDPipe, or another parser would instead leak one runtime's tokenization,
labels, lifecycle, and licensing assumptions into the product contract.

Subtitle text is especially hostile to positional assumptions: parsers may split
contractions or multi-word tokens, merge abbreviations, normalize punctuation, or
leave fragments partially analyzed. ADR 0011 already demonstrated that an implicit
index mapping can silently attach analysis to the wrong project token.

## Decision

### 1. One provider-neutral, rebuildable analysis artifact

`SyntacticAnalysisProvider` accepts an immutable sentence snapshot and returns a
versioned `SyntacticAnalysis` draft in a project-owned UD-compatible shape. The
artifact records provider, runtime, model, language profile, contract version,
source fingerprint, and validation status. Provider-private Python objects and
labels never cross the adapter boundary.

The artifact is derived data. It is not a user asset, learning evidence, a
capability fact, or canonical Construction identity. A provider may produce
dependency-pattern candidates only; server-side curated/user-owned identity rules
remain authoritative under ADR 0020.

### 2. Token alignment is span-based and explicitly many-to-many

All offsets are half-open Unicode-scalar ranges over the exact
`SubtitleSentence.display_text`: `[start_char, end_char)`. They are not UTF-8 byte
offsets, UTF-16 code units, normalized-text offsets, or positions in a filtered
token list.

Every syntactic word records its source span and the complete set of intersecting
non-whitespace `SubtitleToken.index` values. Every alignable SubtitleToken can
therefore map to zero, one, or many syntactic words. Consumers must use this
relation, never array position or normalized-string equality. Whitespace is
retained in the subtitle snapshot but excluded from the mapping relation and
lexical coverage; punctuation coverage is reported separately. Any unaligned,
normalized-overlap, split, or merged mapping is explicit.

The executable examples in
`testdata/syntactic-analysis/mapping-contract-v1.json` are the Slice 0 mapping
contract. Slice 1 domain types and validators must preserve its semantics.

### 3. UD-compatible fields are a common vocabulary, not parser identity

The neutral syntactic word carries surface, lemma, UPOS, optional XPOS, FEATS,
HEAD, and DEPREL plus the alignment relation. HEAD points within one sentence;
root/tree constraints and sentence ownership are validated after adaptation.
Absence of a parser confidence is represented as absence. Providers must not
invent probabilities.

### 4. Activation requires validation; abstention is first-class

An artifact may be `valid`, `partial`, `invalid`, or unavailable. Low lexical
coverage, invalid spans, invalid heads, multiple roots, cycles, timeout, unsupported
language, missing runtime/model, corrupt model, or protocol failure prevents
syntax-gated consumer activation. Partial artifacts remain inspectable for research
but cannot silently trigger high-risk B rules.

If no validated artifact is available:

- Reference B keeps its current conservative text heuristic;
- SenseGroup keeps `punctuation_length_rule_v1`;
- subtitles, playback, A, and audio-backed C remain available;
- ChunkTimeline is unchanged.

Syntax never fills Reference C, claims observed sound, or replaces ChunkTimeline.

### 5. Cache identity isolates every replaceable input

The logical cache key is the tuple:

```text
contract_version
+ source_fingerprint(display_text + SubtitleToken snapshot + language)
+ provider_id + provider_version
+ runtime_id + runtime_version
+ model_id + model_version + model_checksum
+ profile/config fingerprint
```

Changing any member creates a new artifact identity. Analyses may initially remain
ephemeral or live in a replaceable local cache; persistence is permitted only in a
dedicated analysis store that can be deleted and rebuilt without touching subtitle,
learning, SenseGroup correction, ChunkTimeline, or Construction user-asset rows.
No SQLite migration is authorized by Slice 0.

### 6. Heavy runtimes and models are research-sidecar capabilities

The first adapters use an opt-in JSONL Python sidecar. stdout is protocol-only and
stderr is diagnostic-only. Python, PyTorch, Stanza, spaCy, and model packages are
not bundled into the consumer app by this decision. Missing or failing research
capabilities degrade as described above.

No parser is qualified or selected permanently by this ADR. Qualification follows
the locked development/validation procedure in
`3.9.1-EVALUATION-PREREGISTRATION.md`.

### 7. Runtime, model, treebank, and transitive assets are audited separately

A permissive runtime license does not grant rights to model weights or training
data. Before a model can run outside local research, its exact download URL,
version, checksum, size, model card, training treebanks/data, each applicable
license, redistribution terms, commercial-use terms, and required notices must be
captured. Unknown provenance means research-only and not qualified for distribution.

The initial audit is
`.planning/phases/3.9.1-shared-syntactic-analysis-provider/3.9.1-LICENSE-AUDIT.md`.

## Consequences

- One sentence analysis can serve B, SenseGroup, and dependency-pattern matching
  without any consumer knowing which parser produced it.
- Alignment errors are visible and gate activation instead of silently shifting
  syntactic roles onto neighboring subtitle tokens.
- Parser upgrades are cache misses, not in-place mutation of durable user assets.
- A model-free installation retains current product behavior.
- Slice 1 must implement the neutral DTO/error/validator boundary before Slice 2
  adapters are allowed to define production shapes.

## Rejected Alternatives

- **Expose Stanza or spaCy objects directly.** Rejected because tokenization,
  labels, runtime lifecycle, and versioning would become consumer dependencies.
- **Align by array index or normalized surface text.** Rejected because
  contractions, abbreviations, normalization, and skipped tokens make silent
  misalignment inevitable.
- **Persist syntax on SubtitleToken rows.** Rejected because replaceable parser
  output would mutate source data and make provider/model upgrades ambiguous.
- **Use syntax as C or ChunkTimeline evidence.** Rejected because dependency
  structure is text evidence, not observed timing, phones, energy, or prosody.
- **Let the parser mint Construction keys.** Rejected by ADR 0020's curator/user
  identity boundary.
