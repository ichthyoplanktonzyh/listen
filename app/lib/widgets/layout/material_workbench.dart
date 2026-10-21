import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/workbench_study_mode.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../utils/media_title.dart';
import '../common/content_settle.dart';

/// The single learning surface for every adopted material.
///
/// Documents and audio use the same surface with [videoPane] null; video
/// materials provide a pane only when Core reports a real video rendition.
/// The learning panel, transport and source/document states are injected by
/// the owning session, so there is no product-level document workbench.
class MaterialWorkbench extends StatefulWidget {
  static const defaultMediaFraction = 0.42;

  const MaterialWorkbench({
    super.key,
    required this.materialTitle,
    required this.videoPane,
    required this.learningPanel,
    required this.mediaFraction,
    required this.onMediaFractionChanged,
    this.onCollapse,
    this.studyMode = WorkbenchStudyMode.normal,
    this.subtitleMenu,
    this.studyMenu,
    this.translationMenu,
    this.listeningMenu,
    this.learningEditionAction,
    this.onOpenSettings,
    this.retentionMenu,
  });

  final String materialTitle;

  /// The only visual-stream input. Null means this material has no video
  /// stream and therefore must not render an empty media pane or splitter.
  final Widget? videoPane;
  final Widget learningPanel;
  final double mediaFraction;
  final ValueChanged<double> onMediaFractionChanged;
  final VoidCallback? onCollapse;

  /// The selected listening display, used to animate transcript changes.
  final WorkbenchStudyMode studyMode;

  /// Actions on this media, shown at the end of the session header. Null on
  /// surfaces that have none wired.
  final Widget? subtitleMenu;

  /// Listening display and direct listening exercises.
  final Widget? studyMenu;

  /// Switches the transcript between original, bilingual and translation.
  final Widget? translationMenu;

  /// The extensive-listening session for this sitting.
  final Widget? listeningMenu;

  /// Opens the immutable package and eight-resource status for this Material.
  /// This is material-scoped, so it lives on the workbench rather than in a
  /// global tools menu.
  final Widget? learningEditionAction;

  /// Opens app settings.
  ///
  /// The rail's own settings entry is unreachable while this workbench is up —
  /// the workbench is a full-bleed sibling of the rail, so it covers it — which
  /// left the native macOS menu as the only way in and nothing at all on
  /// Windows. It belongs on the surface that is actually on screen.
  final VoidCallback? onOpenSettings;

  /// The retention affordance (Keep / reference in place / unretain) for the
  /// current media. Null on surfaces that have none wired.
  final Widget? retentionMenu;

  @override
  State<MaterialWorkbench> createState() => _MaterialWorkbenchState();
}

class _MaterialWorkbenchState extends State<MaterialWorkbench> {
  static const splitterWidth = 9.0;
  late double _mediaFraction;

  @override
  void initState() {
    super.initState();
    _mediaFraction = _normalizedFraction(widget.mediaFraction);
  }

  @override
  void didUpdateWidget(MaterialWorkbench oldWidget) {
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
  Widget build(BuildContext context) {
    final videoPane = widget.videoPane;
    return Material(
      // The workbench is a full-bleed layer stacked over the shell, not a page
      // in a route — nothing behind it is supposed to be visible. Without its
      // own opaque ground the rail and whichever page is underneath show
      // straight through the body.
      //
      // The workbench is a full-bleed layer stacked over the shell; content
      // behind it should not show through.
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _SessionHeader(
            materialTitle: widget.materialTitle,
            onCollapse: widget.onCollapse,
            subtitleMenu: widget.subtitleMenu,
            studyMenu: widget.studyMenu,
            translationMenu: widget.translationMenu,
            listeningMenu: widget.listeningMenu,
            learningEditionAction: widget.learningEditionAction,
            onOpenSettings: widget.onOpenSettings,
            retentionMenu: widget.retentionMenu,
          ),
          Expanded(
            child: videoPane == null
                ? ContentSettle(
                    settleKey: widget.studyMode,
                    child: widget.learningPanel,
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
                                materialTitle: widget.materialTitle,
                                playerStage: videoPane,
                              ),
                            ),
                            _WorkbenchSplitter.horizontal(
                              onReset: () => _setMediaFraction(
                                MaterialWorkbench.defaultMediaFraction,
                              ),
                              onDrag: (delta) {
                                _setMediaFraction(
                                  (_mediaFraction + delta / availableHeight)
                                      .clamp(minimumFraction, maximumFraction),
                                );
                              },
                            ),
                            Expanded(
                              child: ContentSettle(
                                settleKey: widget.studyMode,
                                child: widget.learningPanel,
                              ),
                            ),
                          ],
                        );
                      }

                      final availableWidth =
                          constraints.maxWidth - splitterWidth;
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
                              materialTitle: widget.materialTitle,
                              playerStage: videoPane,
                            ),
                          ),
                          _WorkbenchSplitter(
                            onReset: () => _setMediaFraction(
                              MaterialWorkbench.defaultMediaFraction,
                            ),
                            onDrag: (delta) {
                              _setMediaFraction(
                                (_mediaFraction + delta / availableWidth).clamp(
                                  minimumFraction,
                                  maximumFraction,
                                ),
                              );
                            },
                          ),
                          Expanded(
                            child: ContentSettle(
                              settleKey: widget.studyMode,
                              child: widget.learningPanel,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.materialTitle,
    required this.onCollapse,
    required this.subtitleMenu,
    required this.studyMenu,
    required this.translationMenu,
    required this.listeningMenu,
    required this.learningEditionAction,
    required this.onOpenSettings,
    required this.retentionMenu,
  });

  final String materialTitle;
  final VoidCallback? onCollapse;
  final Widget? subtitleMenu;
  final Widget? studyMenu;
  final Widget? translationMenu;
  final Widget? listeningMenu;
  final Widget? learningEditionAction;
  final VoidCallback? onOpenSettings;
  final Widget? retentionMenu;

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
                key: const Key('workbench-close'),
                tooltip: l.text('backToHome'),
                onPressed: onCollapse,
                icon: const Icon(Icons.arrow_back),
              ),
            Expanded(child: _Breadcrumb(materialTitle: materialTitle)),
            ?learningEditionAction,
            ?listeningMenu,
            if (translationMenu != null) ...[_gap, translationMenu!],
            if (studyMenu != null) ...[_gap, studyMenu!],
            if (subtitleMenu != null) ...[_gap, subtitleMenu!],
            if (retentionMenu != null) ...[_gap, retentionMenu!],
            _gap,
            IconButton(
              key: const Key('workbench-export'),
              tooltip: l.text('workbenchExportUnavailable'),
              onPressed: null,
              iconSize: ListenIconSize.chrome,
              color: colors.onSurfaceVariant,
              icon: const Icon(Icons.download_outlined),
            ),
            IconButton(
              key: const Key('workbench-share'),
              tooltip: l.text('workbenchShareUnavailable'),
              onPressed: null,
              iconSize: ListenIconSize.chrome,
              color: colors.onSurfaceVariant,
              icon: const Icon(Icons.ios_share_outlined),
            ),
            if (onOpenSettings != null)
              IconButton(
                key: const Key('workbench-settings'),
                tooltip: l.text('settings'),
                onPressed: onOpenSettings,
                iconSize: ListenIconSize.chrome,
                color: colors.onSurfaceVariant,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
      ),
    );
  }

  static const _gap = SizedBox(width: ListenSpacing.gap8);
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.materialTitle});

  final String materialTitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l = AppLocalizations.of(context);
    final quiet = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.text('sidebarLibrary'), style: quiet),
        Icon(
          Icons.chevron_right,
          size: ListenIconSize.control,
          color: colors.onSurfaceVariant,
        ),
        Flexible(
          child: Tooltip(
            message: materialTitle,
            child: Text(
              displayMediaTitle(materialTitle),
              key: const Key('workbench-breadcrumb-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The drag handle between the two panes.
///
/// Double-clicking it restores the default split. That is where the two
/// layout buttons went: resetting a split is an action on the splitter, and
/// putting it on the splitter costs no permanent chrome in the media pane.
class _WorkbenchSplitter extends StatelessWidget {
  const _WorkbenchSplitter({required this.onDrag, required this.onReset})
    : _vertical = false;
  const _WorkbenchSplitter.horizontal({
    required this.onDrag,
    required this.onReset,
  }) : _vertical = true;

  final ValueChanged<double> onDrag;
  final VoidCallback onReset;
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
          onDoubleTap: onReset,
          onHorizontalDragUpdate: _vertical
              ? null
              : (details) => onDrag(details.delta.dx),
          onVerticalDragUpdate: _vertical
              ? (details) => onDrag(details.delta.dy)
              : null,
          child: _vertical
              ? SizedBox(
                  height: _MaterialWorkbenchState.splitterWidth,
                  child: Center(child: SizedBox(height: 1, child: divider)),
                )
              : SizedBox(
                  width: _MaterialWorkbenchState.splitterWidth,
                  child: Center(child: SizedBox(width: 1, child: divider)),
                ),
        ),
      ),
    );
  }
}

/// The media half of the workbench: what this is, and the picture.
///
/// It used to open with a 56px toolbar holding a decorative play glyph and two
/// layout buttons — none of them actions on the media — and then centre the
/// video inside a padded 16:9 box, which left a band of empty surface above
/// and below it. The title, meanwhile, was a single ellipsized line squeezed
/// into the session header between the channel pills and the menus.
///
/// So the title comes here, where there is room for it to be the heading of
/// the thing it names, and the video takes the width it is given. Resetting
/// the split moved to a double-click on the splitter: that is the thing being
/// reset, and it costs no permanent chrome.
class _MediaPane extends StatelessWidget {
  const _MediaPane({required this.materialTitle, required this.playerStage});

  final String materialTitle;
  final Widget playerStage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: ListenPadding.card,
            // The heading reads the title, not the download artefact (§3.7):
            // extension, provider id and trailing date are stripped for
            // display. The raw file name stays one hover away, so nothing is
            // hidden — a learner who needs the exact file still has it.
            child: Tooltip(
              message: materialTitle,
              child: Text(
                displayMediaTitle(materialTitle),
                key: const Key('workbench-media-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: ListenSpacing.gap16,
              ),
              // Top-aligned rather than centred: the picture belongs under its
              // heading, and on an audio file the leftover space collects at
              // the bottom instead of framing an empty box.
              child: Align(
                alignment: Alignment.topCenter,
                child: AspectRatio(aspectRatio: 16 / 9, child: playerStage),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
