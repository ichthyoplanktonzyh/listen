# Ubiquitous Language

## Content Source

An external origin from which a piece of content is known, such as a podcast
feed, a YouTube channel, a publisher catalog, or a user-owned local collection.

## Source Identity

A stable, source-scoped identifier for one content item, such as a podcast
episode GUID or a YouTube video ID. It identifies provenance, not byte-level or
timeline compatibility.

## Content Edition

A particular editorial version of a source item. Trimming, replaced audio,
redubbing, or another change that alters the learning timeline creates a
different edition even when the Source Identity remains the same.

## Media Rendition

A concrete encoded media file for a Content Edition, including its container,
audio tracks, codecs, duration, and byte fingerprint. Multiple renditions can
represent the same edition without being byte-identical.

## Timeline Compatibility

Evidence that package time coordinates can be applied safely to a Media
Rendition. Compatibility may be exact, verified compatible, unverified, or
incompatible; sharing a Source Identity alone is not sufficient evidence.

## Media Offer

A lawful way to obtain or play a Media Rendition, together with availability,
license, integrity, and acquisition metadata. It is separate from a learning
resource package.

## Catalog Entry

The discoverable record that relates a Content Source and Content Edition to
its metadata, Media Offers, and Package Listings.

## Catalog Channel

A versioned, subscribable collection of Catalog Entries curated by an official
or community publisher.

## Package Listing

A mutable discovery record for a package series, including description,
publisher presentation, ratings, reports, and pointers to Package Releases.

## Package Release

An immutable, content-addressed publication of a `.listenpkg`, identified by
its digest and carrying its resource inventory, provenance, compatibility,
license, and optional publisher signature.

## Package Installation

The local record that a particular Package Release was verified and imported,
including its installed resources and local lifecycle state.

## Learning Material

The local composition of a playable Media Rendition with installed resource
candidates and the learner's explicit active selections.

## Publisher Status

The verified identity or trust classification of the entity distributing a
Package Release, such as official, verified community, ordinary community, or
unsigned local. It does not imply review quality or license validity.

## Review Status

The independently reported degree of quality review applied to a Package
Release, such as machine checked, sample reviewed, or fully human reviewed. It
does not imply publisher identity or license validity.

## License Status

The independently reported state of rights and redistribution evidence for a
Media Offer or Package Release, such as verified, publisher declared, or
unknown. It does not imply publisher identity or review quality.

## Official Starter Catalog

The official, permanently free, preferably sign-in-free Catalog Channel of
lawfully distributable starter materials and Package Releases used to provide
a complete first-run learning experience and public quality examples.
