# Listen Ubiquitous Language

This glossary is the canonical cross-repository product language. It does not
describe endpoints, tables, screens, release versions, or implementation status.
Repository-local glossaries may add terms but must not redefine these concepts.
A maintained Chinese rendering is available in
[DOMAIN.zh-CN.md](DOMAIN.zh-CN.md); both files describe the same model and must
change together.

## People and languages

**Learner**: The person building one private history of language materials,
activity, and learning facts.
_Avoid_: Account, profile, customer

**Content Language**: The language actually present in a material or segment.
One material may contain more than one.
_Avoid_: Target Language, Interface Language

**Target Language**: A language the Learner intends to improve. A Learner may
have more than one.
_Avoid_: Content Language, selected locale

**Support Language**: A language used to translate or explain a Target
Language.
_Avoid_: Interface Language, source language

**Interface Language**: The language used by the Listen application itself.
_Avoid_: Target Language, Support Language

**Language Capability**: A language-aware ability available for a material,
such as tokenization, tone, stress, mora, pronunciation, or morphology
analysis.
_Avoid_: Supported-language flag, Learning Activity

## Materials and resources

**Content Source**: An external origin that publishes or identifies Language
Materials, such as a feed, channel, publisher catalog, or learner-owned
collection.
_Avoid_: Personal Library, Package Listing

**Source Identity**: A stable, source-scoped identity for one Language Material.
It establishes provenance but not byte equality or timeline compatibility.
_Avoid_: File hash, Package Release

**Language Material**: A language-bearing work the Learner may study, such as an
article, podcast episode, video, conversation, or recording.
Its Source Renditions and Structured Reading Resources do not become separate
Materials.
_Avoid_: Media file, Content Package, course, Raw Material, Structured Material

**Material Revision**: A stable semantic and timeline version of a Language
Material. A changed cut, dub, inserted segment, or text revision may create
another revision.
_Avoid_: Media Rendition, Package Release

**Source Asset**: A concrete, Learner-authorized content object acquired or
bound for a Material Revision. It may be copied into a Managed Asset Store or
referenced in place; storage location and current availability are not its
semantic identity.
_Avoid_: Learning Resource, Managed Asset Store, Content Source

**Document Rendition**: A concrete document-format realization of a Material
Revision, such as plain text, Markdown, HTML, EPUB, or PDF. It preserves the
source representation and may be directly viewable without a Structured
Reading Resource. Authored markup or layout does not make it a Structured
Reading Resource; multiple Document Renditions may realize the same revision.
_Avoid_: Structured Reading Resource, Structured Material, pasted-text form,
Material Revision

**Media Rendition**: A concrete playable audio or video realization of a
Material Revision. Two renditions may represent the same revision without
identical bytes.
_Avoid_: Material Revision, Source Identity

**Source Rendition**: A Document or Media Rendition realized directly by a
Learner-authorized Source Asset without generative transformation.
_Avoid_: Source Asset, Derived Rendition, publisher guarantee

**Derived Rendition**: A Document or Media Rendition produced from exact input
Renditions or Learning Resources rather than acquired directly as a Source
Asset. It realizes the same Material Revision only when its meaning and any
required alignment remain compatible.
_Avoid_: Source Rendition, Learning Resource, automatic replacement

**Material Capability**: A learner-facing ability that a compatible composition
of Renditions and Learning Resources can offer, such as Read, Listen, Watch, or
synchronized Read-and-Listen. Its current availability is a projection, not
Material identity or a universal measure of quality.
_Avoid_: Learning Activity, Material Shape, completion score

**Capability Gap**: A Material Capability requested by the Learner but not
currently available. It may be derivable and does not make the Material invalid
or incomplete by itself.
_Avoid_: Broken Material, missing source asset, mandatory generation

**Capability Completion**: The material-centered process of resolving existing
or deriving missing Renditions and Learning Resources needed to satisfy one
Capability Gap.
_Avoid_: Universal completeness, automatic generation, provider job

**Timeline Compatibility**: Verified evidence that timed Learning Resources can
be applied to a Media Rendition without changing their meaning or alignment.
_Avoid_: Matching Source Identity, approximate similarity

**Temporary Material**: A Language Material opened for immediate use without
being retained in the Personal Library.
_Avoid_: Learning Material, installed content

**Learning Material**: A Language Material as available inside Listen, composed
from Document Renditions, Media Renditions, and whatever Learning Resources are
currently available. It is valid without generated enrichment.
_Avoid_: Content Package, Catalog Entry

**Learning Resource**: A portable, provenance-bearing resource that makes a
Learning Material more usable for learning.
_Avoid_: Learner state, cache, model response

**Base Resource**: A Learning Resource that describes the material itself in its
Content Language, such as structured reading content, transcription,
segmentation, or timing.
_Avoid_: Translation, learner-specific explanation

**Structured Reading Resource**: A versioned, format-neutral Base Resource that
represents exact logical reading content as ordered hierarchy, blocks, and text
spans with Content Language metadata and stable Reading Anchors. It may map
those anchors back to one or more Document Renditions, but it is neither an
original document, a Markdown file, a rendered screen, nor a second Material.
_Avoid_: Document Rendition, Structured Material, Markdown document,
extracted-text cache, reading UI state

**Assistance Resource**: A Learning Resource that helps a particular audience,
such as a translation, explanation, hint, or level-specific annotation.
_Avoid_: Base Resource, Learning Fact

**Content Enrichment**: The optional process of deriving new Renditions or
Learning Resources from exact existing inputs to offer another Material
Capability or improve an available one.
_Avoid_: Required import step, Learning Activity

**Resource Provenance**: The origin, inputs, producer, model, configuration, and
transformation history needed to explain a Learning Resource.
_Avoid_: Quality guarantee, provider log

**Rendition Provenance**: The origin, exact inputs, producer, model,
configuration, and transformation history needed to explain a Derived
Rendition.
_Avoid_: Source Identity, quality guarantee, provider log

**Reading Anchor**: A stable identity for a logical block or span within one
exact Base Resource. Reading positions, annotations, corpus occurrences, and
dependent resources may use it; continuity across another resource or Material
Revision requires an explicit mapping.
_Avoid_: Paragraph index, file path, universal cross-version identity

**Rendition Locator**: A format-specific location inside one exact Document or
Media Rendition, such as a PDF page region, EPUB fragment, source character
range, or media-time range. It can connect a Reading Anchor to source
presentation but is not durable learner-state identity by itself.
_Avoid_: Reading Anchor, Material Revision, screen coordinate

## Discovery and acquisition

**Content Subscription**: The Learner's durable choice to receive future
Discovery Items from a Content Source.
_Avoid_: Personal Library membership, automatic download

**Discovery Item**: A source- or community-provided candidate for a Language
Material, Material Revision, or Learning Edition that the Learner has not yet
retained.
_Avoid_: Learning Material, Package Installation

**Material Acquisition**: The learner-authorized act of making required source
assets usable on a device through download, source playback, or binding a local
asset.
_Avoid_: Discovery, redistribution right, Package Installation

## Library and corpus

**Personal Library**: The Learner's explicitly retained collection of Learning
Materials. Membership is durable and synchronized; opening a Temporary Material
does not add it. Membership is independent of where a source asset is stored on
the learner's devices.
_Avoid_: Personal Corpus, playback history, Personal Library folder

**Managed Asset Store**: Device-local storage managed by Listen for verified
copies of source assets bound to retained Learning Materials. It supports local
availability but does not define Personal Library membership; a retained
material may instead reference an asset in place.
_Avoid_: Personal Library, Personal Library folder

**Personal Corpus**: A searchable view of language occurrences derived from the
Personal Library. The view is rebuildable; the library and resources are
authoritative.
_Avoid_: Personal Library, search-index files

**Community Corpus**: The searchable public corpus derived from published
Learning Editions and Package Releases.
_Avoid_: Personal Corpus, external search provider

**Corpus Occurrence**: One occurrence of a word, phrase, construction, sound, or
other language span in a specific material context, optionally anchored to a
media range.
_Avoid_: Search result row, dictionary entry, decontextualized token

**Search Scope**: The corpus boundary selected for a query: Current Material,
Personal Corpus, or Community Corpus.
_Avoid_: Separate search feature

**External Context Reference**: An ephemeral, attributed result from an
external context provider. It is not part of a Listen corpus unless the source
material enters through normal intake.
_Avoid_: Corpus Occurrence, imported Learning Resource

## Activity and personal state

**Learning Activity**: A way the Learner chooses to engage with a Learning
Material through listening, reading, speaking, writing, or a future experience.
_Avoid_: Mandatory lesson step, screen, feature

**Learning Fact**: A durable factual record of an explicit choice or meaningful
learning outcome. It excludes high-frequency telemetry and replaceable model
conclusions.
_Avoid_: Raw clickstream, Learning Inference

**Learning Record**: Learner-owned history and state that cannot be safely
reconstructed from public packages, including progress, notes, saved items, and
Learning Facts.
_Avoid_: Content Package, generated cache

**Lexical Capability Profile**: The Learner-owned assessment of one Lexical Unit
across independent reading, listening, speaking, and writing capabilities. Each
capability is unassessed, not acquired, or acquired; absence of evidence remains
unassessed, and explicit Learner authority outranks a replaceable projection.
_Avoid_: Package Resource, one linear vocabulary level

**Personal Expression**: A Learner-owned expression pattern, its immutable
revisions, and speaking or writing attempts. A source snapshot may preserve
origin, but the expression and history outlive the source.
_Avoid_: Community Learning Resource, generated phrase candidate

**Learning Inference**: A replaceable, versioned interpretation derived from
Learning Facts, such as difficulty or capability estimates.
_Avoid_: Learning Fact, permanent truth

**Training Candidate**: An optional, ranked suggestion for a next learning
action. It does not become a plan without the Learner's choice.
_Avoid_: Mandatory assignment, Learning Fact

## Distribution and community

**Content Package**: A portable, data-only bundle of material descriptors,
Renditions, and Learning Resources. It contains neither executable providers nor
personal Learning Records.
_Avoid_: Database export, model bundle, learner backup

**Delivery Profile**: How a Content Package supplies its blobs: embedded,
externally referenced, or a mixture.
_Avoid_: Separate package format

**Learning Edition**: One producer's coherent pedagogical composition of
compatible Renditions and Learning Resources for a Material Revision, declared
audience, Target Language, and optional Support Languages. It may offer one or
multiple Material Capabilities.
_Avoid_: Material Revision, Package Release

**Package Release**: An immutable, content-addressed publication of one Learning
Edition.
_Avoid_: Mutable latest package, Package Listing

**Package Listing**: A mutable community record grouping Package Releases and
carrying discovery, ranking, moderation, and update information.
_Avoid_: Content Package, immutable release

**Package Installation**: The local record that a Package Release was validated
and made available as candidate Renditions and Learning Resources. It neither
adopts the edition nor silently activates candidates.
_Avoid_: Download, Package Release, Learning Edition Adoption

**Learning Edition Adoption**: The Learner's explicit decision to use a
coherent selection of compatible Renditions and Learning Resources from an
installed Learning Edition for one Learning Material.
_Avoid_: Package Installation, package-declared active state

**Publisher Status**: The declared or verified identity class of a publisher,
independent of review quality and redistribution rights.
_Avoid_: Review Status, License Status

**Review Status**: The declared level and method of content review, independent
of publisher identity and redistribution rights.
_Avoid_: Publisher Status, correctness guarantee

**License Status**: Available evidence about permission to use or redistribute a
resource, independent of publisher identity and review quality.
_Avoid_: Publisher Status, availability
