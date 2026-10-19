# ADR 0004: MVP Dictionary Provider

- Status: Accepted with release risk
- Date: 2026-06-09

## Decision

Use the public [Free Dictionary API](https://dictionaryapi.dev/) as the first
English dictionary provider. It returns definitions and phonetics without an
API key. The shared provider has a five-second timeout, maps responses into a
provider-independent model, and caches successful results locally for 30 days.

Dictionary lookup sends only the normalized language and lemma. It never sends
media paths, subtitles, playback history, or learning status. Failure, timeout,
offline operation, and no-result responses do not block playback, state
changes, or diagnosis.

## License And Availability

The service website states that the API is free for applications. Its server
source repository is GPL-3.0; no server source or dictionary data is bundled in
LLPlayerNext. The provenance and redistribution terms of returned dictionary
content are not sufficiently explicit for offline redistribution, so MVP only
caches results for personal local use and does not ship a dictionary dataset.

Before broader public or commercial distribution, confirm API terms and data
provenance or replace this provider with a source having explicit content
licensing.
