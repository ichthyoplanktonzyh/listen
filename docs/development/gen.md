# Gen development

Run shared setup from the root with `./dev setup`. The independent Python CLI
and its deterministic fixture providers remain available inside `gen/`.
Python 3.11+ is required; `pypdf` is a base dependency for PDF text extraction.
Heavy ASR, alignment, OCR, and TTS providers are optional extras.

## CLI and tests

From `gen/`:

```sh
.venv/bin/python -m listen_gen --help
.venv/bin/python -m unittest discover -s tests -v
```

A bounded capability request names exact material/revision inputs and a
requested capability. The CLI emits a deterministic Content Package v3:

```sh
.venv/bin/python -m listen_gen package from-capability request.json \
  --output /tmp/generated.zip --tts-provider fake --machine-events
```

Use a fixture request compatible with the selected fake/fixture provider;
see [tests](../../gen/tests/). Ordinary tests and root `./dev test integration`
use deterministic inputs and no live model credentials. Inspect
[cli.py](../../gen/src/listen_gen/cli.py) for current provider and option names.

## Optional providers and workbench

Provider runtimes and weights are separately installed and configured. Install
only the extras needed for the chosen provider; their declarations are in
[pyproject.toml](../../gen/pyproject.toml). A missing provider or model is an
explicit failure, not permission to switch providers or fabricate resources.
No model download or paid inference is part of ordinary setup/tests.

The current independent workbench is launched from `gen/`:

```sh
.venv/bin/python -m listen_gen gui
```

It serves a local provider/generation UI. Its profiles, task history, sources,
and generated packages are local user data, not repository documentation or
fixtures. This workbench is existing implementation, not a new commitment to
keep it in the main-branch scope; that selection belongs to the current
[roadmap](../../ROADMAP.md).

## Integration and packaging

Canonical schemas live in [Core contracts](../../core/contracts/content-package/v3/).
Gen does not carry a second schema tree. Machine events and release manifests
have their own [protocol](../protocols/gen-machine-events.md) and
[bundle contract](../protocols/gen-release-bundle.md).

Root `./dev release` supplies a fresh Core contract manifest and common source
identity. The independent builder/verifier is
[release_bundle.py](../../gen/tools/release_bundle.py); inspect its help for
standalone use. A `.pyz` carries Gen source, not a Python interpreter or optional
model runtimes. See [distribution requirements](dev-preview-distribution.md).
