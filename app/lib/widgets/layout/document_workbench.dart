import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/document_session_controller.dart';
import '../../localization.dart';
import '../../models/document_session.dart';
import '../../models/material_capability.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/listen_loading.dart';
import '../document/document_session_view.dart';
import 'media_workbench.dart';

/// The workbench with a text material on it.
///
/// Same workbench layer as timed media — same header, same text region, same
/// collapse — with the visual pane switched off, because a document has no
/// picture and an empty video box is not a neutral placeholder. It is not a
/// page: the app never pushes a route to read something.
///
/// A source document is input, not a learning surface. Until Gen has produced
/// an interactive timed transcript, the body is an honest preparation state;
/// the exact PDF/EPUB/Markdown/HTML/text source remains one secondary action
/// away for provenance and verification. The finished generation lands on
/// this same surface — no "open the result" step and no second material.
class DocumentWorkbench extends StatefulWidget {
  const DocumentWorkbench({
    super.key,
    required this.controller,
    required this.mediaFraction,
    required this.onMediaFractionChanged,
    this.onCollapse,
    this.onOpenSettings,
    this.listenRun,
    this.onRequestListen,
    this.onCancelListen,
    this.timedLearningPanel,
    this.learningEditionAction,
  });

  final DocumentSessionController controller;
  final double mediaFraction;
  final ValueChanged<double> onMediaFractionChanged;
  final VoidCallback? onCollapse;
  final VoidCallback? onOpenSettings;

  /// The live Listen generation run for the open material, when one exists.
  final CapabilityRunView? listenRun;

  /// Starts Listen generation for the open material. Null when no generator is
  /// wired, which hides the affordance rather than offering a dead button.
  final VoidCallback? onRequestListen;
  final VoidCallback? onCancelListen;

  /// The app's existing transcript/learning panel. Once a composition brings
  /// an exact timed text track, this replaces the raw document renderer in the
  /// same right-hand region — it is not a second workbench or a new page.
  final Widget? timedLearningPanel;

  /// The current Material's installed learning-package versions and resource
  /// status. Kept separate from the source-document toggle.
  final Widget? learningEditionAction;

  @override
  State<DocumentWorkbench> createState() => _DocumentWorkbenchState();
}

class _DocumentWorkbenchState extends State<DocumentWorkbench> {
  bool _showSource = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        final title = switch (state) {
          DocumentSessionReady(:final details) ||
          DocumentSessionChoosingAsset(
            :final details,
          ) => details.currentRevision.title,
          _ => l.text('documentTitle'),
        };
        final composition = switch (state) {
          DocumentSessionReady(:final composition) => composition,
          _ => null,
        };
        final timedPanel = !(composition?.hasInteractiveTranscript ?? false)
            ? null
            : widget.timedLearningPanel;
        final ready = state is DocumentSessionReady;
        final hasInteractiveLearningSurface = ready && timedPanel != null;
        final learningPanel = switch (state) {
          DocumentSessionReady() when _showSource => DocumentSessionView(
            controller: widget.controller,
            sourceOnly: true,
          ),
          DocumentSessionReady() when hasInteractiveLearningSurface =>
            timedPanel,
          DocumentSessionReady() => _DocumentPreparationSurface(
            run: widget.listenRun,
            onRequest: widget.onRequestListen,
            onCancel: widget.onCancelListen,
            onViewSource: () => setState(() => _showSource = true),
          ),
          _ => DocumentSessionView(controller: widget.controller),
        };
        return MediaWorkbench(
          mediaTitle: title,
          playerStage: const SizedBox.shrink(),
          learningPanel: learningPanel,
          // Once structured text exists but generated speech is still
          // missing, generation remains available in the header as a
          // supplement. Before that, the preparation surface owns the primary
          // action so it cannot be overlooked.
          listeningMenu: hasInteractiveLearningSurface
              ? _listenAction(state)
              : null,
          learningEditionAction: ready ? widget.learningEditionAction : null,
          studyMenu: ready
              ? _SourceMaterialAction(
                  showingSource: _showSource,
                  onPressed: () => setState(() => _showSource = !_showSource),
                )
              : null,
          // Membership belongs in the header, the same place a media session
          // keeps it. It used to be repeated inside the body next to a second
          // copy of the title, which is what made a document look like a page
          // stacked inside the workbench instead of the workbench's own text.
          retentionMenu: _retentionAction(state),
          mediaFraction: widget.mediaFraction,
          onMediaFractionChanged: widget.onMediaFractionChanged,
          onCollapse: widget.onCollapse,
          // No visual stream and — until a rendition is adopted — no current
          // timed sentence to shadow.
          showMediaPane: false,
          showShadowAction: false,
          onOpenSettings: widget.onOpenSettings,
        );
      },
    );
  }

  /// Keep / Unkeep for the open document, or null before one is open.
  ///
  /// A document opens as Temporary Material and only the learner's explicit
  /// Keep adds it to the Personal Library, so the state is worth stating
  /// rather than leaving to be inferred from which button is showing.
  Widget? _retentionAction(DocumentSessionState state) {
    if (state is! DocumentSessionReady) return null;
    return _DocumentRetentionAction(
      isRetained: state.isRetained,
      inFlight: state.retentionInFlight,
      onKeep: () => unawaited(widget.controller.retain()),
      onUnkeep: () => unawaited(widget.controller.unretain()),
    );
  }

  /// The Listen affordance for the open document, or null when it does not
  /// apply.
  ///
  /// Absent whenever the material can already be listened to: once a
  /// composition with derived audio is adopted, the capability exists and the
  /// workbench shows the audio instead of an invitation to generate it again.
  Widget? _listenAction(DocumentSessionState state) {
    final request = widget.onRequestListen;
    if (request == null) return null;
    if (state is! DocumentSessionReady) return null;
    if (_hasCompleteLearningResources(state)) return null;
    return _ListenCapabilityAction(
      run: widget.listenRun,
      onRequest: request,
      onCancel: widget.onCancelListen,
    );
  }

  static bool _hasCompleteLearningResources(DocumentSessionReady state) =>
      (state.composition?.hasInteractiveTranscript ?? false) &&
      state.composition?.derivedMediaPath != null;
}

/// The primary state for a document that is still only a source asset.
///
/// Directly drawing source bytes here used to make a successful import look
/// like a successful learning session even though no token could be looked up
/// and no sentence could follow playback. This state names the missing step
/// and gives generation the visual priority it has in the user journey.
class _DocumentPreparationSurface extends StatelessWidget {
  const _DocumentPreparationSurface({
    required this.run,
    required this.onRequest,
    required this.onCancel,
    required this.onViewSource,
  });

  final CapabilityRunView? run;
  final VoidCallback? onRequest;
  final VoidCallback? onCancel;
  final VoidCallback onViewSource;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final failed = run?.phase == CapabilityRunPhase.failed;
    final failureBodyKey = switch (run?.failureCode) {
      'generator_python_unavailable' =>
        'learningMaterialsPythonUnavailableBody',
      _ => 'learningMaterialsPreparationFailedBody',
    };
    return Material(
      key: const Key('document-learning-preparation'),
      color: colors.surfaceContainerLowest,
      child: Center(
        child: SingleChildScrollView(
          padding: ListenPadding.pageCompact,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: ListenBreakpoints.noticeColumnMax,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  failed ? Icons.error_outline : Icons.auto_stories_outlined,
                  size: ListenIconSize.illustration,
                  color: failed ? colors.error : colors.primary,
                ),
                const SizedBox(height: ListenSpacing.gap12),
                Text(
                  l.text(
                    failed
                        ? 'learningMaterialsPreparationFailedTitle'
                        : 'documentLearningMaterialsTitle',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                Text(
                  l.text(
                    failed ? failureBodyKey : 'documentLearningMaterialsBody',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap16),
                _ListenCapabilityAction(
                  run: run,
                  onRequest: onRequest,
                  onCancel: onCancel,
                  prominent: true,
                ),
                const SizedBox(height: ListenSpacing.gap8),
                TextButton.icon(
                  key: const Key('document-view-source'),
                  onPressed: onViewSource,
                  icon: const Icon(Icons.description_outlined),
                  label: Text(l.text('viewSourceMaterial')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceMaterialAction extends StatelessWidget {
  const _SourceMaterialAction({
    required this.showingSource,
    required this.onPressed,
  });

  final bool showingSource;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return IconButton(
      key: const Key('document-source-toggle'),
      tooltip: l.text(
        showingSource ? 'backToLearningMaterials' : 'viewSourceMaterial',
      ),
      onPressed: onPressed,
      iconSize: ListenIconSize.chrome,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      icon: Icon(
        showingSource
            ? Icons.auto_stories_outlined
            : Icons.description_outlined,
      ),
    );
  }
}

/// Request / progress + cancel / retry for the Listen generation of the open
/// document. A completed run shows nothing: the session reloads the adopted
/// composition and the workbench simply has audio.
class _ListenCapabilityAction extends StatelessWidget {
  const _ListenCapabilityAction({
    required this.run,
    required this.onRequest,
    required this.onCancel,
    this.prominent = false,
  });

  final CapabilityRunView? run;
  final VoidCallback? onRequest;
  final VoidCallback? onCancel;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final run = this.run;
    final phase = run?.phase ?? CapabilityRunPhase.idle;
    switch (phase) {
      case CapabilityRunPhase.resolving ||
          CapabilityRunPhase.generating ||
          CapabilityRunPhase.installing ||
          CapabilityRunPhase.adopting:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListenLoading.inline(),
            const SizedBox(width: ListenSpacing.gap6),
            Text(
              run?.stage ?? l.text('capabilityInProgress'),
              key: const Key('document-listen-progress'),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (onCancel != null)
              IconButton(
                key: const Key('document-listen-cancel'),
                tooltip: l.text('cancel'),
                visualDensity: VisualDensity.compact,
                onPressed: onCancel,
                icon: const Icon(Icons.close),
              ),
          ],
        );
      case CapabilityRunPhase.failed:
        final button = prominent ? FilledButton.new : TextButton.new;
        return button(
          key: const Key('document-listen-retry'),
          onPressed: onRequest,
          child: Text(l.text('retry')),
        );
      case CapabilityRunPhase.completed:
      // A completed run only disappears when the caller observes the complete
      // resources. If the adopted edition is still incomplete, offer the same
      // material-level request again instead of leaving a dead empty state.
      case CapabilityRunPhase.cancelled || CapabilityRunPhase.idle:
        final button = prominent ? FilledButton.icon : TextButton.icon;
        return button(
          key: const Key('document-listen-request'),
          onPressed: onRequest,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: Text(l.text('generateLearningMaterials')),
        );
    }
  }
}

/// Keep / Unkeep for the open document.
///
/// An icon in the header's tool strip, like every other control there: a
/// document's title already names it, and a text button wide enough to say
/// "remove from the personal library" pushes the strip off the edge of a
/// narrow window. The state it is in — Temporary or Kept — is the tooltip,
/// and it is a real difference: a Temporary document is gone when the
/// workbench closes.
class _DocumentRetentionAction extends StatelessWidget {
  const _DocumentRetentionAction({
    required this.isRetained,
    required this.inFlight,
    required this.onKeep,
    required this.onUnkeep,
  });

  final bool isRetained;
  final bool inFlight;
  final VoidCallback onKeep;
  final VoidCallback onUnkeep;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (inFlight) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
        child: ListenLoading.inline(),
      );
    }
    return IconButton(
      key: const Key('document-retention'),
      tooltip: isRetained
          ? l.text('retentionUnkeepAction')
          : l.text('retentionKeepAction'),
      onPressed: isRetained ? onUnkeep : onKeep,
      iconSize: ListenIconSize.chrome,
      color: isRetained
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
      icon: Icon(isRetained ? Icons.bookmark : Icons.bookmark_border),
    );
  }
}
