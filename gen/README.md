# listen-gen

`listen-gen` is Listen's replaceable content-production toolkit and is intended
to become the ecosystem's open producer. Its stable output is a Content
Package v3 consumed by `listen-core`; model runtimes and raw provider payloads
are not part of that interface.

The repository does not yet contain an open-source license grant. Until the
owner selects and adds one, public source availability must not be described as
open-source permission.

Shared product semantics, language, context ownership, learner journeys,
development policy, and the project roadmap are canonical in
[`ichthyoplanktonzyh/listen`](https://github.com/ichthyoplanktonzyh/listen).
This repository's [CONTEXT.md](CONTEXT.md) defines only production-specific
terms, while `contracts.lock.json` identifies the package contract it consumes.

## Capability production

The entry point is `package from-capability`: one bounded request names an
exact Material Revision, the exact Renditions and Resources available to the
run, and one requested Material Capability. Gen plans the smallest derivation
graph, runs replaceable providers, reports honest events, and emits one
deterministic Content Package v3.

Derivations:

- **document → structured reading** — deterministic extraction for plain
  text, Markdown, HTML, and EPUB, PDF text-layer extraction (`pypdf`), and an
  optional OCR provider seam for scanned PDFs. OCR absence or failure is an
  honest capability result, never an import failure.
- **document → listen** — provider-neutral TTS behind a local macOS `say`
  adapter, a deterministic in-process fake, and a fixture adapter. A Derived
  audio Media Rendition and a separate anchor-to-time alignment Resource are
  produced; when exact timing cannot be produced, audio succeeds while
  synchronized reading stays unavailable — timing is never fabricated.
- **media → structured reading** — the existing ASR adapters (fixture,
  command, whisper.cpp) and exact media-time alignment behind the request
  interface.

An offline fixture flow exercises the full CLI without model credentials or
network access:

```bash
python -m listen_gen package from-capability request.json \
  --output /tmp/generated.zip \
  --tts-provider fake \
  --machine-events
```

See [docs/machine-event-protocol-v2.md](docs/machine-event-protocol-v2.md)
for the request schema, the event contract, and the failure codes.

## Deterministic release bundle

A deterministic, verifiable release bundle can be built from a clean
checkout:

```bash
python tools/release_bundle.py build \
  --source-commit "$(git rev-parse HEAD)" \
  --output-parent dist
```

The bundle is written to `dist/listen-gen-<version>/` and consists of a
runnable `.pyz` zipapp plus a `.release.json` manifest; both files must be
published together. Verify it before distribution:

```bash
python tools/release_bundle.py verify \
  dist/listen-gen-0.4.0/listen-gen-0.4.0.release.json
```

The `.pyz` requires Python 3.11 or newer. See
[docs/release-bundle-v1.md](docs/release-bundle-v1.md) for the full bundle
contract and distribution rules.

## Contract authority

The canonical schema is owned by `listen-core` at
`contracts/content-package/v3`. `contracts.lock.json` records that dependency.
This repository does not carry a schema copy.

## Development

```bash
python -m unittest discover -s tests -v
```

No model credentials or live services are used by these tests. To also send
the generated fixture package through Core's Rust inspector, explicitly point
the suite at a checkout:

```bash
LISTEN_CORE_CHECKOUT=/path/to/listen-core \
  python -m unittest discover -s tests -v
```
