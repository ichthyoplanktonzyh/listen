import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/content_channel.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../utils/media_title.dart';
import '../common/content_settle.dart';
import 'content_channel_switcher.dart';

class MediaWorkbench extends StatefulWidget {
  const MediaWorkbench({
    super.key,
    required this.mediaTitle,
    required this.playerStage,
    required this.learningPanel,
    required this.mediaFraction,
    required this.onMediaFractionChanged,
    this.onCollapse,
    this.selectedChannel = ContentChannel.listening,
    this.channelAvailability = const {},
    this.onChannelSelected,
    this.immersiveStage,
  });

  final String mediaTitle;
  final Widget playerStage;
  final Widget learningPanel;
  final double mediaFraction;
  final ValueChanged<double> onMediaFractionChanged;
  final VoidCallback? onCollapse;
  final ContentChannel selectedChannel;
  final Map<ContentChannel, ContentChannelAvailability> channelAvailability;
  final ValueChanged<ContentChannel>? onChannelSelected;

  /// A channel-native surface that owns the workbench body. Reading and task
  /// scenes use this instead of pretending to be the media pane of a split.
  final Widget? immersiveStage;

  @override
  State<MediaWorkbench> createState() => _MediaWorkbenchState();
}

class _MediaWorkbenchState extends State<MediaWorkbench> {
  static const splitterWidth = 9.0;
  static const defaultMediaFraction = 0.42;
  static const compactMediaFraction = 0.32;
  late double _mediaFraction;

  @override
  void initState() {
    super.initState();
    _mediaFraction = _normalizedFraction(widget.mediaFraction);
  }

  @override
  void didUpdateWidget(MediaWorkbench oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaFraction != oldWidget.mediaFraction &&
        (widget.mediaFraction - _mediaFraction).abs() > 0.005) {
      _mediaFraction = _normalizedFraction(widget.mediaFraction);
    }
  }

  double _normalizedFraction(double value) => value.clamp(0.3, 0.62).toDouble();

  void _setMediaFraction(double value) {
    final next = _normalizedFraction(value);
    setState(() => _mediaFraction = next);
    widget.onMediaFractionChanged(next);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SessionHeader(
        mediaTitle: widget.mediaTitle,
        selectedChannel: widget.selectedChannel,
        availability: widget.channelAvailability,
        onSelected: widget.onChannelSelected,
        onCollapse: widget.onCollapse,
      ),
      Expanded(
        // Channel surfaces settle in (#46): switching channels fades the new
        // surface in with an 8px rise instead of hard-cutting.
        child: widget.immersiveStage != null
            ? ContentSettle(
                settleKey: widget.selectedChannel,
                child: widget.immersiveStage!,
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth <
                      ListenBreakpoints.workbenchStacked) {
                    final availableHeight =
                        constraints.maxHeight - splitterWidth;
                    final minimumFraction = (240 / availableHeight).clamp(
                      0.28,
                      0.7,
                    );
                    final maximumFraction =
                        ((availableHeight - 260) / availableHeight).clamp(
                          minimumFraction,
                          0.72,
                        );
                    final effectiveFraction = _mediaFraction.clamp(
                      minimumFraction,
                      maximumFraction,
                    );
                    return Column(
                      children: [
                        SizedBox(
                          height: availableHeight * effectiveFraction,
                          child: _MediaPane(
                            playerStage: widget.playerStage,
                            onCompactMedia: () =>
                                _setMediaFraction(compactMediaFraction),
                            onResetLayout: () =>
                                _setMediaFraction(defaultMediaFraction),
                            onCollapse: widget.onCollapse,
                          ),
                        ),
                        _WorkbenchSplitter.horizontal(
                          onDrag: (delta) {
                            _setMediaFraction(
                              (_mediaFraction + delta / availableHeight).clamp(
                                minimumFraction,
                                maximumFraction,
                              ),
                            );
                          },
                        ),
                        Expanded(
                          child: ContentSettle(
                            settleKey: widget.selectedChannel,
                            child: widget.learningPanel,
                          ),
                        ),
                      ],
                    );
                  }

                  final availableWidth = constraints.maxWidth - splitterWidth;
                  final minimumFraction = (320 / availableWidth).clamp(
                    0.28,
                    0.7,
                  );
                  final maximumFraction =
                      ((availableWidth - 420) / availableWidth).clamp(
                        minimumFraction,
                        0.7,
                      );
                  final effectiveFraction = _mediaFraction.clamp(
                    minimumFraction,
                    maximumFraction,
                  );
                  return Row(
                    children: [
                      SizedBox(
                        width: availableWidth * effectiveFraction,
                        child: _MediaPane(
                          playerStage: widget.playerStage,
                          onCompactMedia: () =>
                              _setMediaFraction(compactMediaFraction),
                          onResetLayout: () =>
                              _setMediaFraction(defaultMediaFraction),
                          onCollapse: widget.onCollapse,
                        ),
                      ),
                      _WorkbenchSplitter(
                        onDrag: (delta) {
                          _setMediaFraction(
                            (_mediaFraction + delta / availableWidth).clamp(
                              minimumFraction,
                              maximumFraction,
                            ),
                          );
                        },
                      ),
                      Expanded(child: widget.learningPanel),
                    ],
                  );
                },
              ),
      ),
    ],
  );
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.mediaTitle,
    required this.selectedChannel,
    required this.availability,
    required this.onSelected,
    required this.onCollapse,
  });

  final String mediaTitle;
  final ContentChannel selectedChannel;
  final Map<ContentChannel, ContentChannelAvailability> availability;
  final ValueChanged<ContentChannel>? onSelected;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: ListenPadding.row,
        child: Row(
          children: [
            if (onCollapse != null)
              IconButton(
                tooltip: l.text('backToHome'),
                onPressed: onCollapse,
                icon: const Icon(Icons.home_outlined),
              ),
            Flexible(
              // The header reads the title, not the download artefact (§3.7):
              // extension, provider id and trailing date are stripped for
              // display. The raw file name stays one hover away, so nothing is
              // hidden — a learner who needs the exact file still has it.
              child: Tooltip(
                message: mediaTitle,
                child: Text(
                  displayMediaTitle(mediaTitle),
                  key: const Key('workbench-media-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: ListenSpacing.gap16),
            ContentChannelSwitcher(
              selected: selectedChannel,
              availability: availability,
              onSelected: onSelected ?? (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchSplitter extends StatelessWidget {
  const _WorkbenchSplitter({required this.onDrag}) : _vertical = false;
  const _WorkbenchSplitter.horizontal({required this.onDrag})
    : _vertical = true;

  final ValueChanged<double> onDrag;
  final bool _vertical;

  @override
  Widget build(BuildContext context) {
    final divider = Container(
      color: Theme.of(context).colorScheme.outlineVariant,
    );
    return Semantics(
      label: 'Resize media and transcript',
      child: MouseRegion(
        cursor: _vertical
            ? SystemMouseCursors.resizeRow
            : SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: const Key('media-workbench-splitter'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _vertical
              ? null
              : (details) => onDrag(details.delta.dx),
          onVerticalDragUpdate: _vertical
              ? (details) => onDrag(details.delta.dy)
              : null,
          child: _vertical
              ? SizedBox(
                  height: _MediaWorkbenchState.splitterWidth,
                  child: Center(child: SizedBox(height: 1, child: divider)),
                )
              : SizedBox(
                  width: _MediaWorkbenchState.splitterWidth,
                  child: Center(child: SizedBox(width: 1, child: divider)),
                ),
        ),
      ),
    );
  }
}

class _MediaPane extends StatelessWidget {
  const _MediaPane({
    required this.playerStage,
    required this.onCompactMedia,
    required this.onResetLayout,
    this.onCollapse,
  });

  final Widget playerStage;
  final VoidCallback? onCompactMedia;
  final VoidCallback? onResetLayout;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ListenSpacing.gap16,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    size: ListenIconSize.control,
                    color: colors.primary,
                  ),
                  const Spacer(),
                  if (onCompactMedia != null)
                    IconButton(
                      tooltip: l.text('compactMediaPane'),
                      onPressed: onCompactMedia,
                      icon: const Icon(Icons.compress),
                    ),
                  if (onResetLayout != null)
                    IconButton(
                      tooltip: l.text('resetWorkbenchLayout'),
                      onPressed: onResetLayout,
                      icon: const Icon(Icons.restart_alt),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: AspectRatio(aspectRatio: 16 / 9, child: playerStage),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
