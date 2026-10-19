import 'package:flutter/material.dart';

import '../../controllers/discovery_view_model.dart';
import '../../localization.dart';
import '../../screens/discovery_home_screen.dart';
import '../../theme/spacing.dart';
import 'today_pane.dart';

/// The application landing page: resume the current learning context, then
/// discover the next material. Operational counters and system health belong
/// to their own destinations, not in the learner's opening decision space.
class HomePane extends StatelessWidget {
  const HomePane({
    super.key,
    required this.discovery,
    required this.recentMediaTitle,
    required this.recentMediaPath,
    required this.recentPosition,
    required this.recentDuration,
    required this.recentSubtitleCount,
    required this.onContinue,
    required this.onOpenMedia,
    required this.onPlayMedia,
    required this.onOpenDocument,
  });

  final DiscoveryViewModel discovery;
  final String? recentMediaTitle;
  final String? recentMediaPath;
  final Duration recentPosition;
  final Duration recentDuration;
  final int recentSubtitleCount;
  final VoidCallback onContinue;
  final VoidCallback onOpenMedia;
  final ValueChanged<String> onPlayMedia;
  final ValueChanged<String> onOpenDocument;

  bool get _hasRecentMedia =>
      (recentMediaTitle?.isNotEmpty ?? false) ||
      (recentMediaPath?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);

    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasRecentMedia)
            ColoredBox(
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  ListenSpacing.gap24,
                  ListenSpacing.gap16,
                  ListenSpacing.gap24,
                  ListenSpacing.gap16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.text('homeContinueLearning'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: ListenSpacing.gap12),
                    ContinueLearningCard(
                      mediaTitle: recentMediaTitle,
                      mediaPath: recentMediaPath,
                      position: recentPosition,
                      duration: recentDuration,
                      subtitleCount: recentSubtitleCount,
                      onContinue: onContinue,
                      onOpenMedia: onOpenMedia,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: DiscoveryHome(
              viewModel: discovery,
              onOpenMedia: onOpenMedia,
              onPlayMedia: onPlayMedia,
              onOpenDocument: onOpenDocument,
            ),
          ),
        ],
      ),
    );
  }
}
