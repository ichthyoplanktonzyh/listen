# Listen Roadmap

> Current stage: desktop/mobile local learning and replaceable material
> production, approved 2026-10-22.

[STATE.md](STATE.md) defines the implementation baseline and remaining gaps.
The [devices and production design](docs/architecture/devices-and-production.md)
defines the accepted deployment target, and [JOURNEYS.md](JOURNEYS.md) defines
the learner experience. The broader [MODEL.md](MODEL.md) remains a domain model,
not an instruction to restore deferred activities or source modalities.

The listening scope reduction is merged. Its frozen recovery branches remain
recovery points; new work starts from the reduced `main` baseline. Preserve
existing learner data and published releases under the root development rules.

## 1. Establish shared desktop/mobile local learning

Design and validate changes on desktop and mobile together, starting with
macOS and Android. Separate the Core learning module and persistence rules
from heavy production tools and platform process assumptions. Validate a light
embedded mobile runtime and required platform adapters before committing to a
specific bridge. Keep desktop process assembly where it remains useful.

Prove that the same qualified material can be validated, explicitly adopted,
and consumed in both Workbenches. Also open native media in that same workspace
before preparation, using available source resources without Gen. Exercise
playback, timed text, existing help,
intentional collection, exact source re-entry, and local listening review.
Close the relevant Personal Corpus depth gaps as part of that journey.
Both ends persist learner intent and facts locally, including while offline.
Shared semantics do not require identical layouts or desktop interactions on
a touch screen. Other OS rollout order remains to be selected.

Implement the owner-approved resource policy in
[MODEL.md](MODEL.md#4-resource-policy-and-readiness): foundational interactive
text, exact sentence/word alignment, and declared translations; deeper analysis
on demand. Validate per-action partial readiness separately from complete
foundations and device-local availability. Reuse qualified native resources,
preserve playback on generation failure, and gate Corpus saving on qualified
text/anchors with accurate mapping for original-audio re-entry. Existing
schema acceptance or read/listen/watch availability is not this acceptance gate.

## 2. Complete phone submission and computer production

Pair the devices and run the first automatic journey over local transfer:

```text
phone shares an audio/video link or local file
    -> phone enters the Workbench and plays accessible native media
    -> explicit preparation request reaches the selected computer as a durable task
    -> computer obtains exact input and runs Gen
    -> result is delivered, validated, and explicitly adopted on the phone
    -> phone disconnects and learns, collects, and reviews locally
    -> private learning records return to the computer
    -> computer re-enters the retained Slice and its history
```

Manual export/import can be a development aid, but is not acceptance of this
automatic delivery journey. Persist tasks across page closure and restart;
separate production outcome from each recipient's readiness. Support honest
waiting when the computer is unavailable, cancellation, retry, reconnect,
resumable resource transfer, and duplicate-safe effects. Establish explicit
conflict/correction semantics for private facts and derived review schedules;
do not replicate by overwriting whole database files.

Use deterministic production fixtures for this gate. Exercise the actual
desktop/mobile combination, not just desktop tests or mobile layout previews.
Prepared learning must work with the production computer off and phone offline.

## 3. Validate replaceable model providers

Keep the same computer executor and task/delivery flow while allowing local
models, vendor APIs, or mixed computation. Every route must satisfy the same
material contract and provenance/qualification requirements. Use deterministic
provider adapters to verify those semantics; live/paid calls still require
explicit authorization.

Expose default executor/provider choices and per-task overrides without turning
ordinary learning into pipeline configuration. Explain remote data disclosure,
cost controls, unknown provider outcomes, and failures. Do not silently switch
to paid computation when an executor or provider is unavailable.

## 4. Add remote production and asynchronous remote delivery

Introduce a remote Production Executor under the same task/result semantics.
Add optional relay transport for devices on different networks or online at
different times; keep relay transport independent of production hosting.
Pairing, authenticated access, private data handling, and interrupted-transfer
recovery are required before remote acceptance. Concrete services and wire
protocols remain implementation decisions.

The acceptance journey prepares new material with the personal computer off:
phone submission reaches the remote executor, Gen produces a qualified result,
the phone receives and verifies it, and local offline learning continues.
Notifications are hints; reopening must reconcile task and delivery state even
if no background notification arrived. Do not promise immediate background
downloads across all mobile platforms.

Community publishing, subscriptions, recommendations, and a complete account
system are not prerequisites for this private cross-device journey.

## Queued listening-product follow-up

Restore vocabulary four-dimensional display, filtering, and manual marking.
The domain and storage retain independent reading/listening/speaking/writing
state; currently the vocabulary UI exposes listening only. This is a later
fix, not part of writing the approved plan, and does not restore independent
reading/writing/speaking activities, output assessment, or coach automation.

Continue to select listening-depth work from concrete failures in material
readiness, useful perceptual help, intentional collection, Personal Corpus
re-entry, and audio-first review. Do not add breadth solely because the model
can describe it.
