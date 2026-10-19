# ADR 0028: Pattern Production And Personal Expression Stay Linked But Separate

Status: Accepted — 2026-07-22

Pattern Production completes two different facts: its Constructed Speaking Task is authoritative for the prompt,
recording and corrected transcript, while its Personal Expression Use records that one immutable user-owned pattern
version was used with a particular assistance level and learner self-assessment. We keep both facts and require every
new speaking Personal Expression Use to reference its semantic attempt ID; writing uses cannot carry that reference.
This avoids both collapsing user-owned pattern history into the generic speaking task and maintaining two unrelated
transcript authorities. Historical pre-3.19.1 JSON remains readable with no inferred link.
