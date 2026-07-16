import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../localization.dart';
import 'word_learning_panel.dart';

/// Keeps reading as the primary scene while giving an explicitly requested
/// word a visible, dismissible home. Wide windows reserve a contextual rail;
/// narrow windows overlay it without destroying the reading position.
class ReadingContextLayout extends StatelessWidget {
  const ReadingContextLayout({
    super.key,
    required this.reader,
    required this.inspector,
    required this.inspectorOpen,
  });

  final Widget reader;
  final Widget inspector;
  final bool inspectorOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (!inspectorOpen) return reader;
      if (constraints.maxWidth >= 980) {
        return Row(
          children: [
            Expanded(child: reader),
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            SizedBox(
              key: const ValueKey('reading-word-inspector-rail'),
              width: (constraints.maxWidth * 0.34).clamp(360, 460),
              child: inspector,
            ),
          ],
        );
      }
      return Stack(
        children: [
          Positioned.fill(child: reader),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: constraints.maxWidth * 0.9,
            child: Material(
              key: const ValueKey('reading-word-inspector-overlay'),
              elevation: 12,
              child: inspector,
            ),
          ),
        ],
      );
    },
  );
}

class ReadingWordInspector extends StatelessWidget {
  const ReadingWordInspector({
    super.key,
    required this.learningController,
    required this.onClose,
    required this.onStatus,
    required this.onSave,
    required this.onSource,
    required this.onHeard,
    required this.onNotHeard,
    required this.onCapabilityOverride,
    required this.onReadingMark,
    this.onRecordSource,
    this.onOpenListeningDictionary,
    this.onPlayPronunciationAudio,
    this.hasSelectedCue = false,
  });

  final LearningController learningController;
  final VoidCallback onClose;
  final ValueChanged<String?> onStatus;
  final Future<void> Function(String?, String?) onSave;
  final ValueChanged<Map<String, dynamic>> onSource;
  final VoidCallback onHeard;
  final VoidCallback onNotHeard;
  final Future<void> Function(String capability, String? conclusion)
  onCapabilityOverride;
  final void Function(bool understood) onReadingMark;
  final VoidCallback? onRecordSource;
  final VoidCallback? onOpenListeningDictionary;
  final ValueChanged<String>? onPlayPronunciationAudio;
  final bool hasSelectedCue;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: learningController,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final colors = Theme.of(context).colorScheme;
      final details = learningController.selectedLexicalDetails;
      return Material(
        color: colors.surfaceContainerLowest,
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_outlined, color: colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        details?.entry.displayForm ??
                            learningController.selectedToken?.text ??
                            l.text('wordLearning'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('reading-word-inspector-close'),
                      tooltip: l.text('readingWordInspectorClose'),
                      onPressed: onClose,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: details == null
                  ? const Center(child: CircularProgressIndicator())
                  : WordLearningPanel(
                      details: details,
                      dictionary: learningController.selectedDictionary,
                      pronunciation: learningController.selectedPronunciation,
                      languageProfile:
                          learningController.currentLanguageProfile,
                      onStatus: onStatus,
                      onSave: onSave,
                      onSource: onSource,
                      onHeard: onHeard,
                      onNotHeard: onNotHeard,
                      onCapabilityOverride: onCapabilityOverride,
                      onRecordSource: onRecordSource,
                      onReadingMark: onReadingMark,
                      onOpenListeningDictionary: onOpenListeningDictionary,
                      onPlayPronunciationAudio: onPlayPronunciationAudio,
                      hasSelectedCue: hasSelectedCue,
                    ),
            ),
          ],
        ),
      );
    },
  );
}
