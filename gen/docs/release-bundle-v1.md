# Deterministic release bundle v1

The release bundle is the immutable Gen handoff for the three-repository
local exact-media round trip. It is **not** the final user-facing standalone
native application; it replaces sibling checkouts, `PYTHONPATH=src`, and
unpinned local source with two pinned files that must be distributed together:

```text
listen-gen-<version>.pyz
listen-gen-<version>.release.json
```

The `.pyz` is a runnable Python zipapp containing the complete `listen_gen`
source. The `.release.json` manifest pins the tool version, the Git source
commit, the machine-event protocol identity, the Content Package contract
identity, and the artifact filename, size, and SHA-256.

## Runtime requirements

- The `.pyz` still requires Python 3.11 or newer; nothing is vendored.
- The `fixture` provider needs no external media commands.
- The `command` provider needs `ffprobe`, `ffmpeg`, and the external ASR
  wrapper.
- The `whisper-cpp` provider needs `ffprobe`, `ffmpeg`, `whisper-cli`, and a
  whisper model.
- These native tools and models are never placed inside the zipapp.

## Building

Build from a clean, merged or tagged checkout. `--source-commit` must be the
exact commit of that checkout:

```bash
python tools/release_bundle.py build \
  --source-commit "$(git rev-parse HEAD)" \
  --output-parent dist
```

Output layout:

```text
dist/listen-gen-0.1.0/
├── listen-gen-0.1.0.pyz
└── listen-gen-0.1.0.release.json
```

The build is deterministic: identical source, version, and generation rules
produce byte-identical `.pyz` and `.release.json` files regardless of the
checkout path or the output directory. The build never calls Git, never
accesses the network, and never overwrites an existing bundle directory.
Recorded metadata excludes checkout paths, user and host names, build time,
operating system, branch names, and local tool or model paths.

## Verification

Run the verifier before publishing:

```bash
python tools/release_bundle.py verify \
  dist/listen-gen-0.1.0/listen-gen-0.1.0.release.json
```

The verifier strictly parses the manifest, checks the artifact size,
SHA-256, shebang, and the complete archive structure and entry contents
against the source tree, without executing any archive code. On success it
prints one canonical JSON line with `"status": "verified"`.

Recipients must at minimum verify the manifest's artifact SHA-256 before
executing the `.pyz`.

## Fixture smoke

```bash
python dist/listen-gen-0.1.0/listen-gen-0.1.0.pyz --help
python dist/listen-gen-0.1.0/listen-gen-0.1.0.pyz package from-media \
  tests/fixtures/sample-media.wav \
  --provider fixture --fixture tests/fixtures/sample.asr.json \
  --title "Smoke" --media-kind audio --duration-ms 2200 \
  --created-at-ms 1786000000000 --output /tmp/smoke.listenpkg
```

## Distribution rules

1. Upload and distribute the `.pyz` and `.release.json` together; they are
   meaningless apart.
2. The App consumes the bundle later via version and checksum pins, never via
   a source checkout.
3. This change creates no tag, publishes no GitHub Release, and does not
   modify the App lock.
4. PyInstaller, wheel release flows, and system Python installs are not
   claimed to be equivalent to this bundle.
