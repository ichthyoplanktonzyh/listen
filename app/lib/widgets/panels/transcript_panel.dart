import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/timeline.dart';
import '../../models/types.dart';
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
  });

  final SubtitleTrack? track;
  final ScrollController scrollController;
  final Cue? currentCue;
  final Map<String, LexicalEntry> wordEntries;
  final Map<String, LexicalCapabilityProfile> capabilityProfiles;
  final bool showStyles;
  final Color baseColor;
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
                child: Stack(
                  children: [
                    ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            leading: SizedBox(
                              width: 58,
                              child: Text(
                                formatDuration(cue.start),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                            title: TokenLine(
                              cue: cue,
                              profiles: widget.wordEntries,
                              capabilityProfiles: widget.capabilityProfiles,
                              showStyles: widget.showStyles,
                              baseColor: effectiveBaseColor,
                              onWord: widget.onWord,
                            ),
                            onTap: () => widget.onSeekCue(cue),
                          ),
                        );
                      },
                    ),
                    if (!_following && widget.currentCue != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 14,
                        child: Center(
                          child: _BackToCurrentButton(
                            label: l.text('backToCurrentSentence'),
                            onPressed: _resumeFollowing,
                          ),
                        ),
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

class _BackToCurrentButton extends StatelessWidget {
  const _BackToCurrentButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primary,
      elevation: 3,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.vertical_align_center, size: 18, color: colors.onPrimary),
              const SizedBox(width: 7),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
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
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.subtitles_outlined, size: 34, color: colors.primary),
              const SizedBox(height: 14),
              Text(
                l.text('noTranscriptTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                l.text('importSubtitleHint'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (onImportSubtitle != null) ...[
                const SizedBox(height: 16),
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
