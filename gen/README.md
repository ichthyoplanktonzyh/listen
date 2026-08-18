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
  optional OCR provider seam for scanned PDFs. Markdown is parsed
  semantically (heading/paragraph structure preserved, markup markers never
  reach speech text); HTML discards script/style/navigation; EPUB preserves
  spine order and chapter boundaries. OCR absence or failure is an honest
  capability result, never an import failure. Every derivation emits exactly
  one self-contained Structured Reading resource.
- **document → listen** — provider-neutral TTS behind a local macOS `say`
  adapter, a deterministic in-process fake, and a fixture adapter. TTS
  consumes only the exact logical text of a Structured Reading through an
  internal production input projection (never the raw document). The `say`
  adapter synthesizes per sentence, measures each segment's real duration,
  and concatenates the audio, so the anchor-to-time alignment comes from
  measured segment boundaries; when exact timing cannot be produced, audio
  succeeds while synchronized reading stays unavailable — timing is never
  fabricated.
- **media → structured reading** — the existing ASR adapters (fixture,
  command, whisper.cpp) and exact media-time alignment behind the request
  interface. Provider, model, and configuration facts flow into resource
  provenance and never leak raw output or paths into the package.

An offline fixture flow exercises the full CLI without model credentials or
network access:

```bash
python -m listen_gen package from-capability request.json \
  --output /tmp/generated.zip \
  --tts-provider fake \
  --machine-events
```

## Model Providers & Generation GUI

Launch the local GUI management workbench:

```bash
./run_gui.sh
# or using the virtualenv:
source .venv/bin/activate && listen-gen gui
```

The GUI workbench is served at `http://127.0.0.1:8420` and allows managing LLM, ASR (Whisper.cpp), phonetic models (Wav2Vec2), alignment, TTS, running connectivity tests, and launching generation pipelines.

The workbench ships as a zero-runtime-dependency stack (Python standard
library server + single-file frontend) with:

- **Provider management** — LLM profiles (DeepSeek/OpenAI/Anthropic/Gemini/
  custom), Whisper.cpp, Wav2Vec2, aligner and TTS configuration persisted to
  `~/.listen-gen/profiles.json`, with connectivity tests and validation on
  save.
- **Generation pipeline** — submit a bounded capability request from document
  or media input, watch the live v2 machine-event stream (accept → plan →
  running → completed/cancelled/failed), download the produced Content
  Package v3, or cancel a running task between stages.
- **Run queue with a concurrency cap** — submissions run through a FIFO
  scheduler that starts at most `$LISTEN_GEN_MAX_CONCURRENT_RUNS` workers in
  parallel (default 2, set to 1 to fully serialize); extra requests stay
  `queued` (with their position shown) and can be cancelled before they
  start. This prevents a burst of clicks from spawning many heavy
  subprocesses (`say` / `whisper.cpp`) at once.
- **One-click rerun** — every task stores its request and config snapshot, so
  a finished run can be re-submitted verbatim (source files re-verified on
  disk, digests recomputed); text inputs are persisted under
  `~/.listen-gen/sources` so they can be re-read.
- **Persistent artifacts** — produced packages live in
  `~/.listen-gen/artifacts` and stay downloadable across restarts.
- **Persistent task history** — every run is recorded in
  `~/.listen-gen/tasks.json` and survives restarts; the 任务历史 tab lists
  past runs with per-task event replay, status, timestamps and artifact
  download. Tasks still queued/running when the server exits are restored as
  failed with an honest `server_restarted` error.
- **Per-task stats & export** — the task detail panel shows total duration,
  per-stage timings and the packaged resource/media manifest; the full event
  log (with recorded timestamps) can be downloaded as JSON.
- **Resilient event streaming** — SSE frames carry per-task sequence ids, so
  a dropped connection resumes from the last delivered event
  (`Last-Event-ID`) instead of re-reading from the start.
- **Streaming file uploads** — documents, media and subtitles are sent as
  `multipart/form-data` with progress feedback (no base64 memory blowups for
  large files); stale uploads and sources are pruned after 7 days.

Run the GUI test coverage with:

```bash
python -m unittest tests.test_gui -v
```

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
  dist/listen-gen-0.5.0/listen-gen-0.5.0.release.json
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
