# Listen Ubiquitous Language

This glossary is the canonical cross-repository product language. It specializes
the model in [MODEL.md](MODEL.md) without redefining it and does not describe
endpoints, tables, screens, releases, or current implementation status.

A maintained Chinese rendering is available in
[DOMAIN.zh-CN.md](DOMAIN.zh-CN.md). English domain names are the stable
identifiers used by code and contracts; every domain-language change updates
both files in the same documentation change.

## People and languages

**Learner**: The person building a private history of authentic language
experiences, Meaningful Learning Episodes, and learner-language capabilities.
_Avoid_: Account, profile, customer

**Content Language**: A language actually present in a Source or Complete
Learning Material. One material may contain more than one.
_Avoid_: Target Language, Interface Language

**Target Language**: A language the Learner intends to improve. A Learner may
have more than one.
_Avoid_: Content Language, selected locale

**Support Language**: A language used to translate or explain a Target
Language. The required Sentence Translation of a Complete Learning Material is
declared for a Support Language.
_Avoid_: Interface Language, source language

**Interface Language**: The language used by the Listen application itself.
_Avoid_: Target Language, Support Language

**Personal L2 World**: A learner-relative, replaceable interpretation of what
language objects and relations are currently available to the Learner. It is
derived from Personal Corpus evidence and explicit Learner authority; it never
replaces the Corpus history.
_Avoid_: Personal Corpus, account profile, permanent truth

## Language world and material production

**Raw Source**: A learner-authorized input to material production, such as a
file, URL, feed item, article, document, pasted text, podcast, recording, audio,
or video. It may be acquired, inspected, or previewed, but is not yet the
formal first-class object of the learning world.
_Avoid_: Complete Learning Material, Learning Activity

**Content Source**: An external origin that publishes or identifies Raw Sources
or language-bearing works, such as a feed, channel, publisher catalog, website,
or learner-owned collection.
_Avoid_: Raw Source, Personal Corpus, Package Listing

**Source Identity**: A stable, source-scoped identity for one language-bearing
work or revision. It records provenance but does not by itself prove byte,
text, semantic, or timeline compatibility.
_Avoid_: File hash, Material Revision, Package Release

**Source Asset**: A concrete learner-authorized content object used as material
production input: exact bytes or an equivalent bound source, plus digest, size,
availability, and provenance where applicable.
_Avoid_: Learning Resource, Personal Corpus Entry, Managed Asset Store

**Material Revision**: One stable semantic and timeline version of a
language-bearing work. A changed text, cut, dub, insertion, or canonical audio
may require a new revision.
_Avoid_: Raw Source, Rendition, Package Release

**Document Rendition**: An exact document-format realization of a Material
Revision, such as plain text, Markdown, HTML, EPUB, or PDF. It preserves source
representation and may be a production input; it is not Structured Timed Text.
_Avoid_: Canonical Text, Structured Timed Text, Complete Learning Material

**Media Rendition**: An exact playable audio or video realization of a Material
Revision. It may be a Source Rendition or a Derived Rendition.
_Avoid_: Canonical Audio, Material Revision, Language Slice

**Source Rendition**: A Document or Media Rendition realized directly from a
learner-authorized Source Asset without generative transformation.
_Avoid_: Source Asset, Derived Rendition

**Derived Rendition**: A Document or Media Rendition produced from exact input
Renditions or material-side resources, with provenance and compatibility
evidence. Faithful TTS may produce a Derived Media Rendition of the same
Material Revision; a semantic rewrite may not silently do so.
_Avoid_: Source Rendition, automatic replacement

**Learning Material Compiler**: The material-production function, principally
implemented by `listen-gen`, that turns Raw Sources and qualified reusable
inputs into a Complete Learning Material. It owns provider execution and
material-side derivation, not learner state or Learning Experience selection.
_Avoid_: Learning Activity, import form, provider workflow

**Complete Learning Material**: The formal first-class material consumed by the
learning world, qualified for its actual modalities under [MODEL.md](MODEL.md):
text learning needs no TTS, while present audio requires the full
sound-processing scope. “Learning Material” is the accepted short form.
_Avoid_: Raw Source, single file, Content Package, mandatory audio for all text

**Canonical Audio**: The exact audio representation used by the material's
Structured Timed Text and Speech Learning Representation. It may come from a
Source Media Rendition or faithful TTS.
_Avoid_: Any available audio, detached clip, generated pronunciation example

**Canonical Text**: The exact language-bearing text of one Complete Learning
Material, whether or not audio exists. It may come from an authored document,
qualified transcription, or another verified path and pairs with exact
Canonical Audio when present.
_Avoid_: UI transcript, translation, OCR cache

**Source Video**: A video representation retained when the Raw Source includes
video. Video is not synthetically required for Complete Learning Material.
_Avoid_: Canonical Audio, generated completion requirement

**Structured Reading**: The audio-independent, structured representation of
Canonical Text with hierarchy, sentence/token spans, and stable Text Anchors.
It supplies coordinates for reading, translation, Sense Groups, and text-based
Language Slices.
_Avoid_: Document Rendition, transcript UI, mandatory audio alignment

**Structured Timed Text**: The interactive representation that maps stable
Canonical Text spans to exact Canonical Audio ranges with compatible structure
references. It adds coordinates for synchronized highlighting, replay, loops,
and speech learning without being a prerequisite for text-only learning.
_Avoid_: Plain transcript, subtitle UI, Document Rendition, approximate timing

**Text Anchor**: A stable identity for an exact span or structural unit in
Canonical Text. It is valid within a declared text-structure revision,
independently of audio; continuity across revisions requires explicit mapping.
_Avoid_: Screen coordinates, paragraph index, universal cross-version identity

**Audio Locator**: An exact time range in Canonical Audio. It may be paired with
a Text Anchor by Structured Timed Text and referenced by a Language Slice.
_Avoid_: Language Slice identity, estimated timing presented as exact

**Sentence Translation**: A sentence- or utterance-aligned translation of
Canonical Text into a declared Support Language. It belongs to the Complete
Learning Material contract whether or not the composition includes audio.
_Avoid_: Optional contextual explanation, interface localization

**Speech Learning Representation**: The conceptual learning-oriented speech
representation spanning material-side Signal Facts and Speech Structure plus
learner-relative Perceptual Guidance. It is realized by multiple versioned,
provenance-bearing resources rather than one universal artifact.
_Avoid_: IPA transcript, RhythmFrame, ChunkTimeline, phonetics annotation view

**Signal Fact**: A material-side, evidence-bearing fact about Canonical Audio,
such as word/phone timing, phone realization, duration, energy, pitch/F0,
voicing, or speech/silence intervals. Observed, forced-aligned, predicted, canonical, and
estimated facts remain distinguishable.
_Avoid_: Perceptual Guidance, text prior presented as audio evidence

**Speech Structure**: A replaceable interpretation of signal and text evidence
into prominence, information/stress anchors, nuclei, weak groups, rhythm,
compression, prosodic boundaries, Prosodic Chunks, or connected-speech phenomena.
_Avoid_: Signal Fact, Learner State, fixed universal annotation

**Citation Pronunciation**: A conventional reference pronunciation of the
language content, independent of how a particular recording realizes it.
_Avoid_: Observed phones, Actual Delivery

**Connected-speech Prediction**: An evidence-labeled prediction of how language
may be realized in continuous speech. It can be derived from text without
claiming that the phenomenon occurred in a recording.
_Avoid_: Actual Delivery, confirmed audio event

**Actual Delivery**: An evidence-qualified interpretation of how language is
realized in one exact recording. It remains distinct from reference
pronunciation and text-derived prediction.
_Avoid_: Citation Pronunciation, prediction presented as observation

**Prosodic Chunk**: A bounded organization in the speech signal, anchored to
exact words and projected to audio through compatible timing.
_Avoid_: Sense Group, lexical phrase, ChunkTimeline

**Sense Group**: A semantic/syntactic, meaning-oriented grouping of text that
supports reading and bounded learning focus without audio or TTS. It may
overlap with a Prosodic Chunk but neither proves an audible boundary nor
inherits the chunk's identity.
_Avoid_: Prosodic Chunk, reusable lexical phrase

**Connected-speech Phenomenon**: A material-side interpretation of how speech
realization differs or connects in context, such as reduction, linking,
assimilation, deletion, flapping, or compression, with evidence and provenance.
_Avoid_: Unqualified rule label, Learner difficulty

**Perceptual Guidance**: Learner-relative guidance derived from material-side
speech representation and learner evidence: what to attend to, which cue or
anchor to reveal, and when to replay. It is part of Learning Experience, not
fixed material truth.
_Avoid_: Signal Fact, Gen-authored universal answer, phonetic terminology

**Optional Enrichment**: Grammar, semantic, pragmatic, discourse, cultural, or
contextual assistance that improves a Complete Learning Material but is not a
required part of its contract.
_Avoid_: Sentence Translation, required sound processing, audio-independent Sense Group

**Resource Provenance**: The exact inputs, producer, provider/model, version,
configuration, transformation, evidence class, and qualification history needed
to interpret a material-side resource honestly.
_Avoid_: Quality guarantee, provider log

## Learning world

**Learning Boundary**: The boundary after which the learning system consumes a
Complete Learning Material and reasons about Learner-relative experience rather
than provider production steps.
_Avoid_: File import, package installation, screen navigation

**Workbench**: The unified learner-facing workspace that consumes material and
learning semantics supplied by Core and hosts material interaction and Learning
Activities. Its views and activity modes may vary with the material and intent
without becoming separate material-consumption systems.
_Avoid_: Learning Activity, media-only player, provider-output viewer, one fixed layout

**Language Object**: A family of reusable language targets such as a Lexical
Unit, expression, construction, sound contrast, or other object for which
learner-language capability may be assessed. The family has no mandatory
universal database identity.
_Avoid_: Token, Language Slice, universal parent table

**Learning Activity**: A meaningful cognitive operation through which a Learner
interacts with a Complete Learning Material, such as listening for meaning,
intensive listening, reading, dictation, shadowing, reconstruction, speaking,
or writing.
_Avoid_: Screen, button, feature, mandatory course stage

**Language Slice**: A stable, re-enterable pointer to a bounded experience in a
Complete Learning Material: Material Revision, Canonical Text span, Canonical
Audio rendition/range when available, and compatible resource references. A
text-only Slice is valid; it normally does not copy audio or become a new
material.
_Avoid_: Audio clip file, detached flashcard, Corpus Occurrence

**Learning Focus**: The Language Slice or Language Object currently receiving
intentional attention inside a Learning Activity.
_Avoid_: Playback cursor, automatic hover, permanent collection

**Learner Relation**: The durable fact that a Learner has intentionally saved,
focused, practiced, judged, produced, or reactivated a Language Slice or
Language Object.
_Avoid_: Raw click, model inference, package membership

**Meaningful Learning Episode**: A bounded, learner-significant history of what
happened with a Slice or target, including activity intent, conditions,
assistance, attempt or judgment, outcome, source context, and provenance.
_Avoid_: Page view, raw clickstream, capability projection

**Exposure**: The fact that language was presented or played. It does not prove
attention, learning, or acquisition.
_Avoid_: Meaningful Learning Episode, acquired capability

**Attention**: Evidence that the Learner intentionally focused on a Slice,
target, or cue. It does not by itself prove learning or acquisition.
_Avoid_: Exposure, acquired capability

**Learning Observation**: An append-only fact about a learner action, attempt,
condition, assistance level, and outcome. It may support a Meaningful Learning
Episode but is not automatically qualified Evidence.
_Avoid_: Telemetry aggregate, Learner Inference

**Learning Fact**: A durable fact the Learner cannot safely recreate, including
Meaningful Learning Episodes, explicit decisions, attempts, corrections, and
qualified outcomes. High-frequency telemetry and replaceable conclusions are
not Learning Facts.
_Avoid_: Clickstream, Learner Inference, generated cache

**Evidence**: A stated, versioned qualification of Learning Facts or
Observations for one conclusion. Retention alone does not make a fact evidence
for every capability.
_Avoid_: Observation, permanent truth

**Assistance**: A factual condition of an attempt or episode, such as audio
replay, focus range, perceptual cue, speech explanation, timed text,
translation, source visibility, imitation, or another support.
_Avoid_: Capability score, universal total order

**Scaffold**: Assistance intentionally exposed to make the current cognitive
operation possible. Listen prefers the Minimum Sufficient Scaffold and records
what was available or used.
_Avoid_: Answer reveal by default, acquired capability

**Acquisition Experience**: The learner-relative experience selected to change
or test a learner-language capability. It may reactivate, repair perception,
support retrieval, elicit production, or test transfer.
_Avoid_: Scheduler, Content Package, generic exercise row

**Perceptual Repair**: A listening acquisition sequence in which failed
perception leads to attention guidance and another act of listening, with only
the minimum useful support exposed.
_Avoid_: Phonetic explanation consumption, answer memorization

**Transfer Experience**: An experience that tests or develops capability under
a changed sentence, speaker, rate, prosody, acoustic realization, modality, or
context rather than only repeating the same item.
_Avoid_: Same-recording replay, final mastery proof

## Personal Corpus and learner state

**Personal Library**: The Learner's intentionally retained collection of Raw
Sources and Complete Learning Materials. It supports ownership and availability
but is not the Personal Corpus.
_Avoid_: Personal Corpus, file-system folder, playback history

**Personal Corpus Entry**: One Language Slice plus its Learner Relation and
Meaningful Learning History, including source context, assistance, and
outcomes. It can originate in text-only learning or an explicit save without
requiring a completed exercise.
_Avoid_: Search-result row, bookmark, copied audio clip

**Personal Corpus**: The durable, learner-owned history of authentic Language
Slices with their relations and Meaningful Learning Episodes. It serves as
memory, Evidence Base, and a browsable Experience Reservoir from which the
Learner can choose further learning or review; indexes are rebuildable projections.
_Avoid_: Personal Library, vocabulary deck, search index, Personal L2 World

**Corpus Occurrence**: A rebuildable material-side occurrence of a Language
Object or span in context. It can help discover Slices but does not become a
Personal Corpus Entry until a Learner Relation and meaningful history exist.
_Avoid_: Personal Corpus Entry, dictionary entry

**Experience Reservoir**: The Personal Corpus viewed as reusable authentic
material for review, repair, retrieval, production, and transfer.
_Avoid_: Generated question bank, mandatory queue

**Learner State**: A simple, durable or explicitly authoritative state about a
Learner–Language Object relation. Detailed subskill interpretation remains a
replaceable Learner Inference unless the product deliberately promotes it.
_Avoid_: Personal Corpus history, giant capability tensor

**Capability Dimension**: One independent reading, listening, speaking, or
writing relation for a Language Object. No dimension is inferred from another
without its own qualified evidence or explicit Learner authority.
_Avoid_: Material Capability, one linear vocabulary level

**Lexical Capability Profile**: The Learner-owned or evidence-projected state of
one Lexical Unit across the four Capability Dimensions. Unassessed means no
current conclusion and never means not acquired.
_Avoid_: Package Resource, one vocabulary status

**Learner Inference**: A replaceable, versioned interpretation derived from
Personal Corpus Evidence, such as difficulty, capability, robustness, or a
suggested next experience.
_Avoid_: Learning Fact, explicit Learner decision, permanent truth

**Training Candidate**: An optional, explainable suggestion for a next
Acquisition Experience. It does not become a plan without Learner choice or an
explicitly accepted policy.
_Avoid_: Mandatory assignment, Learning Fact

**Review Schedule**: The time policy that decides when a learner-language
relation should be reactivated. It does not decide what Acquisition Experience
occurs when the item returns.
_Avoid_: Learning Experience, review activity definition

## Distribution and community

**Learning Edition**: A producer's coherent, qualified composition of the
Renditions and material-side resources that satisfy a Complete Learning
Material contract for a Material Revision, declared audience, Target Language,
and Support Language.
_Avoid_: Material Revision, learner state, activity sequence

**Content Package**: A portable, data-only distribution bundle for a Learning
Edition. It contains no executable provider and no personal Learning Facts.
_Avoid_: Course, learner backup, model bundle

**Package Release**: An immutable, content-addressed publication of one
Learning Edition.
_Avoid_: Mutable latest package, Package Listing

**Package Listing**: A mutable community record grouping Package Releases and
carrying discovery, ranking, moderation, and update information.
_Avoid_: Content Package, immutable release

**Package Installation**: The local fact that a Package Release was validated
and made available. It does not itself create a Personal Corpus Entry or choose
a Learning Activity.
_Avoid_: Learning Edition Adoption, acquisition experience

**Learning Edition Adoption**: The Learner's explicit decision to use one
installed, qualified Complete Learning Material composition.
_Avoid_: Package Installation, learner capability

**Community Corpus**: A searchable projection over public, rights-compatible
Complete Learning Materials and their occurrences. It contains no private
Learner Relations or Meaningful Learning Episodes.
_Avoid_: Personal Corpus, external search provider

**External Context Reference**: An attributed, ephemeral result from an
external provider. It does not enter a Listen corpus unless its source is
compiled and retained through the ordinary material and learning boundaries.
_Avoid_: Corpus Occurrence, Personal Corpus Entry
