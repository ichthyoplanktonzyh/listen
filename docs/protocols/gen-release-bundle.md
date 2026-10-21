# Deterministic release bundle v1

Gen remains independently runnable in the Listen monorepo. Its immutable
bundle contains a Python zipapp and matching release manifest. The shared
current-source and product release workflows are documented in
[DEVELOPMENT.md](../../DEVELOPMENT.md); neither requires an older repository
checkout or a manually committed component pin.

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
- The toolchain covers the released zipapp's supported ASR providers
  (`fixture`, `command`, and `whisper-cpp`), with the Gen stage families
  (`media`, `asr`) that require each tool. It is the union of their requirements
  in `PROVIDER_REQUIREMENTS`; it does not describe every source-checkout adapter.
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
- Document extraction, OCR, and document-to-speech adapters are not included.
- These native tools and models are never placed inside the zipapp.

Qwen3 and SenseVoice are source-checkout adapters. Their sidecar launchers live
under `gen/tools/`, outside the zipapp's `listen_gen` source collection. They
require the corresponding Python extras, sidecar interpreter, model files,
and FFmpeg/FFprobe preprocessing tools. The zipapp does not supply those
launchers or runtimes; their direct provider options require a source checkout.
Model installation and downloads remain explicit opt-ins.

## Content package contract identity

The manifest's `content_package_contract` block pins the exact Core
contract the bundle produces packages against:

```json
"content_package_contract": {
  "authority": {
    "repository": "ichthyoplanktonzyh/listen",
    "path": "core/contracts/content-package/v3"
  },
  "release_schema_id": "listen.content-package.release.v3",
  "package_schema": "listen.content-package.release.v3",
  "schema_version": 3,
  "contract_version": "5.0.0",
  "canonical_sha256": "sha256:<release.schema.json file digest>"
}
```

`contract_version` and `canonical_sha256` come **only** from a fresh
Core contract artifact manifest from the same source snapshot (the `listen-contracts-<version>.
manifest.json` produced by Core's `release_artifacts.py contract`); the
`canonical_sha256` is the SHA-256 of that manifest's
`contracts/content-package/v3/release.schema.json` file entry, copied
verbatim. Gen never invents a Core release identity: a build without the
Core manifest fails instead of recording a fabricated version or digest.

## Building

Build from a clean, merged or tagged checkout. `--source-commit` must be the
exact commit of that checkout, and `--core-contract-manifest` must name a
fresh Core contract artifact manifest from the same source snapshot:

```bash
python tools/release_bundle.py build \
  --source-commit "$(git rev-parse HEAD)" \
  --core-contract-manifest /path/to/listen-contracts-5.0.0.manifest.json \
  --output-parent dist
```

Output layout:

```text
dist/listen-gen-0.5.2/
├── listen-gen-0.5.2.pyz
└── listen-gen-0.5.2.release.json
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
  dist/listen-gen-0.5.2/listen-gen-0.5.2.release.json \
  --core-contract-manifest /path/to/listen-contracts-5.0.0.manifest.json
```

The verifier strictly parses the manifest — including the complete
`runtime_identity` block, whose schema, versions, runtime, and toolchain must
exactly match the release source constants — and checks the artifact size,
SHA-256, shebang, and the complete archive structure and entry contents
against the source tree, without executing any archive code. The contract
version and digest must exactly match the supplied Core artifact manifest,
and its source commit must match the Gen source commit.
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

Distribute the `.pyz` and `.release.json` together. The App verifies their
identity and exact hashes against a generated product lock. Debug development
uses an explicitly generated lock for the current source; formal releases embed
the generated lock and ignore debug lock overrides. Published artifacts remain
immutable. The zipapp retains its independent CLI and Python requirement.
