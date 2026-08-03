import 'package:flutter/material.dart';

import '../../controllers/auxiliary_audio_controller.dart';
import '../../controllers/coach_dashboard_controller.dart';
import '../../controllers/hunting_controller.dart';
import '../../controllers/occurrence_media_resolver.dart';
import '../../controllers/personal_expression_view_model.dart';
import '../../controllers/review_controller.dart';
import '../../controllers/semantic_search_view_model.dart';
import '../../controllers/slice_player_controller.dart';
import '../../controllers/vocabulary_view_model.dart';
import '../../localization.dart';
import '../../models/coach_dashboard.dart';
import '../../models/personal_expression.dart';
import '../../models/practice.dart';
import '../../screens/personal_expression_screen.dart';
import '../../screens/review_queue_screen.dart';
import '../../screens/vocabulary_screen.dart';
import '../coach/coach_dashboard_screen.dart';
import '../common/listen_error_state.dart';
import 'learning_flows.dart';

/// Shell-route hosts for the learning destinations.
///
/// Vocabulary, expression, review and coach used to be pushed over the whole
/// shell as modal pages: the sidebar vanished while they were open and their
/// sidebar entries could never carry a selection state. They are shell routes
/// now; the composition root builds their route-scoped controllers, these
/// hosts own the bundle for the life of the visit and dispose it when the
/// route is left.
///
/// The bundles come from the composition root (never constructed here), so
/// this file stays inside the flows boundary and keeps repositories out of
/// presentation. While the core is disconnected the root supplies no bundle
/// and the hosts render the honest unavailable pane instead of swallowing the
/// visit — a destination is reachable even when its content is not.

/// A route-scoped controller bundle built by the composition root.
abstract interface class RouteScopedControllers {
  void dispose();
}

/// Owns a route-scoped controller bundle for one shell visit: builds it on
/// entry, rebuilds it when the core connects or disconnects (or the learning
/// language changes), and disposes it when the route is left.
abstract class ShellRouteHost<T extends RouteScopedControllers>
    extends StatefulWidget {
  const ShellRouteHost({
    super.key,
    required this.create,
    required this.language,
  });

  /// Builds the bundle while the core is connected; null while it is not.
  final T? Function()? create;

  /// The learning language the route's controllers are bound to.
  final String language;
}

abstract class ShellRouteHostState<
  W extends ShellRouteHost<T>,
  T extends RouteScopedControllers
>
    extends State<W> {
  T? _controllers;

  T? get controllers => _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = widget.create?.call();
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final connectivityChanged =
        (widget.create == null) != (oldWidget.create == null);
    final languageChanged = widget.language != oldWidget.language;
    if (!connectivityChanged && !languageChanged) return;
    final previous = _controllers;
    _controllers = widget.create?.call();
    previous?.dispose();
  }

  @override
  void dispose() {
    _controllers?.dispose();
    super.dispose();
  }
}

/// One voice for every destination the core gates (Unavailable State,
/// CONTEXT.md): the route renders the reason instead of a dead surface.
class _CoreUnavailablePane extends StatelessWidget {
  const _CoreUnavailablePane();

  @override
  Widget build(BuildContext context) {
    return ListenErrorState(
      message: AppLocalizations.of(context).text('statusConnectLocalCoreFirst'),
    );
  }
}

/// The listening dictionary as a shell route.
class VocabularyRouteControllers implements RouteScopedControllers {
  const VocabularyRouteControllers({
    required this.viewModel,
    required this.semanticSearchViewModel,
    required this.slicePlayer,
  });

  final VocabularyViewModel viewModel;
  final SemanticSearchViewModel semanticSearchViewModel;
  final SlicePlayerController slicePlayer;

  @override
  void dispose() {
    viewModel.dispose();
    semanticSearchViewModel.dispose();
    slicePlayer.dispose();
  }
}

class VocabularyRouteHost extends ShellRouteHost<VocabularyRouteControllers> {
  const VocabularyRouteHost({
    super.key,
    required super.create,
    required super.language,
    required this.onExport,
    required this.onImport,
    required this.huntingController,
    required this.auxiliaryAudio,
    required this.pauseBackgroundPlayback,
    this.onStartShadowing,
  });

  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final HuntingController huntingController;
  final AuxiliaryAudioController auxiliaryAudio;
  final Future<void> Function() pauseBackgroundPlayback;

  /// Hands a slice's audio to the practice window; the occurrence is the raw
  /// occurrence JSON (see [VocabularyScreen.onStartShadowing]).
  final VocabularyShadowingCallback? onStartShadowing;

  @override
  State<VocabularyRouteHost> createState() => _VocabularyRouteHostState();
}

class _VocabularyRouteHostState
    extends
        ShellRouteHostState<VocabularyRouteHost, VocabularyRouteControllers> {
  @override
  Widget build(BuildContext context) {
    final controllers = this.controllers;
    if (controllers == null) return const _CoreUnavailablePane();
    return VocabularyScreen(
      viewModel: controllers.viewModel,
      semanticSearchViewModel: controllers.semanticSearchViewModel,
      slicePlayer: controllers.slicePlayer,
      language: widget.language,
      onExport: widget.onExport,
      onImport: widget.onImport,
      huntingController: widget.huntingController,
      auxiliaryAudio: widget.auxiliaryAudio,
      onPauseBackgroundPlayback: widget.pauseBackgroundPlayback,
      onStartShadowing: widget.onStartShadowing,
    );
  }
}

/// The audio-first review queue as a shell route.
class ReviewRouteControllers implements RouteScopedControllers {
  const ReviewRouteControllers({
    required this.controller,
    required this.resolver,
    required this.slicePlayer,
  });

  final ReviewController controller;
  final OccurrenceMediaResolver resolver;
  final SlicePlayerController slicePlayer;

  @override
  void dispose() {
    controller.dispose();
    slicePlayer.dispose();
  }
}

class ReviewRouteHost extends ShellRouteHost<ReviewRouteControllers> {
  const ReviewRouteHost({
    super.key,
    required super.create,
    required super.language,
    required this.pauseBackgroundPlayback,
    required this.onStartShadowing,
    required this.onStartDelayedRetelling,
  });

  final Future<void> Function() pauseBackgroundPlayback;
  final Future<void> Function(ReviewQueueEntry entry) onStartShadowing;
  final Future<void> Function(ReviewQueueEntry entry) onStartDelayedRetelling;

  @override
  State<ReviewRouteHost> createState() => _ReviewRouteHostState();
}

class _ReviewRouteHostState
    extends ShellRouteHostState<ReviewRouteHost, ReviewRouteControllers> {
  @override
  Widget build(BuildContext context) {
    final controllers = this.controllers;
    if (controllers == null) return const _CoreUnavailablePane();
    return ReviewQueueScreen(
      controller: controllers.controller,
      resolver: controllers.resolver,
      slicePlayer: controllers.slicePlayer,
      onPauseBackgroundPlayback: widget.pauseBackgroundPlayback,
      onStartShadowing: widget.onStartShadowing,
      onStartDelayedRetelling: widget.onStartDelayedRetelling,
    );
  }
}

/// The learning coach dashboard as a shell route.
class CoachRouteControllers implements RouteScopedControllers {
  const CoachRouteControllers({required this.controller});

  final CoachDashboardController controller;

  @override
  void dispose() => controller.dispose();
}

class CoachRouteHost extends ShellRouteHost<CoachRouteControllers> {
  const CoachRouteHost({
    super.key,
    required super.create,
    required super.language,
    required this.onNavigate,
  });

  final Future<void> Function(
    CoachSuggestionDestination destination,
    CoachReturnContext returnContext,
  )
  onNavigate;

  @override
  State<CoachRouteHost> createState() => _CoachRouteHostState();
}

class _CoachRouteHostState
    extends ShellRouteHostState<CoachRouteHost, CoachRouteControllers> {
  @override
  Widget build(BuildContext context) {
    final controllers = this.controllers;
    if (controllers == null) return const _CoreUnavailablePane();
    return CoachDashboardScreen(
      controller: controllers.controller,
      language: widget.language,
      onNavigate: widget.onNavigate,
    );
  }
}

/// My expressions as a shell route. The detail and the writing desk stay
/// pushed routes on top: they are tasks, not destinations.
class ExpressionRouteControllers implements RouteScopedControllers {
  const ExpressionRouteControllers({required this.viewModel});

  final PersonalExpressionViewModel viewModel;

  @override
  void dispose() => viewModel.dispose();
}

class ExpressionRouteHost extends ShellRouteHost<ExpressionRouteControllers> {
  const ExpressionRouteHost({
    super.key,
    required super.create,
    required super.language,
    required this.createDetailViewModel,
    required this.onPlaySource,
    required this.onStartSpeaking,
  });

  /// Builds the detail route's view model per pattern in the composition root
  /// (the detail is a pushed task, so its model is scoped to that push).
  final PersonalExpressionDetailViewModelFactory? createDetailViewModel;
  final Future<void> Function(PersonalExpressionSourceView source)?
  onPlaySource;
  final Future<void> Function(SentencePatternAssetView pattern)?
  onStartSpeaking;

  @override
  State<ExpressionRouteHost> createState() => _ExpressionRouteHostState();
}

class _ExpressionRouteHostState
    extends
        ShellRouteHostState<ExpressionRouteHost, ExpressionRouteControllers> {
  @override
  Widget build(BuildContext context) {
    final controllers = this.controllers;
    final createDetailViewModel = widget.createDetailViewModel;
    if (controllers == null || createDetailViewModel == null) {
      return const _CoreUnavailablePane();
    }
    return PersonalExpressionScreen(
      viewModel: controllers.viewModel,
      onOpenPattern: (context, pattern) => openPersonalExpressionDetailFlow(
        context: context,
        pattern: pattern,
        createViewModel: createDetailViewModel,
        onPlaySource: widget.onPlaySource,
        onStartSpeaking: widget.onStartSpeaking,
      ),
      language: widget.language,
      onPlaySource: widget.onPlaySource,
      onStartSpeaking: widget.onStartSpeaking,
    );
  }
}
