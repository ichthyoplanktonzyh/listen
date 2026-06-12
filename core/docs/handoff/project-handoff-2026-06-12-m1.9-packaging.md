# LLPlayerNext Project Handoff: 2026-06-12 M1.9 Packaging

## 1. Repository State

- Workspace: `/Users/shadow/LLPlayerNext`
- Branch: `codex/milestone-1.9-pronunciation-sync`
- Latest committed change before this handoff:
  `a2d1609 fix: render packaged desktop startup`
- Do not touch the user-owned untracked paths:
  - `.claude/`
  - `docs/architecture/flutter-refactoring-plan.md`
- `apps/desktop/macos/Runner.xcodeproj/project.pbxproj` is modified by the
  user's Xcode signing attempt. It contains Personal Team
  `X6MK9RZ95J`, but also unrelated Xcode project-format churn and still forces
  the macOS signing identity to `-`. It is intentionally not included in the
  packaging commit.

## 2. M1.9 Implementation Status

M1.9 is functionally implemented and integrated with the modular Flutter
frontend. Important commits:

- `56e37c2 feat: complete milestone 1.9 acceptance candidate`
- `0e12dd8 refactor: integrate modular frontend with milestone 1.9`
- `b5a7a7f feat: close milestone 1.9 verification gaps`
- `2368cbc fix: remove blank startup stall`
- `a2d1609 fix: render packaged desktop startup`

Collaborative functional acceptance completed on 2026-06-12 through
`flutter run`. The remaining M1.9 closure blocker is independent packaged-app
execution on this Mac. Do not create the `v0.7.0` tag until packaged smoke
passes.

## 3. White-Screen Fixes Already Committed

Two independent white-screen causes were found and fixed:

1. API startup synchronously hashed the installed 66 MB ECDICT resource.
   Startup is now fast, and the UI shows explicit startup/error states.
2. Flutter failed its first frame with:

   `List<dynamic> is not a subtype of List<PlayerTrack>`

   Player track state is now strongly typed.

The packaged app also now prefers its bundled `api-http` instead of accidentally
using `target/release/api-http` when launched from the repository.

## 4. Current Packaging Facts

The build script changes staged for the next commit:

- Run `flutter clean` before release packaging so prior mutated build products
  cannot affect the archive.
- Clear extended attributes before and after ad-hoc signing.
- Update top-level app timestamps so Finder no longer displays the stale
  `00:17` directory timestamp.
- Use `COPYFILE_DISABLE=1 zip -X` instead of `ditto -c -k`.
- Reject archives containing `._*` AppleDouble files or `.DS_Store`.

These changes fix a real packaging defect. Earlier archives contained files
such as `._CodeResources` and `._LLPlayerNext`, causing:

`bundle format unrecognized, invalid, or unsuitable`

Current archive:

- Path: `/Users/shadow/LLPlayerNext/dist/LLPlayerNext-macos-arm64.zip`
- Built: `2026-06-12 20:51:17`
- SHA-256:
  `0a8292f30083e9503a63a9780d7da8278e28c8747585d0c8a5d0023a68cf4788`
- It contains no `._*` metadata files.
- It is still not independently executable because AMFI rejects the new
  ad-hoc signature.

## 5. AMFI / Signing Blocker

Current machine state:

```text
Developer mode is currently enabled.
0 valid identities found
```

Every clean build is finally signed with:

```bash
codesign --force --deep --sign - LLPlayerNext.app
```

This creates a new ad-hoc signature. On this macOS 26.2 machine, newly built
Release apps and newly re-signed Debug apps are killed with `SIGKILL 9` before
Flutter writes any log. The older experimental app at
`/tmp/llplayernext-clean-stage.qmXAq4/LLPlayerNext.app` still runs, apparently
because its earlier ad-hoc signature hash is already accepted/cached locally.

Important: Developer Mode and the Terminal Developer Tools toggle do not make
all newly generated ad-hoc signatures reliably executable.

The user created an Apple Development certificate record in Xcode, but:

```bash
security find-identity -v -p codesigning
```

still reports `0 valid identities found`. The likely missing piece is a valid
certificate/private-key pair in the login keychain.

## 6. Incorrect Hypotheses That Must Not Be Repeated

- The stale Finder timestamp was not proof that the archive contained old code.
- Universal `x86_64 + arm64` architecture is not the root cause.
- Do not thin the app or frameworks to arm64.
- A thin-arm64 experiment appeared to launch, but later inspection showed the
  supposedly successful experimental main executable was still universal; the
  thinning operation had not actually produced the claimed evidence.
- The frontend white-screen bug is fixed; current immediate termination happens
  before Flutter startup.

## 7. Recommended Next Steps

1. Help the user inspect Keychain Access:
   `login` -> `My Certificates` -> `Apple Development`.
2. Confirm the certificate expands to a private key.
3. Re-run:

   ```bash
   security find-identity -v -p codesigning
   ```

4. Once a valid identity exists, update `scripts/build-macos-mvp.sh` to select
   that identity instead of `--sign -`.
5. Sign nested executable code correctly, then sign the outer app.
6. Rebuild and run:

   ```bash
   /bin/bash scripts/verify-mvp.sh
   ```

7. Extract the final archive and verify Finder-equivalent launch:

   ```bash
   open -n /path/to/LLPlayerNext.app
   ```

8. Complete manual M1.9 acceptance, then create `v0.7.0`.

Paid Developer ID is not required for local development signing. It will be
required later for stable distribution to other Macs.

## 8. Verification History

Before the signing investigation:

- Flutter analyze passed.
- Flutter tests passed: 36 tests.
- Rust tests/clippy and `scripts/verify-m19.sh` passed.
- Packaged smoke previously passed while an accepted/cached ad-hoc build was in
  use.

Current clean package smoke fails immediately with `SIGKILL 9`, empty desktop
log, and no valid code-signing identity. Treat this as the active blocker, not
as an application logic regression.

## 9. Collaborative Functional Acceptance Update

- The standard fallback when double-clicking a newly built app is blocked is:

  ```bash
  cd /Users/shadow/LLPlayerNext
  export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH"
  cargo build -p api-http
  cd apps/desktop
  flutter run -d macos
  ```

- This fallback passed collaborative functional acceptance, including AV1
  playback and estimated current-word sync.
- Acceptance found and fixed the Flutter word-timing API field mapping.
- Current-word presentation now supports background highlight, scale bounce,
  and glow. Underline remains reserved for phrase candidates.
- See `docs/development/macos-functional-testing.md` and
  `docs/verification/milestone-1.9-acceptance.md`.
- The fallback does not replace independent package launch smoke.
