# ADR 0036: Open Resource Package Ecosystem

- Status: Accepted
- Date: 2026-08-01

Listen will use an Anki-like open ecosystem: `.listenpkg` is an open,
immutable, pure-data format; `listen-gen` is an open producer with replaceable
providers; and `listen-app` plus `listen-core` form the trusted consumption and
learning plane. Media, Package Releases, and learner records stay independent;
official and community publishers use the same package contract; updates add
candidates without changing active selections; and direct local import plus
future third-party registries remain supported. This preserves user agency and
provider choice while allowing commercial value in the App, synchronization,
hosted generation, curated discovery, and related services.

Package distribution separates mutable Package Listings from digest-addressed
immutable Package Releases. Publisher Status, Review Status, and License Status
are independent facts. The permanently free Official Starter Catalog seeds the
ecosystem using self-produced, public-domain, openly licensed, or explicitly
authorized media without receiving hidden format privileges.

Community reuse also requires layered media identity: Source Identity,
Content Edition, Media Rendition, and Timeline Compatibility are different
concepts. Content Package v1 retains exact media SHA-256 matching while later
contracts design cross-rendition compatibility explicitly. Discovery,
playback, and media acquisition remain separate capabilities; no source
identity implies download rights.

The Hosted Catalog/Registry is a future optional fourth role whose repository,
protocol, moderation, federation, and deployment are not decided by this ADR.
Exact source and contributor licenses, publisher signatures, and hosted-service
pricing also remain separate decisions.
