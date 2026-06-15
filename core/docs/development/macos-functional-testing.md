# macOS Functional Testing

## Preferred Order

1. When independent distribution signing is available, build the archive,
   extract it, and launch the extracted `LLPlayerNext.app`. Run
   `scripts/verify-mvp.sh`.
2. If the newly built app cannot be launched because local signing or AMFI
   rejects it, use the development workflow below for functional testing.
3. Record independent archive launch separately from functional acceptance
   while Developer ID signing/notarization remains deferred.

## Development Run Fallback

Run from a terminal:

```sh
cd /Users/shadow/LLPlayerNext
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH"
cargo build -p api-http
cd apps/desktop
flutter run -d macos
```

The first command builds the Rust local API sidecar. Running Flutter from
`apps/desktop` discovers the sidecar by searching the current directory and
development app executable ancestors for `target/debug/api-http`.

Keep the terminal open while testing:

- press `r` for hot reload;
- press `R` for a full hot restart;
- press `q` to stop the application.

Do not use Xcode's Run button as a substitute for this workflow unless its
launched app can locate an `api-http` sidecar. A missing sidecar produces the
visible error `Local API sidecar not found`.

## Signing Check

Before retrying packaged-app acceptance, run:

```sh
security find-identity -v -p codesigning
```

A usable local development signing setup must report at least one valid
identity backed by a private key. If it reports `0 valid identities found`,
continue functional testing with `flutter run` and leave packaged launch
acceptance open.

An `Apple Development` identity is sufficient for Xcode-managed development
launches. It is not a standalone distribution identity: copying or extracting
that signed app outside Xcode's registered development location may still be
rejected by macOS. For an independently distributed archive, use a
`Developer ID Application` identity and the release distribution/notarization
workflow.
