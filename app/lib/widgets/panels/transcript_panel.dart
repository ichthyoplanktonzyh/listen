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
    required this.showStyles,
    required this.baseColor,
    required this.onWord,
    required this.onSeekCue,
  });

  final SubtitleTrack? track;
  final ScrollController scrollController;
  final Cue? currentCue;
  final Map<String, LexicalEntry> wordEntries;
  final bool showStyles;
  final Color baseColor;
  final Future<void> Function(SubtitleToken token, Cue cue) onWord;
  final Future<void> Function(Cue? cue) onSeekCue;

  @override
  State<TranscriptPanel> createState() => _TranscriptPanelState();
}

class _TranscriptPanelState extends State<TranscriptPanel> {
  final Map<String, GlobalKey> _cueKeys = {};
  bool _syncScheduled = false;

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
      child: Column(
        children: [
          Expanded(
            child: widget.track == null
                ? Center(child: Text(l.text('importSubtitleHint')))
                : ListView.builder(
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
                          selectedTileColor: colors.primaryContainer.withValues(
                            alpha: 0.5,
                          ),
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
                            showStyles: widget.showStyles,
                            baseColor: effectiveBaseColor,
                            onWord: widget.onWord,
                          ),
                          onTap: () => widget.onSeekCue(cue),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  GlobalKey _keyFor(Cue cue) => _cueKeys.putIfAbsent(cue.id, () => GlobalKey());

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
