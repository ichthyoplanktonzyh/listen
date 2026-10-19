import 'package:flutter/material.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/theme/typography.dart';
import 'package:llplayer_next/widgets/common/listen_empty_state.dart';
import 'package:llplayer_next/widgets/common/listen_error_state.dart';
import 'package:llplayer_next/widgets/common/listen_loading.dart';
import 'package:llplayer_next/widgets/listen_wordmark.dart';

import 'support/golden.dart';

/// Baselines for the shared state language (#46) and the wordmark (#28/#32).
///
/// These four widgets are the app's most-reused visible vocabulary: almost
/// every panel eventually shows one of them, and none of them belongs to a
/// screen a parallel slice is rebuilding. They are also where a regression is
/// least likely to be noticed by hand — nobody opens an app to look at its
/// empty states.
///
/// The waiting mark is the one that most needs a picture. `ListenLoading`
/// deliberately is not a spinner; it is the wordmark breathing, and the
/// difference between "breathing mark" and "mark that failed to draw" is
/// invisible to `loading_discipline_test.dart`, which can only see that no
/// `CircularProgressIndicator` was used. Under the harness's reduce-motion
/// frame the breath is held at full presence, so what is pinned here is the
/// mark itself.
void main() {
  goldenScene(
    'wordmark',
    size: GoldenSurface.component,
    builder: (context) => const _WordmarkSheet(),
  );

  goldenScene(
    'state_empty',
    size: GoldenSurface.component,
    builder: (context) => Row(
      children: [
        const Expanded(
          child: ListenEmptyState(
            icon: Icons.inbox_outlined,
            message: 'Nothing captured from this media yet',
          ),
        ),
        Expanded(
          child: ListenEmptyState(
            icon: Icons.folder_open_outlined,
            message: 'No media open',
            action: OutlinedButton(
              onPressed: () {},
              child: const Text('Open media'),
            ),
          ),
        ),
      ],
    ),
  );

  goldenScene(
    'state_error',
    size: GoldenSurface.component,
    builder: (context) => Column(
      children: [
        Expanded(
          child: ListenErrorState(
            message: 'This panel could not load',
            action: OutlinedButton(
              onPressed: () {},
              child: const Text('Try again'),
            ),
          ),
        ),
        const Padding(
          padding: ListenPadding.card,
          child: ListenErrorNotice(
            message: 'This turn could not be transcribed',
          ),
        ),
      ],
    ),
  );

  goldenScene(
    'state_loading',
    size: GoldenSurface.component,
    builder: (context) => Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const ListenLoading(label: 'Reading the timeline'),
          const ListenLoading(),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const ListenLoading.inline(size: ListenIconSize.control),
            label: const Text('Importing'),
          ),
        ],
      ),
    ),
  );
}

/// The lockup at the sizes it actually ships at, plus the bare mark the
/// waiting state reuses.
///
/// The mark's two halves are brand constants rather than theme roles — the
/// bright/dark relationship *is* the meaning — so the same drawing has to come
/// out of both baselines unchanged while only the wordmark text follows
/// `onSurface`. That is a claim about two images at once, which is why it is
/// worth a picture.
class _WordmarkSheet extends StatelessWidget {
  const _WordmarkSheet();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: ListenSpacing.gap24,
      children: [
        const ListenWordmark(size: 40),
        const ListenWordmark(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: ListenSpacing.gap16,
          children: [
            for (final size in const [
              ListenIconSize.inline,
              ListenIconSize.control,
              ListenIconSize.chrome,
              ListenIconSize.illustration,
            ])
              ListenWordmark(size: size, withText: false),
          ],
        ),
        Text(
          'mark colors are brand constants, not theme roles',
          style: ListenType.caption,
        ),
      ],
    ),
  );
}
