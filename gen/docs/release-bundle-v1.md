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
identity, the runtime/toolchain identity, and the artifact filename, size,
and SHA-256.

## Runtime identity

The manifest carries an explicit, versioned runtime/toolchain identity in
`runtime_identity`:

```json
"runtime_identity": {
  "schema": "listen_gen.runtime-identity.v1",
  "version": 1,
  "runtime": {"family": "python", "requires": ">=3.11"},
  "toolchain": {
    "schema": "listen_gen.toolchain-identity.v1",
    "version": 1,
    "tools": [
      {"id": "asr-wrapper", "roles": ["asr"]},
      {"id": "ffmpeg", "roles": ["media", "asr"]},
      {"id": "ffprobe", "roles": ["media", "asr"]},
      {"id": "whisper-cli", "roles": ["asr"]},
      {"id": "whisper-model", "roles": ["asr"]}
    ]
  }
}
```

The identity is the verifier-checked contract between the released bundle and
the runtime/toolchain it may bind to:

- The runtime is the interpreter family and version requirement the zipapp
  itself needs.
- The toolchain is every external tool the bundle may invoke across the
  declared ASR providers, with the Gen stage families (`media`, `asr`) that
  require each tool. It is exactly the union of the per-provider requirements
  in `PROVIDER_REQUIREMENTS`.
- Consumers record this identity immutably in their pin and the verifier
  rejects any manifest whose identity drifts from the source constants, so a
  release cannot silently add, drop, or re-role a tool.

## Runtime requirements

- The `.pyz` still requires Python 3.11 or newer; nothing is vendored.
- The `fixture` ASR provider needs no external media commands.
- The `command` ASR provider needs `ffprobe`, `ffmpeg`, and the external ASR
  wrapper.
- The `whisper-cpp` ASR provider needs `ffprobe`, `ffmpeg`, `whisper-cli`,
  and a whisper model.
- The `fake` and `fixture` TTS providers need no external commands; the `say`
  TTS provider binds to the macOS `say` and `afconvert` executables.
- The `fixture` OCR provider needs no external commands; the absence of a
  real OCR adapter is an honest capability result, not a hidden pipeline.
- These native tools and models are never placed inside the zipapp.

## Content package contract identity

The manifest's `content_package_contract` block pins the exact listen-core
contract the bundle produces packages against:

```json
"content_package_contract": {
  "authority": {
    "repository": "ichthyoplanktonzyh/listen-core",
    "path": "contracts/content-package/v3"
  },
  "release_schema_id": "listen.content-package.release.v3",
  "package_schema": "listen.content-package.release.v3",
  "schema_version": 3,
  "contract_version": "4.0.0",
  "canonical_sha256": "sha256:<release.schema.json file digest>"
}
```

`contract_version` and `canonical_sha256` come **only** from a real
listen-core contract artifact manifest (the `listen-contracts-<version>.
manifest.json` produced by Core's `release_artifacts.py contract`); the
`canonical_sha256` is the SHA-256 of that manifest's
`contracts/content-package/v3/release.schema.json` file entry, copied
verbatim. Gen never invents a Core release identity: a build without the
Core manifest fails instead of recording a fabricated version or digest.

## Building

Build from a clean, merged or tagged checkout. `--source-commit` must be the
exact commit of that checkout, and `--core-contract-manifest` must name a
real listen-core contract artifact manifest:

```bash
python tools/release_bundle.py build \
  --source-commit "$(git rev-parse HEAD)" \
  --core-contract-manifest /path/to/listen-contracts-4.0.0.manifest.json \
  --output-parent dist
```

Output layout:

```text
dist/listen-gen-0.5.0/
├── listen-gen-0.5.0.pyz
└── listen-gen-0.5.0.release.json
```

The build is deterministic: identical source, version, contract identity,
and generation rules produce byte-identical `.pyz` and `.release.json` files
regardless of the checkout path or the output directory. The build never
calls Git, never accesses the network, and never overwrites an existing
bundle directory. Recorded metadata excludes checkout paths, user and host
names, build time, operating system, branch names, and local tool or model
paths.

## Verification

Run the verifier before publishing:

```bash
python tools/release_bundle.py verify \
  dist/listen-gen-0.5.0/listen-gen-0.5.0.release.json \
  --core-contract-manifest /path/to/listen-contracts-4.0.0.manifest.json
```

The verifier strictly parses the manifest — including the complete
`runtime_identity` block, whose schema, versions, runtime, and toolchain must
exactly match the release source constants — and checks the artifact size,
SHA-256, shebang, and the complete archive structure and entry contents
against the source tree, without executing any archive code. The contract
version and digest must exactly match the supplied Core artifact manifest.
On success it
prints one canonical JSON line with `"status": "verified"`, the tool
identity, the artifact SHA-256, and the verified `runtime_identity`.

Recipients must at minimum verify the manifest's artifact SHA-256 before
executing the `.pyz`, and record the returned `runtime_identity` immutably
with the bundle pin.

## Fixture smoke

```bash
python dist/listen-gen-0.5.0/listen-gen-0.5.0.pyz --help
python dist/listen-gen-0.5.0/listen-gen-0.5.0.pyz package from-capability \
  /path/to/capability.json \
  --provider fixture --fixture tests/fixtures/sample.asr.json \
  --machine-events
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
