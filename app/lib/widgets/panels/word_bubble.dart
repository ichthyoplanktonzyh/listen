import 'package:flutter/material.dart';

import '../../controllers/learning_controller.dart';
import '../../localization.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/listen_loading.dart';

/// Opens the word lookup as a bubble anchored at [anchor] (a global position,
/// normally where the reader clicked the word).
///
/// This is the replacement for the old behaviour, where tapping a word swapped
/// the whole side panel to the word tab: the transcript vanished, and coming
/// back meant finding your line again. A lookup is a glance, so it gets a
/// glance-sized surface over the text it came from, and the full entry stays
/// one click away in the session panel.
///
/// A transparent barrier dismisses it, so it costs nothing to open and nothing
/// to leave.
Future<void> showWordBubble({
  required BuildContext context,
  required Offset anchor,
  required LearningController learning,
  required ValueChanged<String?> onStatus,
  required VoidCallback onOpenDetails,
  ValueChanged<String>? onPlayPronunciationAudio,
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  builder: (context) => _AnchoredBubble(
    anchor: anchor,
    child: ListenableBuilder(
      listenable: learning,
      builder: (context, _) => WordBubble(
        details: learning.selectedLexicalDetails,
        dictionary: learning.selectedDictionary,
        pronunciation: learning.selectedPronunciation,
        onStatus: onStatus,
        onOpenDetails: () {
          Navigator.of(context).pop();
          onOpenDetails();
        },
        onPlayPronunciationAudio: onPlayPronunciationAudio,
      ),
    ),
  ),
);

/// The bubble's body: what is known about the word right now, and nothing
/// dressed up as more than that.
///
/// The lookup arrives in two steps — the entry first, the dictionary after a
/// round trip — and the bubble shows exactly which step it is on. It never
/// leaves a blank where a definition would go: waiting says it is waiting, a
/// provider that returned nothing says so, and a provider that failed says
/// that instead of silently reading as "no such word".
class WordBubble extends StatelessWidget {
  const WordBubble({
    super.key,
    required this.details,
    required this.dictionary,
    required this.pronunciation,
    required this.onStatus,
    required this.onOpenDetails,
    this.onPlayPronunciationAudio,
  });

  /// Null while the entry is still being resolved.
  final LexicalEntryDetails? details;

  /// Null while the dictionary round trip is in flight.
  final DictionaryLookupBundle? dictionary;
  final WordPronunciation? pronunciation;
  final ValueChanged<String?> onStatus;
  final VoidCallback onOpenDetails;
  final ValueChanged<String>? onPlayPronunciationAudio;

  /// Wide enough for a definition line to breathe, narrow enough that it reads
  /// as a note on the word rather than a second panel.
  static const bubbleWidth = 320.0;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final entry = details?.entry;
    return Material(
      key: const Key('word-bubble'),
      color: colors.surfaceContainerHigh,
      borderRadius: ListenRadii.surfaceBorder,
      elevation: 8,
      child: Container(
        width: bubbleWidth,
        decoration: BoxDecoration(
          borderRadius: ListenRadii.surfaceBorder,
          border: Border.all(color: colors.outlineVariant),
        ),
        padding: ListenPadding.card,
        child: entry == null
            ? Row(
                children: [
                  const ListenLoading.inline(),
                  const SizedBox(width: ListenSpacing.gap8),
                  Text(
                    l.text('wordBubbleLookingUp'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(context, l, entry),
                  const SizedBox(height: ListenSpacing.gap8),
                  _gloss(context, l),
                  const SizedBox(height: ListenSpacing.gap12),
                  _statusChoices(context, l, entry),
                  const SizedBox(height: ListenSpacing.gap8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('word-bubble-details'),
                      onPressed: onOpenDetails,
                      icon: const Icon(
                        Icons.open_in_new,
                        size: ListenIconSize.inline,
                      ),
                      label: Text(l.text('wordBubbleDetails')),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _header(BuildContext context, AppLocalizations l, LexicalEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final phonetic = _phonetic();
    final audioUrl = _audioUrl();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            entry.displayForm,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (phonetic != null) ...[
          const SizedBox(width: ListenSpacing.gap8),
          Flexible(
            child: Text(
              phonetic,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
        if (audioUrl != null && onPlayPronunciationAudio != null)
          IconButton(
            key: const Key('word-bubble-play'),
            tooltip: l.text('playPronunciation'),
            onPressed: () => onPlayPronunciationAudio!(audioUrl),
            iconSize: ListenIconSize.control,
            icon: const Icon(Icons.volume_up_outlined),
          ),
      ],
    );
  }

  /// One line of meaning, or an honest account of why there is none.
  Widget _gloss(BuildContext context, AppLocalizations l) {
    final colors = Theme.of(context).colorScheme;
    final userDefinition = details?.entry.userDefinition;
    if (userDefinition != null && userDefinition.isNotEmpty) {
      return Text(userDefinition, style: Theme.of(context).textTheme.bodyMedium);
    }
    if (dictionary == null) {
      return Row(
        children: [
          const ListenLoading.inline(size: ListenIconSize.inline),
          const SizedBox(width: ListenSpacing.gap6),
          Text(
            l.text('wordBubbleLookingUp'),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      );
    }
    for (final result in dictionary!.results) {
      final definitions =
          result.lookup?.definitions ?? const <DictionaryDefinition>[];
      if (definitions.isEmpty) continue;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            definitions.first.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: ListenSpacing.gap2),
          // Whose reading this is. A gloss with no provider is a claim with no
          // source, and the panel behind this bubble has always named one.
          Text(
            result.provider.displayName,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      );
    }
    final failed = dictionary!.results.where(
      (result) => result.error != null && result.error!.isNotEmpty,
    );
    return Text(
      failed.isEmpty
          ? l.text('wordBubbleNoDefinition')
          : l.text('wordBubbleLookupFailed'),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: failed.isEmpty ? colors.onSurfaceVariant : colors.error,
      ),
    );
  }

  Widget _statusChoices(
    BuildContext context,
    AppLocalizations l,
    LexicalEntry entry,
  ) => Wrap(
    spacing: ListenSpacing.gap6,
    runSpacing: ListenSpacing.gap6,
    children: [
      for (final value in const [
        'unknown_meaning',
        'known_not_recognized',
        'known_recognized',
      ])
        ChoiceChip(
          key: ValueKey('word-bubble-status-$value'),
          label: Text(l.status(value)),
          selected: entry.status == value,
          onSelected: (_) => onStatus(value),
        ),
    ],
  );

  String? _phonetic() {
    for (final result in _results) {
      for (final phonetic in result.lookup?.phonetics ?? _noPhonetics) {
        if (phonetic.text.isNotEmpty) return phonetic.text;
      }
    }
    return null;
  }

  String? _audioUrl() {
    for (final result in _results) {
      for (final phonetic in result.lookup?.phonetics ?? _noPhonetics) {
        final url = phonetic.audioUrl;
        if (url != null && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  List<DictionaryLookupResult> get _results =>
      dictionary?.results ?? _noResults;
}

// Typed empty fallbacks. A bare `?? const []` in a `for-in` header takes its
// element type from the loop rather than from the left operand, which silently
// makes every element `dynamic` — the same trap `word_learning_panel.dart`
// names. Spelling the element type keeps these loops typed.
const List<DictionaryLookupResult> _noResults = [];
const List<DictionaryPhonetic> _noPhonetics = [];

/// Places the bubble beside [anchor], flipping and clamping so it never leaves
/// the window — a popover that runs off the bottom edge is worse than one that
/// simply sits above the word.
class _AnchoredBubble extends StatelessWidget {
  const _AnchoredBubble({required this.anchor, required this.child});

  final Offset anchor;
  final Widget child;

  /// Vertical clearance between the clicked word and the bubble, so the word
  /// itself stays readable under it.
  static const _gap = ListenSpacing.gap12;

  @override
  Widget build(BuildContext context) => CustomSingleChildLayout(
    delegate: _AnchoredBubbleDelegate(anchor: anchor, gap: _gap),
    child: child,
  );
}

class _AnchoredBubbleDelegate extends SingleChildLayoutDelegate {
  const _AnchoredBubbleDelegate({required this.anchor, required this.gap});

  final Offset anchor;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(ListenPadding.card);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (anchor.dx - childSize.width / 2).clamp(
      ListenSpacing.gap8,
      (size.width - childSize.width - ListenSpacing.gap8).clamp(
        ListenSpacing.gap8,
        double.infinity,
      ),
    );
    final below = anchor.dy + gap;
    final top = below + childSize.height <= size.height - ListenSpacing.gap8
        ? below
        : (anchor.dy - gap - childSize.height).clamp(
            ListenSpacing.gap8,
            size.height,
          );
    return Offset(left.toDouble(), top.toDouble());
  }

  @override
  bool shouldRelayout(_AnchoredBubbleDelegate oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.gap != gap;
}
