import 'package:flutter/material.dart';

class MediaWorkbench extends StatefulWidget {
  const MediaWorkbench({
    super.key,
    required this.mediaTitle,
    required this.playerStage,
    required this.learningPanel,
  });

  final String mediaTitle;
  final Widget playerStage;
  final Widget learningPanel;

  @override
  State<MediaWorkbench> createState() => _MediaWorkbenchState();
}

class _MediaWorkbenchState extends State<MediaWorkbench> {
  static const splitterWidth = 9.0;
  double _mediaFraction = 5 / 12;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 820) {
        return Column(
          children: [
            SizedBox(
              height: (constraints.maxHeight * 0.48).clamp(260.0, 460.0),
              child: _MediaPane(
                mediaTitle: widget.mediaTitle,
                playerStage: widget.playerStage,
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
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
            ),
          ),
          _WorkbenchSplitter(
            onDrag: (delta) {
              setState(() {
                _mediaFraction = (_mediaFraction + delta / availableWidth)
                    .clamp(minimumFraction, maximumFraction);
              });
            },
          ),
          Expanded(child: widget.learningPanel),
        ],
      );
    },
  );
}

class _WorkbenchSplitter extends StatelessWidget {
  const _WorkbenchSplitter({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Resize media and transcript',
    child: MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('media-workbench-splitter'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: SizedBox(
          width: _MediaWorkbenchState.splitterWidth,
          child: Center(
            child: Container(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    ),
  );
}

class _MediaPane extends StatelessWidget {
  const _MediaPane({required this.mediaTitle, required this.playerStage});

  final String mediaTitle;
  final Widget playerStage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
                ],
              ),
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
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
