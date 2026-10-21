import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/auxiliary_audio_controller.dart';
import '../../controllers/coach_dashboard_controller.dart';
import '../../controllers/hunting_controller.dart';
import '../../controllers/occurrence_media_resolver.dart';
import '../../controllers/review_controller.dart';
import '../../controllers/review_deck_controller.dart';
import '../../controllers/semantic_search_view_model.dart';
import '../../controllers/slice_player_controller.dart';
import '../../controllers/vocabulary_view_model.dart';
import '../../localization.dart';
import '../../screens/review_deck_home_screen.dart';
import '../../screens/review_queue_screen.dart';
import '../../screens/vocabulary_screen.dart';
import '../common/listen_error_state.dart';
import '../coach/coach_dashboard_screen.dart';

/// Shell-route hosts for the learning destinations.
///
/// Vocabulary and review are shell routes; the composition root builds their
/// route-scoped controllers, these hosts own the bundle for the visit and
/// dispose it when the route is left.
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

/// One voice for every destination the Core gates while unavailable: the route
/// renders the reason instead of a dead surface.
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
  });

  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final HuntingController huntingController;
  final AuxiliaryAudioController auxiliaryAudio;
  final Future<void> Function() pauseBackgroundPlayback;

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
    );
  }
}

/// The review home and the audio-first card session as one shell route.
class ReviewRouteControllers implements RouteScopedControllers {
  const ReviewRouteControllers({
    required this.controller,
    required this.deckController,
    required this.resolver,
    required this.slicePlayer,
  });

  final ReviewController controller;
  final ReviewDeckController deckController;
  final OccurrenceMediaResolver resolver;
  final SlicePlayerController slicePlayer;

  @override
  void dispose() {
    controller.dispose();
    deckController.dispose();
    slicePlayer.dispose();
  }
}

class ReviewRouteHost extends ShellRouteHost<ReviewRouteControllers> {
  const ReviewRouteHost({
    super.key,
    required super.create,
    required super.language,
    required this.pauseBackgroundPlayback,
  });

  final Future<void> Function() pauseBackgroundPlayback;

  @override
  State<ReviewRouteHost> createState() => _ReviewRouteHostState();
}

class _ReviewRouteHostState
    extends ShellRouteHostState<ReviewRouteHost, ReviewRouteControllers> {
  /// The route shows the deck home; a session is pushed over it so leaving one
  /// lands back on counts that are then re-read. The session controller is
  /// shared rather than rebuilt, so an interrupted round survives the pop.
  bool _inSession = false;

  Future<void> _runSession(
    ReviewRouteControllers controllers,
    Future<bool> Function() start,
  ) async {
    // The session opens whether or not the load succeeded. A failure lives in
    // the session's own state and the session screen reports it with a retry;
    // returning early here would leave a pressed button doing nothing at all,
    // which is the one outcome that tells the learner nothing.
    await start();
    if (!mounted) return;
    setState(() => _inSession = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ReviewQueueScreen(
          controller: controllers.controller,
          resolver: controllers.resolver,
          slicePlayer: controllers.slicePlayer,
          autoLoad: false,
          onPauseBackgroundPlayback: widget.pauseBackgroundPlayback,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _inSession = false);
    // Whatever the round did, the counts on the home page moved.
    unawaited(controllers.deckController.load());
  }

  @override
  Widget build(BuildContext context) {
    final controllers = this.controllers;
    if (controllers == null) return const _CoreUnavailablePane();
    return ReviewDeckHomeScreen(
      controller: controllers.deckController,
      onStartSession: () {
        if (_inSession) return;
        unawaited(_runSession(controllers, controllers.controller.load));
      },
      onStartCustomStudy: (request) {
        if (_inSession) return;
        unawaited(
          _runSession(
            controllers,
            () => controllers.controller.loadCustomStudy(request),
          ),
        );
      },
    );
  }
}

/// Route-scoped read-only listening coach.
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
    required this.onOpenReview,
    required this.onOpenHunting,
    required this.onOpenContentHome,
  });

  final VoidCallback onOpenReview;
  final VoidCallback onOpenHunting;
  final VoidCallback onOpenContentHome;

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
      onOpenReview: widget.onOpenReview,
      onOpenHunting: widget.onOpenHunting,
      onOpenContentHome: widget.onOpenContentHome,
    );
  }
}
