# LLPlayerNext Project Handoff: 2026-06-13 M2.0 Start

## Repository State

- Workspace: `/Users/shadow/LLPlayerNext`
- Branch: `codex/milestone-1.9-pronunciation-sync`
- Milestone 1.9 / version 0.7.0 is fully accepted.
- Start the next thread by reading `docs/planning/milestone-2.0.md`.

Preserve these user-owned, uncommitted paths exactly as they are:

- `apps/desktop/macos/Runner.xcodeproj/project.pbxproj`
- `.claude/`
- `docs/architecture/flutter-refactoring-plan.md`

## Milestone 1.9 Closure

Collaborative functional acceptance confirmed:

- ordinary video, AV1 video, audio, controls, and subtitles;
- estimated current-word synchronization across playback state changes;
- canonical pronunciation, IPA, rule predictions, and safe degradation;
- background, scale-bounce, and glow current-word styles;
- persistent settings and learning-status presentation.

The acceptance fixes and documentation are in:

- `c715d40 fix: complete milestone 1.9 functional acceptance`
- `ee3ddb2 docs: clarify macos development signing boundary`

The historical implementation and packaging investigation is recorded in
`docs/handoff/project-handoff-2026-06-12-m1.9-packaging.md`.

## Accepted Distribution Limitation

The current keychain reports one valid Apple Development signing identity
backed by its private key. Development testing through `flutter run` or Xcode
works. Apple Development signing does not make the independently extracted app
launchable on this Mac; direct launch is terminated by system policy.

The user explicitly deferred all of the following from M1.9:

- Developer ID Application signing;
- notarization;
- reliable double-click launch of independently extracted release archives;
- final public-distribution hardening.

Do not reopen this as an M1.9 blocker. Track it as later release work.

## Standard Functional Test Workflow

When double-clicking a newly built app is unavailable:

```bash
cd /Users/shadow/LLPlayerNext
export PATH="/opt/homebrew/opt/rustup/bin:$HOME/.local/share/flutter/bin:$PATH"
cargo build -p api-http
cd apps/desktop
flutter run -d macos
```

`scripts/verify-mvp.sh` remains useful when independent distribution signing is
implemented, but it is not the current functional acceptance path.

## Next Work: Milestone 2.0

Milestone 2.0 targets real-speech phoneme analysis. It is a high-risk research
milestone and must begin with Phase 0, not product integration.

The next thread should:

1. Read `docs/planning/milestone-2.0.md` and the M1.9 pronunciation/timing ADR.
2. Review and confirm the Phase 0 evaluation set, candidate providers, license
   constraints, quality thresholds, and Apple Silicon performance thresholds.
3. Produce a concrete Phase 0 research plan before adding a production
   provider or claiming any result was detected in real audio.
4. Preserve the M1.9 boundary: rule hints are predictions unless supported by
   actual audio evidence meeting the M2.0 confidence gate.

Candidate providers listed in the plan include Wav2IPA/Buckeye, ZIPA,
Wav2Vec2Phoneme or equivalent local models, with Allosaurus limited to a
research baseline because of licensing constraints.

## Verification Baseline

- `scripts/verify-m19.sh` passed after M1.9 integration and acceptance fixes.
- Rust formatting, tests, clippy, Flutter analysis/tests, and contract
  validation passed during M1.9 verification.
- Collaborative functional acceptance completed on 2026-06-12.
- Final M1.9 acceptance decision was recorded on 2026-06-13.

Do not claim M2.0 completion unless a provider meets the quality and licensing
release gates documented in `docs/planning/milestone-2.0.md`.
