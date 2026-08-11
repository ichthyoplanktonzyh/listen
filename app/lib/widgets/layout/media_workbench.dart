import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/content_channel.dart';
import '../../theme/icon_size.dart';
import '../../theme/breakpoints.dart';
import '../../theme/spacing.dart';
import '../../utils/media_title.dart';
import '../common/content_settle.dart';

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
    this.immersiveStage,
    this.subtitleMenu,
    this.studyMenu,
    this.translationMenu,
    this.listeningMenu,
    this.onShadow,
    this.canShadow = false,
    this.onOpenSettings,
    this.retentionMenu,
  });

  final String mediaTitle;
  final Widget playerStage;
  final Widget learningPanel;
  final double mediaFraction;
  final ValueChanged<double> onMediaFractionChanged;
  final VoidCallback? onCollapse;

  /// Which surface owns the body. Only [ContentSettle] reads it now — the
  /// switch itself moved onto [studyMenu].
  final ContentChannel selectedChannel;

  /// A channel-native surface that owns the workbench body. Reading and task
  /// scenes use this instead of pretending to be the media pane of a split.
  final Widget? immersiveStage;

  /// Actions on this media, shown at the end of the session header. Null on
  /// surfaces that have none wired.
  final Widget? subtitleMenu;

  /// Ways of working this material — reading, shadowing, the dictation modes.
  /// It sits here rather than above the transcript, where it used to be a 2×2
  /// button wall between the reader and the text.
  final Widget? studyMenu;

  /// Switches the transcript between original, bilingual and translation.
  final Widget? translationMenu;

  /// The extensive-listening session for this sitting.
  final Widget? listeningMenu;

  /// Shadows the sentence being played — the high-frequency entry the
  /// reference product keeps in the top bar, distinct from the same mode buried
  /// in [studyMenu]. Null-safe: when there is no current sentence the header
  /// still shows the control, disabled with a reason ([canShadow]).
  final VoidCallback? onShadow;

  /// Whether a sentence is currently playing to shadow. Drives whether the
  /// header's shadow control is live or shown disabled-with-reason.
  final bool canShadow;

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
  State<MediaWorkbench> createState() => _MediaWorkbenchState();
}

class _MediaWorkbenchState extends State<MediaWorkbench> {
  static const splitterWidth = 9.0;
  static const defaultMediaFraction = 0.42;
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
        onCollapse: widget.onCollapse,
        subtitleMenu: widget.subtitleMenu,
        studyMenu: widget.studyMenu,
        translationMenu: widget.translationMenu,
        listeningMenu: widget.listeningMenu,
        onShadow: widget.onShadow,
        canShadow: widget.canShadow,
        onOpenSettings: widget.onOpenSettings,
        retentionMenu: widget.retentionMenu,
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
                            mediaTitle: widget.mediaTitle,
                            playerStage: widget.playerStage,
                          ),
                        ),
                        _WorkbenchSplitter.horizontal(
                          onReset: () =>
                              _setMediaFraction(defaultMediaFraction),
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
                          mediaTitle: widget.mediaTitle,
                          playerStage: widget.playerStage,
                        ),
                      ),
                      _WorkbenchSplitter(
                        onReset: () => _setMediaFraction(defaultMediaFraction),
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
    required this.onCollapse,
    required this.subtitleMenu,
    required this.studyMenu,
    required this.translationMenu,
    required this.listeningMenu,
    required this.onShadow,
    required this.canShadow,
    required this.onOpenSettings,
    required this.retentionMenu,
  });

  /// The media on the workbench, for the breadcrumb. It reads the title, not
  /// the download artefact — same rule as the media pane heading.
  final String mediaTitle;

  final VoidCallback? onCollapse;

  /// Actions on *this* media (subtitle sourcing, archiving). They used to sit
  /// on a shell app bar, gated by `canActOnMedia` and therefore dead on every
  /// screen that had no media; here the gate is this header's own existence.
  final Widget? subtitleMenu;

  /// Ways of working this material. Like [subtitleMenu] it acts on *this*
  /// media, so it is gated by this header's own existence.
  final Widget? studyMenu;

  /// Which of the two subtitle tracks the transcript shows.
  final Widget? translationMenu;

  /// The extensive-listening session for this sitting.
  final Widget? listeningMenu;

  /// Shadows the sentence being played, [canShadow] gating it.
  final VoidCallback? onShadow;
  final bool canShadow;

  /// App settings. The rail that used to carry this is behind the workbench.
  final VoidCallback? onOpenSettings;

  /// Retention for the current media (Keep / unretain). Shown in the
  /// take-away band: moving material in or out of the Personal Library is a
  /// keep-or-release decision, the same class as the export/share chrome
  /// beside it.
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
                tooltip: l.text('backToHome'),
                onPressed: onCollapse,
                icon: const Icon(Icons.home_outlined),
              ),
            // Where the learner is. The reference top bar leads with a source
            // breadcrumb; we have no source hierarchy yet (a backend gap — see
            // workbench-backend-gaps.md), so the honest path is the library and
            // this media's title, never an invented channel name.
            Expanded(child: _Breadcrumb(mediaTitle: mediaTitle)),
            // A labelled, tooltipped tool band — not an anonymous menu cluster.
            // Order runs low-commitment to high: session, shadow, how the text
            // reads, how to work it, its subtitles, then take-away and app
            // chrome. Unwired take-away entries are shown disabled with the
            // reason, never as a clickable promise.
            ?listeningMenu,
            _gap,
            IconButton(
              key: const Key('workbench-shadow'),
              tooltip: canShadow
                  ? l.text('workbenchShadowTooltip')
                  : l.text('workbenchShadowNoCue'),
              onPressed: canShadow ? onShadow : null,
              iconSize: ListenIconSize.chrome,
              color: colors.onSurfaceVariant,
              icon: const Icon(Icons.mic_none_outlined),
            ),
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

/// The media breadcrumb: `Media library / <title>`. It reads the display title
/// (extension, provider id and trailing date stripped) and keeps the raw file
/// name a hover away, so nothing is hidden. When space runs out the title
/// ellipsizes; the library root and separator hold their width so the learner
/// never loses the sense of place.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.mediaTitle});

  final String mediaTitle;

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
        Text(l.text('mediaLibrary'), style: quiet),
        Icon(
          Icons.chevron_right,
          size: ListenIconSize.control,
          color: colors.onSurfaceVariant,
        ),
        Flexible(
          child: Tooltip(
            message: mediaTitle,
            child: Text(
              displayMediaTitle(mediaTitle),
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
          Padding(
            padding: ListenPadding.card,
            // The heading reads the title, not the download artefact (§3.7):
            // extension, provider id and trailing date are stripped for
            // display. The raw file name stays one hover away, so nothing is
            // hidden — a learner who needs the exact file still has it.
            child: Tooltip(
              message: mediaTitle,
              child: Text(
                displayMediaTitle(mediaTitle),
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
