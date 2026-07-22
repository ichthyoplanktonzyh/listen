# Syntactic Analysis Slice 0 Fixtures

These fixtures preregister the text and token-alignment risks for Phase 3.9.1.
They do not contain output from Stanza, spaCy, or any other provider, and they do
not qualify a parser.

## Files

- `mapping-contract-v1.json`: executable provider-neutral examples for Unicode
  scalar, half-open spans and explicit 1:N / N:1 / unaligned mappings.
- `ambiguity-dev-v1.jsonl`: adapter-development cases. General offset/protocol
  fixes may be developed against these rows.
- `ambiguity-validation-v1.jsonl`: locked holdout rows. Do not tune adapter
  exceptions or B rules against their labels.

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

The validator checks fixture structure, split isolation, required phenomenon
coverage, mapping span/index invariants, explicit non-exact statuses, and the
locked validation-file digest from the preregistration.
