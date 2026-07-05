import 'package:flutter/material.dart';

import '../../localization.dart';

class MediaWorkbench extends StatefulWidget {
  const MediaWorkbench({
    super.key,
    required this.mediaTitle,
    required this.playerStage,
    required this.learningPanel,
    required this.mediaFraction,
    required this.onMediaFractionChanged,
  });

  final String mediaTitle;
  final Widget playerStage;
  final Widget learningPanel;
  final double mediaFraction;
  final ValueChanged<double> onMediaFractionChanged;

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 820) {
        final availableHeight = constraints.maxHeight - splitterWidth;
        final minimumFraction = (240 / availableHeight).clamp(0.28, 0.7);
        final maximumFraction = ((availableHeight - 260) / availableHeight)
            .clamp(minimumFraction, 0.72);
        final effectiveFraction = _mediaFraction.clamp(
          minimumFraction,
          maximumFraction,
        );
        return Column(
          children: [
            SizedBox(
              height: availableHeight * effectiveFraction,
              child: _MediaPane(
                mediaTitle: widget.mediaTitle,
                playerStage: widget.playerStage,
                onCompactMedia: () => _setMediaFraction(compactMediaFraction),
                onResetLayout: () => _setMediaFraction(defaultMediaFraction),
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
            Expanded(child: widget.learningPanel),
          ],
        );
      }

      final availableWidth = constraints.maxWidth - splitterWidth;
      final minimumFraction = (320 / availableWidth).clamp(0.28, 0.7);
      final maximumFraction = ((availableWidth - 420) / availableWidth).clamp(
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
              mediaTitle: widget.mediaTitle,
              playerStage: widget.playerStage,
              onCompactMedia: () => _setMediaFraction(compactMediaFraction),
              onResetLayout: () => _setMediaFraction(defaultMediaFraction),
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
  );
}

class _WorkbenchSplitter extends StatelessWidget {
  const _WorkbenchSplitter({required this.onDrag}) : _vertical = false;
  const _WorkbenchSplitter.horizontal({required this.onDrag}) : _vertical = true;

  final ValueChanged<double> onDrag;
  final bool _vertical;

  @override
  Widget build(BuildContext context) {
    final divider = Container(color: Theme.of(context).colorScheme.outlineVariant);
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
    required this.mediaTitle,
    required this.playerStage,
    required this.onCompactMedia,
    required this.onResetLayout,
  });

  final String mediaTitle;
  final Widget playerStage;
  final VoidCallback? onCompactMedia;
  final VoidCallback? onResetLayout;

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
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    Icons.play_circle_outline,
                    size: 20,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      mediaTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
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
