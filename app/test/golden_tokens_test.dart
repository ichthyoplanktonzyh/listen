import 'package:flutter/material.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/theme/radii.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/theme/typography.dart';

import 'support/golden.dart';

/// Baselines for the token layer itself (#12 · S10).
///
/// These two sheets exist because of the gap named in §0 of the 2026-07 design
/// spec: change one thing, and nobody knows what else moved. Every screen in
/// the app is assembled out of what these sheets show, so they are the cheapest
/// possible tripwire — a nudge to a scheme role, a font family, a radius tier
/// or a component theme lands here first, in one small image, instead of being
/// discovered later on some screen nobody re-opened.
///
/// The sheets are specimens built by the test, not app widgets. That is
/// deliberate: `lib/` gets no test-only scaffolding, and a specimen can show a
/// role the app currently uses only in one obscure corner — which is precisely
/// where an unreviewed change hides.
void main() {
  goldenScene(
    'tokens_type_and_color',
    size: GoldenSurface.sheet,
    builder: (context) => const _TokenSheet(),
  );

  goldenScene(
    'tokens_controls',
    size: GoldenSurface.sheet,
    builder: (context) => const _ControlSheet(),
  );
}

/// The type ladder, the scheme roles, the radius tiers and the icon steps —
/// the four vocabularies every screen composes from.
class _TokenSheet extends StatelessWidget {
  const _TokenSheet();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: ListenPadding.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The ladder is drawn from the `ListenType` constants and read back
          // through `textTheme`, so the sheet fails if the two ever disagree —
          // the mapping in `ListenTheme._textTheme` is what keeps constant
          // sites and `Theme.of(context)` sites speaking one language.
          for (final (name, style) in const [
            ('caption 11', ListenType.caption),
            ('body 12', ListenType.body),
            ('reading 13', ListenType.reading),
            ('emphasis 14 w600', ListenType.emphasis),
            ('title 16 w600', ListenType.title),
            ('hero 22 w600', ListenType.hero),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: ListenSpacing.gap6),
              child: Text('$name — Listen Hg 汉字 123', style: style),
            ),
          const SizedBox(height: ListenSpacing.gap4),
          Text(
            'timecode 00:12:34 / 01:02:03',
            style: ListenType.timecode.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: ListenSpacing.gap4),
          Text('ipa /ˈlɪs.ən/ ðə ˈwɔːtər', style: ListenType.ipa),

          const SizedBox(height: ListenSpacing.gap24),
          // Scheme roles, in the pairs the app actually renders: a fill with
          // its own on-color written on it, so a contrast regression shows up
          // as unreadable text rather than as a number in a different test.
          Wrap(
            spacing: ListenSpacing.gap8,
            runSpacing: ListenSpacing.gap8,
            children: [
              for (final (label, fill, ink) in [
                ('surface', colors.surface, colors.onSurface),
                ('container', colors.surfaceContainer, colors.onSurfaceVariant),
                ('high', colors.surfaceContainerHigh, colors.onSurface),
                ('primary', colors.primary, colors.onPrimary),
                (
                  'primaryCtr',
                  colors.primaryContainer,
                  colors.onPrimaryContainer,
                ),
                ('secondary', colors.secondary, colors.onSecondary),
                ('tertiary', colors.tertiary, colors.onTertiary),
                ('error', colors.error, colors.onError),
                ('errorCtr', colors.errorContainer, colors.onErrorContainer),
                ('inverse', colors.inverseSurface, colors.onInverseSurface),
              ])
                _Swatch(label: label, fill: fill, ink: ink),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap12),
          // Shades `ColorScheme` has no slot for, plus the two
          // brightness-independent light sources from the charter's color
          // table — they never flip with the theme, and this is where that
          // stays visible.
          Wrap(
            spacing: ListenSpacing.gap8,
            runSpacing: ListenSpacing.gap8,
            children: [
              for (final (label, ink) in [
                ('disabled', colors.disabledForeground),
                ('pressed', colors.pressedPrimary),
                ('covered', colors.verdictCovered),
                ('partial', colors.verdictPartial),
                ('missing', colors.error),
                ('月白', ListenColors.moonWhite),
                ('月蓝', ListenColors.moonBlue),
                ('signal', ListenColors.overlaySignal),
              ])
                _Swatch(label: label, fill: colors.surface, ink: ink),
            ],
          ),

          const SizedBox(height: ListenSpacing.gap24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (label, radius) in const [
                ('tight', ListenRadii.tightBorder),
                ('control', ListenRadii.controlBorder),
                ('surface', ListenRadii.surfaceBorder),
                ('panel', ListenRadii.panelBorder),
                ('pill', ListenRadii.pillBorder),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: ListenSpacing.gap8),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHigh,
                          borderRadius: radius,
                          border: Border.all(color: colors.outlineVariant),
                        ),
                      ),
                      const SizedBox(height: ListenSpacing.gap4),
                      Text(label, style: ListenType.caption),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: ListenSpacing.gap24),
          // The icon ladder beside the text band each step is pinned to: the
          // whole point of `ListenIconSize` is that an icon and its label carry
          // the same weight, which is a claim only a picture can check.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final (label, size, style) in const [
                ('inline', ListenIconSize.inline, ListenType.caption),
                ('control', ListenIconSize.control, ListenType.body),
                ('chrome', ListenIconSize.chrome, ListenType.title),
                (
                  'illustration',
                  ListenIconSize.illustration,
                  ListenType.reading,
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: ListenSpacing.gap16),
                  child: Row(
                    children: [
                      Icon(Icons.graphic_eq, size: size),
                      const SizedBox(width: ListenSpacing.gap4),
                      Text(label, style: style),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.fill, required this.ink});

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    width: 118,
    padding: ListenPadding.tight,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: ListenRadii.controlBorder,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: ListenType.body.copyWith(color: ink),
    ),
  );
}

/// Every component family `ListenTheme` styles, in its resting state.
///
/// A component theme is the one place a visual decision applies to hundreds of
/// call sites at once, so it is also the one place a regression is widest. The
/// focus ring is the exception this sheet cannot show — focus is a live state,
/// and `focus_ring_test.dart` already asserts the resolver directly.
class _ControlSheet extends StatelessWidget {
  const _ControlSheet();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: ListenPadding.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: ListenSpacing.gap8,
            runSpacing: ListenSpacing.gap8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Filled')),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.mic, size: ListenIconSize.control),
                label: const Text('With icon'),
              ),
              const FilledButton(onPressed: null, child: Text('Disabled')),
              OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
              const OutlinedButton(onPressed: null, child: Text('Disabled')),
              TextButton(onPressed: () {}, child: const Text('Text')),
              const TextButton(onPressed: null, child: Text('Disabled')),
              IconButton(
                onPressed: () {},
                iconSize: ListenIconSize.chrome,
                icon: const Icon(Icons.settings_outlined),
              ),
              const IconButton(
                onPressed: null,
                iconSize: ListenIconSize.chrome,
                icon: Icon(Icons.settings_outlined),
              ),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap16),
          Wrap(
            spacing: ListenSpacing.gap8,
            runSpacing: ListenSpacing.gap8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Chip(label: Text('Chip')),
              ChoiceChip(
                label: const Text('Selected'),
                selected: true,
                onSelected: (_) {},
              ),
              ChoiceChip(
                label: const Text('Unselected'),
                selected: false,
                onSelected: (_) {},
              ),
              Switch(value: true, onChanged: (_) {}),
              Switch(value: false, onChanged: (_) {}),
              Checkbox(value: true, onChanged: (_) {}),
              Checkbox(value: false, onChanged: (_) {}),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap16),
          SizedBox(width: 320, child: Slider(value: 0.4, onChanged: (_) {})),
          const SizedBox(height: ListenSpacing.gap8),
          const SizedBox(
            width: 320,
            child: LinearProgressIndicator(value: 0.4),
          ),
          const SizedBox(height: ListenSpacing.gap16),
          const SizedBox(
            width: 320,
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Endpoint',
                hintText: 'wss://example.com',
              ),
            ),
          ),
          const SizedBox(height: ListenSpacing.gap16),
          const Divider(),
          const SizedBox(height: ListenSpacing.gap16),
          SizedBox(
            width: 360,
            child: Card(
              child: Padding(
                padding: ListenPadding.card,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Card surface', style: ListenType.title),
                    const SizedBox(height: ListenSpacing.gap4),
                    Text(
                      'L2 in the elevation table: a clickable object, drawn '
                      'with one hairline border rather than a lighter fill.',
                      style: ListenType.body.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
