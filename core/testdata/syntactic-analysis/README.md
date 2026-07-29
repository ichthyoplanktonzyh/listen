# Syntactic Analysis Slice 0 Fixtures

These fixtures preserve the text and token-alignment risks originally
preregistered for the syntactic-analysis provider work.
The ambiguity and mapping fixtures do not contain provider output or qualify a
parser. The explicitly named Stanza regression fixture contains only the
provider-output cases required by the Rust regression tests.

## Files

- `mapping-contract-v1.json`: executable provider-neutral examples for Unicode
  scalar, half-open spans and explicit 1:N / N:1 / unaligned mappings.
- `ambiguity-dev-v1.jsonl`: adapter-development cases. General offset/protocol
  fixes may be developed against these rows.
- `ambiguity-validation-v1.jsonl`: locked holdout rows. Do not tune adapter
  exceptions or B rules against their labels.
- `locked-fixtures-v1.json`: immutable SHA-256 locks for the v1 and v2
  validation sets, including the historical preregistration provenance.
- `stanza-sense-group-regression-v1.json`: the minimal provider-output subset
  used by the Rust sense-group regression tests, with source report, model, and
  fixture provenance. It is regression evidence, not a current provider
  qualification report.

Both ambiguity files mix short real-caption excerpts with controlled minimal
pairs. Real-caption rows are `manual_product_qa`, not full dependency-tree gold.
The source transcript is local-only and is not committed; only the smallest QA
excerpt and provenance/checksum are retained. Controlled rows are gold only for
their explicit `decision_targets` and dependency expectation, not for an unstated
complete parse.

The fixtures cover future versus motion `going to`, `want to` extraction,
habitual versus state `used to`, obligation versus idiomatic `have to`, function
words, multi-word proper names, contractions, missing punctuation, fragments,
filled pauses, false starts, and numeric tokens.

Run:

```sh
python3 scripts/validate-syntactic-fixtures.py
```

The validators check fixture structure, split isolation, required phenomenon
coverage, mapping span/index invariants, explicit non-exact statuses, and the
locked validation-file digests. Test execution depends only on immutable
artifacts in this directory, not on active or archived planning documents.
