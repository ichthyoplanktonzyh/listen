# Milestone 2.0 First Development Batch

## Purpose

This locks the first 10 cases used to bring up candidate adapters before the
full evaluation set is populated. It is not the locked final test split and
must not be used to claim release quality.

## Selected Cases

| Case | Genre | Rate | Quality | Target phenomena |
|---|---|---|---|---|
| `m20-001` | news | normal | clean | weak form, word linking |
| `m20-002` | news | fast | clean | flap |
| `m20-004` | news | fast | clean | contraction |
| `m20-011` | interview | normal | clean | weak form |
| `m20-013` | interview | normal | clean | `t/d` deletion |
| `m20-015` | interview | normal | noisy | assimilation |
| `m20-021` | conversation | normal | clean | weak form, word linking |
| `m20-022` | conversation | fast | clean | flap |
| `m20-023` | conversation | normal | noisy | `t/d` deletion |
| `m20-024` | conversation | fast | clean | contraction |

The batch covers every required phenomenon, all three genres, normal and fast
speech, and clean and noisy recordings. During sourcing, ensure at least two
cases are useful negative or uncertain examples rather than ten hand-picked
positive examples.

## Preferred Source Order

1. Newly recorded material with written permission covering research,
   modification/annotation, commercial evaluation, and the intended
   redistribution decision.
2. Existing material under an exact license that clearly permits the required
   research and annotation use.
3. Restricted research corpora such as Buckeye only when their access terms
   are recorded and all restricted audio/annotations remain outside Git.

Do not treat a public URL, free download, or model-training availability as a
license grant.

## Human Work Required

For each case:

1. Select or record a short natural utterance matching the slot.
2. Confirm the exact transcript and media range.
3. Add word ranges.
4. Annotate a broad actual-phone timeline without normalizing observed
   reductions back to dictionary pronunciation.
5. Have a different person independently review the timeline.
6. Record the exact source license/access terms and redistribution decision.
7. Run the manifest validator from
   [`m20-evaluation-inputs.md`](./m20-evaluation-inputs.md).

The first candidate run starts only after all 10 rows pass the validator.
