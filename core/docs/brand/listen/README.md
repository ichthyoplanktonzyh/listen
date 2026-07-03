# listen Brand Draft

> Draft created: 2026-07-02
> Generation mode: built-in image generation (`imagegen` / image2 path)

## Direction

`listen` should make the product promise plain: listening is the core language
ability. The visual system should feel less like a media player and more like a
tool for turning sound into language structure and comprehension.

## Candidate Assets

| Asset | Role | Notes |
| --- | --- | --- |
| `assets/listen-icon-concept-a-literal-ear.png` | Conservative app icon concept | Clearest small-size read: ear + waveform + subtitle rhythm marks. Slightly more generic. |
| `assets/listen-icon-concept-a-1024.png` | 1024px app icon candidate | Resized working copy for iconset production. |
| `assets/listen-icon-concept-b-wave-to-language.png` | Recommended app icon concept | Stronger product metaphor: sound wave entering listening contour and becoming language/rhythm blocks. |
| `assets/listen-icon-concept-b-1024.png` | 1024px app icon candidate | Recommended resized working copy for iconset production. |
| `assets/listen-hero-concept-v1-multilingual.png` | Narrative hero concept | Strongest emotional/product story. Contains readable multilingual snippets, so treat as concept/reference unless that is intentional. |
| `assets/listen-hero-clean-v2.png` | Cleaner hero candidate | Removes stray subtitle text and keeps abstract rhythm/comprehension blocks. Better production starting point. |

## Recommendation

- App icon: start from `listen-icon-concept-b-wave-to-language.png`.
- Hero / launch visual: keep `listen-hero-concept-v1-multilingual.png` as the
  mood reference, then refine `listen-hero-clean-v2.png` until the wordmark and
  abstract language blocks are fully controlled.

## Prompt Intent

The generation prompts asked for:

- no headphones, microphone, play button, music note, flags, or generic audio
  app symbolism;
- a graphite/ink base with teal/cyan listening signal and warm amber
  comprehension accents;
- an ear-inspired contour, speech waveform, and subtitle/rhythm blocks;
- serious language-learning craft rather than a music or podcast identity.

## Next Steps

1. Pick one icon direction and generate a flatter vector-friendly pass for exact
   app icon production.
2. Export macOS icon sizes into `apps/desktop/macos/Runner/Assets.xcassets/AppIcon.appiconset/`.
3. Rename the app/product surface from `LLPlayerNext` to `listen` in a separate
   commit after the visual direction is approved.
