# Phase 1 Product Validation and Information Architecture Review

> Status: historical as of 2026-08-24. Its learner-research evidence may be
> reused, but its partial-material journey assumptions are superseded by
> [MODEL.md](../MODEL.md).
>
> Former scope: evaluate the current unreleased App from the learner's side of the
> screen, then use observed problems to decide the minimum Information
> Architecture changes needed before Phase 1 can be accepted.
>
> This is not a code-review checklist, a release declaration, or evidence that
> Phase 1 has passed.

## 1. Purpose

The current App, Core, and Gen branches form an integration candidate. The next
question is not whether every implementation diff can be defended in isolation.
It is whether a learner can understand and complete the material-centered loop:

```text
bring or discover a material
  -> use an available rendition immediately
  -> keep it intentionally
  -> add a missing capability when useful
  -> learn through the resulting material
  -> leave, restart, and continue later
```

Validation proceeds outside-in:

```text
learner intent and observed App behavior
  -> screen, navigation, copy, and interaction state
  -> App state and coordination
  -> Core authority and persisted domain state
  -> Gen planning and production
```

Do not inspect the next layer merely to make the review comprehensive. Trace
inward only when an observed learner problem needs an explanation. This keeps
the work focused on real product defects instead of theoretical hardening.

## 2. Relationship between product validation and IA work

The work has four ordered stages:

1. **Current-product observation** — run the integration candidate and perform
   the learner tasks in this document without changing product behavior.
2. **IA synthesis** — the Supervisor groups evidence, resolves domain-language
   conflicts, and publishes one target IA with explicit non-goals.
3. **Vertical implementation** — a coding agent implements approved IA slices,
   including any App/Core seam correction proven necessary by the journey.
4. **Same-task verification** — repeat the original tasks against the changed
   App. A new layout is not accepted merely because its widget tests pass.

Do not combine stages 1 and 3. Editing the interface while observing it destroys
the baseline, encourages local patching, and makes it impossible to tell whether
the resulting IA solves the original problem.

## 3. Roles during the validation session

### Owner

- Operates the App as the learner and states what they expect before acting.
- May use existing product knowledge, but should not inspect code or follow a
  button-by-button script during a task.
- Decides genuine product trade-offs after evidence has exposed them.

### Coding agent

- Prepares and launches the exact integration candidate.
- Presents one task intent at a time without naming the expected control.
- Records actions, hesitation, wrong turns, visible states, screenshots or a
  short screen recording, terminal output, and process state.
- May inspect App, Core, or Gen after the observed task to identify the likely
  owning seam. It must distinguish observation from diagnosis.
- Does not change product code, tests, schemas, locks, or documentation during
  this baseline session. Environment-only setup must stay disposable.

### Supervisor

- Reviews the structured evidence rather than replaying a broad diff audit.
- Separates interaction defects, IA defects, App state defects, domain-model
  conflicts, authority leaks, and producer failures.
- Produces the target IA and precise implementation slices after observation.
- Independently repeats the decisive journeys before release acceptance.

## 4. Candidate build and evidence rules

- Record the branch and exact commit for App, Core, Gen, and project docs before
  launch. Record the committed App lock identities separately from the local
  unreleased snapshots used for validation.
- The committed production locks currently refer to the last real published
  stack and are not evidence that the unreleased candidate is runnable. Use a
  disposable validation assembly for current Core/Gen snapshots. Do not commit
  temporary paths, hashes, manifests, or lock changes, and do not weaken
  version or artifact verification.
- Follow `listen-app/docs/development/full-app-local-testing.md` for sidecar
  lifecycle and diagnostics, but current code and executable checks override
  stale examples in that runbook.
- Use an isolated temporary App-data/database location for the cold-start pass.
  Do not delete or mutate the owner's normal App data.
- Desktop materials are read-only inputs. Never move, rewrite, or commit them.
  Record their display name, format, relevant media facts, and digest when
  needed; do not place absolute machine paths in production data or commits.
- Do not use a paid provider, live credential, or network-dependent model.
  A real local `say`/TTS or whisper.cpp journey is allowed when already
  available on the machine. Mark every provider as `real local`, `fixture`, or
  `unavailable`.
- Keep screenshots and recordings outside the repositories unless the owner
  later selects a small sanitized asset for documentation or a test fixture.
- A task may be `pass`, `friction`, `fail`, `blocked by environment`, or `not
  run`. Fixture success never substitutes for a requested real-App result.
- Do not claim Phase 1 completion from this session. Its output is a product and
  IA diagnosis plus a bounded implementation plan.

## 5. Observation protocol

For each task:

1. The coding agent gives only the learner intent from the **Prompt** column.
2. Before clicking, the owner says where they expect to begin and what outcome
   they expect.
3. The owner performs the task without code-level hints.
4. The coding agent records the path taken, wrong turns, hesitation longer than
   roughly three seconds, labels interpreted incorrectly, state transitions,
   and final result.
5. Capture the decisive before/after screen and relevant logs. Do not turn the
   session into continuous screenshot collection.
6. Only after the task ends may the coding agent trace the owning App state,
   Core response, persisted data, or Gen event stream.
7. Reset only the state explicitly named by the next task. Otherwise preserve
   continuity so later tasks test the same Material.

The coding agent must not explain the current IA before the orientation task.
The point is to observe the learner's mental model, not their ability to follow
the implementation's vocabulary.

## 6. Validation journeys

Start with one representative document and one representative audio or video
file. Run the broader format matrix only after the central journey is usable;
otherwise record the first blocking product problem and avoid multiplying the
same evidence across formats.

### Journey A — Orientation and first material

| ID | Prompt | Required observation | Semantic success condition |
|---|---|---|---|
| A1 | “You have just opened Listen. Tell me what you think each main area is for.” | Meaning predicted from navigation labels; destination/action/utility confusion; technical concepts visible on the ordinary home surface. | The learner can identify where to bring material, where retained materials live, and where learning activity lives without being taught the IA. |
| A2 | “Add this document and begin reading it.” | First destination chosen; import control chosen; file picker, loading, error, and direct-view transitions; whether Gen/package concepts appear. | A supported Document Rendition opens immediately without generation or a Content Package. |
| A3 | “Leave this material somewhere you can find tomorrow.” | Whether the learner looks for save, keep, library, download, or another concept; comprehension of Keep versus Reference in Place. | Retention is intentional, the storage choice is understandable, and the learner can locate the retained Material afterward. |

Use a real plain-text or text-layer PDF/EPUB document first. After the core path
works, sample Markdown, HTML, EPUB, PDF, and plain text. Include a scanned PDF
only to verify honest direct-view/OCR-unavailable behavior; real OCR is not a
Phase 1 requirement.

### Journey B — One Material across capabilities

| ID | Prompt | Required observation | Semantic success condition |
|---|---|---|---|
| B1 | “Make this document something you can listen to.” | Where the learner searches; meaning of Read/Listen/Watch; derivable/generating/failed states; progress, cancel, retry, and navigation during production. | The request stays attached to the same Material; TTS creates a Derived Media Rendition and does not replace the document. |
| B2 | “Use the new audio and text together.” | Whether the generated result opens naturally; whether the learner encounters a separate unexplained ‘composition’ product; synchronization and missing-alignment presentation. | Adopted audio, Structured Reading, and exact alignment are experienced as capabilities of the same Material. |
| B3 | “Now bring this audio or video into Listen, then make it readable.” | Immediate playback; retention; location of the Read request; ASR progress/failure; no-audio video behavior. | Source media remains playable while Structured Reading is derived, unavailable, cancelled, or failed. |
| B4 | “Switch among reading, listening, and watching this material.” | Whether modes look like navigation destinations, filters, or Material-local capabilities; whether the same item is duplicated in the library. | One Material remains one ownership object and appears in applicable capability views without duplication. |

For one TTS and one ASR path, use real local providers if available. If the
candidate App cannot launch the current Gen snapshot without altering committed
production locks, record that as an integration-assembly blocker; do not bypass
verification or relabel a fixture as a real journey.

### Journey C — Leave, restart, and recover

| ID | Prompt | Required observation | Semantic success condition |
|---|---|---|---|
| C1 | “Close Listen, reopen it, and continue this material.” | Relaunch destination; recent/continue behavior; adopted composition; reading/playback position; activity state. | The retained Material and adopted composition survive restart and are easy to resume. |
| C2 | “The file referenced in place has moved. Find out what happened and recover if possible.” | Error placement and wording; whether membership disappears; available recovery action. | The Material and learner state remain; the missing Source Asset is reported as unavailable rather than silently deleted. |
| C3 | “Cancel a generation, then try again.” | Cancel discoverability; terminal state; stale progress; retry meaning; orphan processes. | Cancellation ends the exact attempt and child processes; retry is a new attempt and the source capability remains usable. |

### Journey D — Discover a material

| ID | Prompt | Required observation | Semantic success condition |
|---|---|---|---|
| D1 | “Subscribe to this source and tell me what that action did.” | Where source management lives; difference between subscription, download, retention, and adoption. | Subscription produces Discovery Items and does not silently retain every item. |
| D2 | “Choose this article and start learning from it.” | Article versus enclosure presentation; acquisition progress; resulting document session; return path. | An article becomes a Document Rendition through the same Material lifecycle as a local document. |
| D3 | “Choose this podcast or video and start learning from it.” | Media acquisition/playback; permissions/unavailable states; resulting Material identity. | An authorized enclosure becomes a Media Rendition through the same lifecycle as local media. |
| D4 | “Refresh the source and find the same item again.” | Duplication, source identity, changed metadata, mixed-feed behavior. | Stable source-scoped identity resolves the same Material; mixed feeds do not inherit one modality from the first entry. |

Use small deterministic RSS and Atom fixtures for repeatability. A real network
feed may be an additional observation, never the only acceptance evidence.

### Journey E — Learn from the retained Material

| ID | Prompt | Required observation | Semantic success condition |
|---|---|---|---|
| E1 | “From this material, enter an existing intensive or extensive learning activity.” | Location and naming of activities; context lost between Material and activity; whether raw media/subtitle state replaces adopted composition. | The activity consumes the active adopted Material composition and keeps its own learner state. |
| E2 | “Save a word or expression, then find it later.” | Difference among Material, My Language, review, and activity navigation; return-to-context behavior. | Learner-owned language facts outlive package/source changes and remain connected to understandable material context. |
| E3 | “Decide what to do next without being assigned a course.” | Meaning and usefulness of Today and Coach; whether suggestions feel optional; dead-end status tiles. | The App supports self-direction and presents optional doors rather than mandatory progression. |

### Journey F — Honest degradation

Exercise one example of each relevant state without repeating every format:

- corrupt or falsely labelled document;
- password-protected or unsupported document;
- scanned PDF without OCR;
- media without an audio track;
- missing referenced Source Asset;
- provider failure and malformed producer output;
- failed installation and failed adoption;
- offline or unavailable acquisition;
- stale completion after a newer request;
- normal App close followed by an orphan-process check.

The key question is whether usable source reading or playback remains usable and
whether the App tells the learner what happened and what they can do next.

## 7. Current IA inventory

The current branch presents this structure in source:

```text
App shell
├── Today
├── Listen
│   ├── My media
│   └── Discover
├── My language
│   ├── Vocabulary
│   ├── Expressions
│   └── Review
├── Coach
├── Start conversation          (launch action, not a destination)
├── Tools                       (utility)
└── Settings                    (utility)

Material-facing surfaces launched outside the shell pane
├── Document Session            (source document direct view)
├── Media Workbench             (playback and learning channels)
└── Composition Session         (adopted Structured Reading / derived audio)
```

This inventory is a baseline, not an endorsed target IA.

## 8. IA hypotheses to validate

### H1 — Modality-shaped navigation conflicts with the Material model

`Listen` currently contains documents, media, the Personal Library, and
discovery. `My media` also contains retained documents. These labels describe
one modality while the product owns modality-neutral Materials. Validate which
destination name the learner expects: Library, Materials, or another plain
learner term. The domain conflict is real; observation decides the clearest
replacement and placement.

### H2 — One Material may look like three unrelated products

Document Session, Media Workbench, and Composition Session use different
shells. Validate whether a learner understands that generated audio, Structured
Reading, source PDF/EPUB, and source media are capabilities of the same
Material. If they lose object continuity, the target IA should introduce one
Material Workspace with rendition-specific modes rather than merely adding
cross-links among three sessions.

### H3 — Today mixes learner doors with implementation health

Today currently combines continue, review, saved-word count, listening inbox,
and local Core status. Validate whether it answers one useful learner question
or reads as a status dashboard. Runtime health belongs in diagnostics unless a
failure requires a learner-facing recovery action.

### H4 — Discover and Library may be hidden under an unclear parent

Discovery and retained materials are distinct lifecycle states. Validate
whether nesting both under `Listen` helps the learner understand their
relationship or merely adds a segment switch before frequent tasks. Also
observe where the learner expects subscription/source management to live.

### H5 — My language may mix collections, activities, and navigation levels

Vocabulary and Expressions are learner-owned collections; Review is an
activity over learner state. Validate whether their shared destination is
understandable, whether the label predicts its contents, and whether returning
to the originating Material remains possible.

### H6 — Coach and Conversation may be premature global destinations

Phase 1 is material-centered and self-directed. Validate whether Coach and
Start conversation are understood as optional learning experiences or compete
with the core material journey. They are not removed merely for being outside
the core loop, but they should not determine the IA before their user role is
clear.

### H7 — Entry actions mix source, location, and format

The library currently offers Open document, Open video/audio, and Open URL
under an add-content/source heading. Validate whether the learner thinks first
in terms of location (`On this Mac`, `From a link`, `From subscriptions`) or
format (`Document`, `Audio`, `Video`). The final intake interface should not
require the learner to understand Source Asset or Rendition terminology.

### H8 — Capability actions may be placed too far from the Material

Validate where the learner looks for Read, Listen, Watch, synchronized use,
Keep, and learning activities: library row, session header, workbench menu, or
another place. Capability state should be visible where the learner is already
using the Material, not only in a management surface.

## 9. IA evaluation criteria

Evaluate the observed structure against these rules:

- **Predictability** — a destination label lets the learner predict its
  contents before opening it.
- **Object continuity** — the learner recognizes one Material across discovery,
  intake, library, capability production, session, activity, and restart.
- **Location and return** — the learner knows where they are, what opened the
  current surface, and how to return without losing state.
- **One navigation grammar** — destinations, launch actions, Material-local
  modes, filters, and utilities are visibly different kinds of controls.
- **User vocabulary** — labels name objects and actions the learner controls;
  packages, blobs, contracts, compositions, Core, Gen, and providers remain
  implementation detail unless intentionally disclosed in diagnostics.
- **Action hierarchy** — immediate use is primary; Keep, add capability, and
  learning activities are discoverable but do not compete as equal unexplained
  buttons.
- **Honest state** — available, derivable, generating, unavailable, and failed
  attempts are distinguishable without presenting a valid Material as broken.
- **Modality neutrality** — adding a document, audio, video, or future rendition
  does not require a new ownership destination.
- **Self-direction** — suggestions and review are available without turning the
  App into a mandatory curriculum.
- **Extensibility through locality** — a new capability should appear on the
  Material surface, not require another global navigation branch.

## 10. Working target IA hypothesis

Use this only as a comparison during observation. It is not implementation
authorization:

```text
Home
├── Continue current material
├── Recent or needs-attention material
└── Optional review / learning doors

Library
├── All Materials
├── Read / Listen / Watch views
└── Add Material

Discover
├── Discovery Items
└── Sources / Subscriptions

Learning
├── Vocabulary
├── Expressions
├── Review
└── Optional conversation / coach experiences

Material Workspace              (opened from Home, Library, or Discover)
├── Read / Listen / Watch modes when available
├── Add a missing capability
├── Keep / availability
└── Material-context learning activities

Settings and diagnostics        (utilities, not learner destinations)
```

The likely architectural center is the Material Workspace: one learner-facing
place whose available modes are projected from the source Renditions and
adopted composition. The exact top-level destination count and labels remain
open until the baseline evidence is reviewed.

## 11. Finding classification and severity

Classify every finding by both type and impact.

Types:

- `interaction` — control behavior, feedback, focus, or visual hierarchy;
- `IA` — destination, grouping, naming, location, return path, or object
  continuity;
- `App state` — state machine, lifecycle, concurrency, or view projection;
- `domain mismatch` — the interface cannot honestly express the accepted
  Material/Rendition/Resource model;
- `authority leak` — App or Gen decides or persists a fact owned by Core;
- `production` — Gen planning, provider execution, qualification, or events;
- `environment` — candidate assembly, local tool, test data, or host setup.

Severity:

- **P0** — blocks the central journey, risks data loss/security, or makes the
  App unusable after a normal action.
- **P1** — the journey is technically possible but the learner is materially
  misled, cannot discover a primary action, or experiences one Material as
  disconnected objects.
- **P2** — recurring friction, weak wording, unclear hierarchy, or an honest
  but awkward degraded state.
- **P3** — visual polish or preference without meaningful task impact.

Do not escalate a code-structure concern to an IA issue without learner-facing
evidence. Escalate to an architecture slice when the same problem crosses
multiple surfaces, duplicates authority/state, or cannot be fixed locally
without making the interface less honest.

## 12. Required handoff from the validation session

Return one report containing:

1. exact App/Core/Gen/docs commits, committed locks, disposable candidate
   assembly method, App-data isolation method, and final Git status;
2. host/tool availability and which providers were real local, fixture,
   unavailable, or not run;
3. one result row per task: `pass`, `friction`, `fail`, `blocked by
   environment`, or `not run`;
4. for every friction/failure: task ID, starting state, expected location or
   outcome stated before acting, actual path, wrong turns, final visible state,
   and decisive screenshot/recording timestamp;
5. exact learner-facing labels that were misunderstood, including interface
   language;
6. a sketch of where the owner expected each destination, action, mode, filter,
   and utility to live;
7. diagnosis kept separate from observation, with the smallest likely owning
   App module and only the necessary Core/Gen seam evidence;
8. restart persistence results and an orphan-process check;
9. raw terminal/log excerpts only for failures, with secrets and unrelated
   local paths removed; and
10. confirmation that no product implementation, schema, committed lock,
    release, PR, push, paid provider, credential, or desktop input was changed.

Use this issue template:

```text
ID: IA- or UX-###
Task: B2
Type: IA | interaction | App state | domain mismatch | authority leak |
      production | environment
Severity: P0 | P1 | P2 | P3
Observation: what the learner did and saw
Expectation stated before acting: ...
Outcome: ...
Evidence: screenshot/recording timestamp/log
Diagnosis (after observation): ...
Likely owning seam: App screen/controller | App-Core | App-Gen | Core | Gen
Do not fix yet: yes
```

## 13. Supervisor decision after handoff

The Supervisor will convert the evidence into no more than these implementation
layers:

1. **IA vocabulary and shell** — top-level destinations, labels, navigation
   grammar, return paths, and removal of technical status from ordinary IA.
2. **Material Workspace continuity** — unify or consistently compose document,
   media, and adopted-composition experiences only if the baseline proves that
   one Material currently fractures into separate products.
3. **Material-local capability and activity actions** — place Read, Listen,
   Watch, Keep, add-capability, and activity entry where observed expectations
   support them; preserve honest state and Core authority.
4. **Focused vertical defects** — fix only journey-blocking App/Core/Gen issues
   discovered during validation.
5. **Same-task regression** — repeat Sections 6 and 9 before any Phase 1 release
   decision.

Coach, conversation, broad visual redesign, new learning activities, provider
breadth, corpus search, community services, and generalized compatibility work
do not enter an IA implementation slice unless the observed Phase 1 journey is
blocked by their current placement or behavior.
