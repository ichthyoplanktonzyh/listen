import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../utils/format_duration.dart';
import '../subtitle/token_line.dart';

class TranscriptPanel extends StatefulWidget {
  const TranscriptPanel({
    super.key,
    required this.track,
    required this.scrollController,
    required this.currentCue,
    required this.wordEntries,
    this.capabilityProfiles = const {},
    required this.showStyles,
    required this.baseColor,
    required this.onWord,
    required this.onSeekCue,
    this.onImportSubtitle,
    this.groupingMode = 'off',
    this.chunkPartitionsBySentence = const {},
    this.senseGroupsBySentence = const {},
    this.chunkDisplayStyle = 'capsule',
  });

  final SubtitleTrack? track;
  final ScrollController scrollController;
  final Cue? currentCue;
  final Map<String, LexicalEntry> wordEntries;
  final Map<String, LexicalCapabilityProfile> capabilityProfiles;
  final bool showStyles;
  final Color baseColor;
  final String groupingMode;
  final Map<String, SentenceChunkPartition> chunkPartitionsBySentence;
  final Map<String, List<SenseGroup>> senseGroupsBySentence;
  final String chunkDisplayStyle;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(Cue? cue) onSeekCue;
  final Future<void> Function()? onImportSubtitle;

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final Map<String, GlobalKey> _cueKeys = {};
  bool _syncScheduled = false;
  // While true the current cue is kept in view automatically. A manual scroll
  // (drag or wheel) pauses following so the user can read elsewhere without
  // being yanked back; programmatic scrolls never trip this.
  bool _following = true;

  @override
  void initState() {
    super.initState();
    _scheduleCurrentCueSync();
  }

  @override
  void didUpdateWidget(covariant TranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track?.id != widget.track?.id) {
      _cueKeys.clear();
      // A new transcript resumes automatic following from the top.
      _following = true;
    }
    if (oldWidget.currentCue?.id != widget.currentCue?.id ||
        oldWidget.track?.id != widget.track?.id) {
      _scheduleCurrentCueSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final effectiveBaseColor = widget.baseColor.computeLuminance() > 0.75
        ? colors.onSurface
        : widget.baseColor;
    return Material(
      color: colors.surfaceContainerLowest,
      child: widget.track == null
          ? _TranscriptEmptyState(onImportSubtitle: widget.onImportSubtitle)
          : NotificationListener<ScrollNotification>(
              // A real user drag carries dragDetails; programmatic scrolls do
              // not, so this pauses following only on genuine interaction.
              onNotification: (notification) {
                if (notification is ScrollStartNotification &&
                    notification.dragDetails != null) {
                  _pauseFollowing();
                }
                return false;
              },
              child: Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) _pauseFollowing();
                },
                // A column, not a stack: the resume-following control is a
                // strip attached under the list instead of a pill floating on
                // top of it. The floating form covered the very sentence the
                // reader had scrolled to (§3.7 / charter P2 — chrome does not
                // sit on content), and it covered a different sentence at
                // every window height.
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: widget.scrollController,
                        padding: const EdgeInsets.symmetric(
                          vertical: ListenSpacing.gap8,
                        ),
                        itemCount: widget.track!.cues.length,
                        itemBuilder: (context, index) {
                          final cue = widget.track!.cues[index];
                          final selected = cue.id == widget.currentCue?.id;
                          return KeyedSubtree(
                            key: _keyFor(cue),
                            child: ListTile(
                              key: ValueKey('transcript-cue-${cue.id}'),
                              selected: selected,
                              selectedTileColor: colors.primaryContainer
                                  .withValues(alpha: 0.5),
                              contentPadding: ListenPadding.row,
                              leading: SizedBox(
                                width: 58,
                                child: Text(
                                  formatDuration(cue.start),
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ),
                              title: TokenLine(
                                cue: cue,
                                profiles: widget.wordEntries,
                                capabilityProfiles: widget.capabilityProfiles,
                                showStyles: widget.showStyles,
                                baseColor: effectiveBaseColor,
                                onWord: widget.onWord,
                                groupingMode: widget.groupingMode,
                                chunkDisplayStyle: widget.chunkDisplayStyle,
                                chunkPartition:
                                    widget.chunkPartitionsBySentence[cue.id],
                                senseGroups:
                                    widget.senseGroupsBySentence[cue.id] ??
                                    const [],
                              ),
                              onTap: () => widget.onSeekCue(cue),
                            ),
                          );
                        },
                      ),
                    ),
                    if (!_following && widget.currentCue != null)
                      _BackToCurrentBar(
                        label: l.text('backToCurrentSentence'),
                        onPressed: _resumeFollowing,
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  GlobalKey _keyFor(Cue cue) => _cueKeys.putIfAbsent(cue.id, () => GlobalKey());

  void _pauseFollowing() {
    if (_following) setState(() => _following = false);
  }

  void _resumeFollowing() {
    setState(() => _following = true);
    _scheduleCurrentCueSync();
  }

  void _scheduleCurrentCueSync({int attempt = 0}) {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _syncCurrentCue(attempt: attempt);
    });
  }

  void _syncCurrentCue({required int attempt}) {
    if (!_following) return;
    final cue = widget.currentCue;
    if (cue == null) return;

    final cueContext = _cueKeys[cue.id]?.currentContext;
    if (cueContext != null) {
      Scrollable.ensureVisible(
        cueContext,
        alignment: 0.38,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    if (attempt >= 3 || !_jumpNearCurrentCue(cue)) return;
    _scheduleCurrentCueSync(attempt: attempt + 1);
  }

  bool _jumpNearCurrentCue(Cue cue) {
    final track = widget.track;
    if (track == null || track.cues.isEmpty) return false;
    if (!widget.scrollController.hasClients) return false;

    final index = track.cues.indexWhere((value) => value.id == cue.id);
    if (index < 0) return false;

    final position = widget.scrollController.position;
    final maxScroll = position.maxScrollExtent;
    if (maxScroll <= 0) return false;

    final denominator = track.cues.length <= 1 ? 1 : track.cues.length - 1;
    final target = (maxScroll * (index / denominator)).clamp(
      position.minScrollExtent,
      maxScroll,
    );
    widget.scrollController.jumpTo(target.toDouble());
    return true;
  }
}

/// The strip that offers to resume following the current sentence.
///
/// It takes its own row at the bottom edge of the list rather than floating
/// over it: the transcript is content, and a control that hides a line of it
/// is exactly the "chrome glows over content" the charter's P2 forbids. Being
/// laid out also makes it honest about its cost — the list gets shorter while
/// the offer stands, and gets its height back the moment following resumes.
class _BackToCurrentBar extends StatelessWidget {
  const _BackToCurrentBar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      key: const Key('transcript-back-to-current'),
      color: colors.surfaceContainerLowest,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.outlineVariant)),
        ),
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: ListenPadding.row,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.vertical_align_center,
                  size: ListenIconSize.control,
                  color: colors.primary,
                ),
                const SizedBox(width: ListenSpacing.gap6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TranscriptEmptyState extends StatelessWidget {
  const _TranscriptEmptyState({required this.onImportSubtitle});

  final Future<void> Function()? onImportSubtitle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: ListenPadding.pageCompact,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.subtitles_outlined,
                size: ListenIconSize.illustration,
                color: colors.primary,
              ),
              const SizedBox(height: ListenSpacing.gap12),
              Text(
                l.text('noTranscriptTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                l.text('importSubtitleHint'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (onImportSubtitle != null) ...[
                const SizedBox(height: ListenSpacing.gap16),
                FilledButton.icon(
                  onPressed: () => onImportSubtitle!(),
                  icon: const Icon(Icons.add),
                  label: Text(l.text('importSubtitle')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
