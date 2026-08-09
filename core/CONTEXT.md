# Listen Ubiquitous Language

This glossary is the canonical cross-repository language for Listen. It defines
product concepts only; it does not describe current endpoints, database tables,
screens, release versions, or implementation status.

## People And Languages

**Learner**:
The person building one private history of language materials, activity, and
learning facts.
_Avoid_: Account, profile, customer

**Content Language**:
The language actually present in a material or one of its segments. One material
may contain more than one Content Language.
_Avoid_: Target Language, Interface Language

**Target Language**:
A language the Learner intends to improve through Listen. A Learner may have
more than one Target Language.
_Avoid_: Content Language, selected locale

**Support Language**:
A language used to translate or explain a Target Language for a Learner.
_Avoid_: Interface Language, source language

**Interface Language**:
The language used by the Listen application itself.
_Avoid_: Target Language, Support Language

**Language Capability**:
A language-aware ability available for a material, such as tokenization, tone,
stress, mora, pronunciation, or morphology analysis.
_Avoid_: Supported language flag, learning activity

## Materials And Resources

**Content Source**:
An external origin that publishes or identifies Language Materials, such as a
podcast feed, video channel, publisher catalog, or learner-owned collection.
_Avoid_: Personal Library, Package Listing

**Source Identity**:
A stable, source-scoped identity for one Language Material. It establishes
provenance but not byte equality or timeline compatibility.
_Avoid_: File hash, Package Release

**Language Material**:
A language-bearing work the Learner may study, such as an article, podcast
episode, video, conversation, or recording.
_Avoid_: Media file, Content Package, course

**Material Revision**:
A stable semantic and timeline version of a Language Material. A changed cut,
dub, inserted segment, or text revision may create another Material Revision.
_Avoid_: Media Rendition, Package Release

**Media Rendition**:
A concrete encoding or realization of a Material Revision. Two renditions may
represent the same revision without having identical bytes.
_Avoid_: Material Revision, Source Identity

**Timeline Compatibility**:
Verified evidence that timed Learning Resources can be applied to a Media
Rendition without changing their meaning or alignment.
_Avoid_: Matching Source Identity, approximate similarity

**Temporary Material**:
A Language Material opened for immediate use without being retained in the
Learner's Personal Library.
_Avoid_: Learning Material, installed content

**Learning Material**:
A Language Material as available inside Listen, composed from source assets and
whatever Learning Resources are currently available. It is valid without any
generated enrichment.
_Avoid_: Content Package, Catalog Entry

**Learning Resource**:
A portable, provenance-bearing resource that makes a Learning Material more
usable for learning.
_Avoid_: Learner state, cache, model response

**Base Resource**:
A Learning Resource that describes the material itself in its Content Language,
such as source text, transcription, segmentation, or timing.
_Avoid_: Translation, learner-specific explanation

**Assistance Resource**:
A Learning Resource that helps a particular audience use the material, such as
a translation, explanation, hint, or level-specific annotation.
_Avoid_: Base Resource, Learning Fact

**Content Enrichment**:
The optional process of deriving new Learning Resources from existing material
and resources.
_Avoid_: Required import step, learning activity

**Resource Provenance**:
The origin, inputs, producer, model, configuration, and transformation history
needed to explain how a Learning Resource was produced.
_Avoid_: Quality guarantee, provider log

## Library And Corpus

**Personal Library**:
The Learner's explicitly retained collection of Learning Materials. Membership
is durable and synchronized; merely opening a Temporary Material does not add it.
_Avoid_: Personal Corpus, playback history

**Personal Corpus**:
A searchable view of language occurrences derived from the Learner's Personal
Library. The view is rebuildable; the library and its resources are authoritative.
_Avoid_: Personal Library, search index files

**Community Corpus**:
The searchable public corpus derived from published Learning Editions and
Package Releases.
_Avoid_: Personal Corpus, external search provider

**Corpus Occurrence**:
One occurrence of a word, phrase, construction, or other language span in a
specific material context, optionally anchored to a media time range.
_Avoid_: Search result row, dictionary entry, decontextualized token

**Search Scope**:
The corpus boundary selected for a query: Current Material, Personal Corpus, or
Community Corpus.
_Avoid_: Separate search feature

**External Context Reference**:
An ephemeral, attributed result supplied by an external context provider. It is
not part of a Listen corpus unless its source material enters through the normal
material intake path.
_Avoid_: Corpus Occurrence, imported Learning Resource

## Activity And Personal State

**Learning Activity**:
A way the Learner chooses to engage with a Learning Material through listening,
reading, speaking, writing, or a future language-learning experience.
_Avoid_: Mandatory lesson step, screen, feature

**Learning Fact**:
A durable factual record of an explicit choice or meaningful learning outcome.
It excludes high-frequency UI telemetry and replaceable model conclusions.
_Avoid_: Raw clickstream, Learning Inference

**Learning Record**:
The Learner-owned history and state that cannot be safely reconstructed from
public packages, including progress, notes, saved items, and Learning Facts.
_Avoid_: Content Package, generated cache

**Learning Inference**:
A replaceable, versioned interpretation derived from Learning Facts, such as a
difficulty or capability estimate.
_Avoid_: Learning Fact, permanent truth

**Training Candidate**:
An optional, ranked suggestion for a next learning action. It does not become a
plan or commitment without the Learner's choice.
_Avoid_: Mandatory assignment, Learning Fact

## Distribution And Community

**Content Package**:
A portable, data-only bundle of material descriptors and Learning Resources. It
contains neither executable providers nor personal Learning Records.
_Avoid_: Database export, model bundle, learner backup

**Delivery Profile**:
How a Content Package supplies its resources: embedded, externally referenced,
or a mixture of both.
_Avoid_: Separate package format

**Learning Edition**:
One producer's pedagogical treatment of a Material Revision for a declared
audience, Target Language, and optional Support Languages.
_Avoid_: Material Revision, Package Release

**Package Release**:
An immutable, content-addressed publication of one Learning Edition.
_Avoid_: Mutable latest package, Package Listing

**Package Listing**:
A mutable community record that groups Package Releases and carries discovery,
ranking, moderation, and update information.
_Avoid_: Content Package, immutable release

**Package Installation**:
The local record that a Package Release was validated and made available as
candidate Learning Resources. Installation does not silently select or activate
new resources.
_Avoid_: Download, Package Release

**Publisher Status**:
The declared or verified identity class of a package publisher, independent of
review quality and redistribution rights.
_Avoid_: Review Status, License Status

**Review Status**:
The declared level and method of content review, independent of publisher
identity and redistribution rights.
_Avoid_: Publisher Status, correctness guarantee

**License Status**:
The available evidence about permission to use or redistribute a resource,
independent of publisher identity and review quality.
_Avoid_: Publisher Status, availability
