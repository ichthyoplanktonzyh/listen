import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_failure.dart';
import '../models/timeline.dart';
import 'content_package_journey_view_model.dart';
import 'media_session_coordinator.dart';
import 'subtitle_controller.dart';

/// What the workbench shows for "does this media have a learning transcript".
///
/// These are product states, not package-lifecycle states: a user who just
/// opened a media file should never have to know that behind the scenes a
/// content package was generated, imported and reconciled.
enum TranscriptReadinessPhase {
  /// A learning transcript is selected and the normal transcript UI is up.
  ready,

  /// Several usable transcripts exist and none is selected; the user picks.
  choosing,

  /// No usable transcript exists; offer to prepare one (or import a file).
  missing,

  /// A preparation run (generate → import → select) is in flight.
  preparing,

  /// The last preparation run failed. The failure is typed and retryable per
  /// the generator's own semantics; it never silently changes the selection.
  failed,

  /// No usable transcript exists and automatic preparation is not possible on
  /// this machine right now (no configured generator / no media round-trip).
  unavailable,
}

/// User-facing stage of an in-flight preparation, derived from the generator
/// machine's phase events. Kept product-shaped: the UI never sees phase
/// identifiers like `normalizing_audio`.
enum TranscriptPreparationStage {
  starting,
  checkingMedia,
  readingMedia,
  preparingAudio,
  transcribing,
  organizing,
  importing,
}

@immutable
class TranscriptReadinessState {
  TranscriptReadinessState({
    this.phase = TranscriptReadinessPhase.missing,
    this.preparationStage,
    this.failure,
    this.fingerprintMismatch = false,
    this.canCancel = false,
    this.canRetry = false,
    List<SubtitleTrack> usableTracks = const [],
  }) : _usableTracks = List.unmodifiable(usableTracks);

  final TranscriptReadinessPhase phase;

  /// Non-null while [phase] is [TranscriptReadinessPhase.preparing].
  final TranscriptPreparationStage? preparationStage;

  /// Typed failure detail behind [TranscriptReadinessPhase.failed]. Kept off
  /// the main surface: the workbench shows a sentence, not identifiers.
  final ApiFailure? failure;

  /// Whether the failure is a media-fingerprint mismatch, which must stay an
  /// explicit failure rather than being retried or force-imported.
  final bool fingerprintMismatch;
  final bool canCancel;
  final bool canRetry;
  final List<SubtitleTrack> _usableTracks;
  List<SubtitleTrack> get usableTracks => List.unmodifiable(_usableTracks);
}

/// App-layer projection that owns "the current media's learning transcript"
/// as a product journey.
///
/// It reuses [ContentPackageJourneyViewModel] for every piece of package
/// orchestration (process run management, machine events, cancel/retry/
/// cleanup, import, fingerprint handling) and only projects its lifecycle
/// onto readiness states. On a successful import it auto-selects the returned
/// track through the existing primary-track selection, so the user's single
/// "prepare" intent runs to completion without a second "select subtitle" tap.
class TranscriptReadinessViewModel extends ChangeNotifier {
  TranscriptReadinessViewModel({
    required this.subtitle,
    required this.mediaSession,
    required this.canAutoPrepare,
    required this.createJourney,
    Listenable? refreshTrigger,
  })
    // The public seam stays an explicit `refreshTrigger` parameter rather than
    // a private initializing formal, whose call-site name would depend on the
    // `private-named-parameters` language feature.
    // ignore: prefer_initializing_formals
    : _refreshTrigger = refreshTrigger {
    subtitle.store.addListener(_recompute);
    _refreshTrigger?.addListener(_recompute);
    _recompute();
  }

  final SubtitleController subtitle;
  final MediaSessionCoordinator mediaSession;

  /// Whether a preparation run can start right now: the generator is
  /// configured and the current media is registered with the core.
  final bool Function() canAutoPrepare;

  /// Creates the package journey for the *current* media, or null when the
  /// media is not ready (no media id/path/duration). Called lazily on the
  /// first prepare so a media session that never prepares pays no cost.
  final ContentPackageJourneyViewModel? Function() createJourney;
  final Listenable? _refreshTrigger;

  late String Function(String key) text;
  ContentPackageJourneyViewModel? _journey;
  bool _autoSelecting = false;
  bool _disposed = false;

  TranscriptReadinessState _state = TranscriptReadinessState();
  TranscriptReadinessState get state => _state;

  void bind({required String Function(String key) text}) {
    this.text = text;
  }

  List<SubtitleTrack> get _usableTracks => subtitle.subtitleResources
      .where((track) => track.usableForLearning)
      .toList(growable: false);

  Future<void> selectTrack(SubtitleTrack track) async {
    if (subtitle.primaryTrack?.id == track.id) return;
    try {
      await mediaSession.usePrimarySubtitleTrack(
        track,
        nextStatus: text('statusLearningTranscriptSelected'),
      );
      await mediaSession.resourceActions.loadSubtitleResources(
        updateStatus: false,
      );
      _recompute();
    } catch (error) {
      if (!_disposed) {
        mediaSession.player.setStatus(
          text('statusLearningTranscriptSelectionFailed'),
          error: true,
          failure: mediaSession.repository.failureDetail(error),
        );
      }
    }
  }

  Future<void> prepareLearningTranscript() async {
    if (!canAutoPrepare()) return;
    final journey = _ensureJourney();
    if (journey == null) return;
    await journey.generateAndImport();
    _recompute();
  }

  void cancel() {
    _journey?.cancel();
    _recompute();
  }

  Future<void> retry() async {
    final journey = _journey;
    if (journey == null || !journey.canRetry) return;
    await journey.retry();
    _recompute();
  }

  Future<void> importSubtitle() =>
      mediaSession.openSubtitle(secondary: false);

  ContentPackageJourneyViewModel? _ensureJourney() {
    final existing = _journey;
    if (existing != null) return existing;
    final created = createJourney();
    if (created == null) return null;
    _journey = created;
    _journey!.addListener(_onJourneyChanged);
    return created;
  }

  void _onJourneyChanged() {
    final journey = _journey;
    // The user's intent was "give this media a learning transcript": once the
    // import lands, its track becomes the selected learning transcript without
    // a second tap. Core import semantics are untouched — this is the app
    // composing generate → import → select from one explicit intent.
    if (!_autoSelecting &&
        journey != null &&
        journey.state.phase == ContentPackageJourneyPhase.candidateReady &&
        journey.state.receipt?.track != null &&
        journey.state.selectedTrackId == null) {
      _autoSelecting = true;
      unawaited(_autoSelectImportedTrack(journey));
    }
    _recompute();
  }

  Future<void> _autoSelectImportedTrack(
    ContentPackageJourneyViewModel journey,
  ) async {
    try {
      await journey.selectImportedSubtitle();
    } finally {
      _autoSelecting = false;
      _recompute();
    }
  }

  void _recompute() {
    if (_disposed) return;
    final journey = _journey;
    final journeyState = journey?.state;
    final failure = journeyState?.failure;
    final phase = switch (subtitle.primaryTrack) {
      != null => TranscriptReadinessPhase.ready,
      _ when journeyState?.busy ?? false =>
        TranscriptReadinessPhase.preparing,
      _ when journeyState?.phase == ContentPackageJourneyPhase.failed ||
          journeyState?.phase ==
              ContentPackageJourneyPhase.fingerprintMismatch =>
        TranscriptReadinessPhase.failed,
      _ when _usableTracks.isNotEmpty => TranscriptReadinessPhase.choosing,
      _ when canAutoPrepare() => TranscriptReadinessPhase.missing,
      _ => TranscriptReadinessPhase.unavailable,
    };
    final next = TranscriptReadinessState(
      phase: phase,
      preparationStage: phase == TranscriptReadinessPhase.preparing
          ? _preparationStageOf(journeyState)
          : null,
      failure: failure,
      fingerprintMismatch:
          journeyState?.phase == ContentPackageJourneyPhase.fingerprintMismatch,
      canCancel: journey?.canCancel ?? false,
      canRetry: journey?.canRetry ?? false,
      usableTracks: _usableTracks,
    );
    if (identical(next, _state) ||
        (next.phase == _state.phase &&
            next.preparationStage == _state.preparationStage &&
            next.fingerprintMismatch == _state.fingerprintMismatch &&
            next.canCancel == _state.canCancel &&
            next.canRetry == _state.canRetry &&
            next.failure == _state.failure &&
            _sameTracks(next.usableTracks, _state.usableTracks))) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  TranscriptPreparationStage? _preparationStageOf(
    ContentPackageJourneyState? journeyState,
  ) {
    if (journeyState == null) return null;
    switch (journeyState.phase) {
      case ContentPackageJourneyPhase.importing:
        return TranscriptPreparationStage.importing;
      case ContentPackageJourneyPhase.generating:
        switch (journeyState.generatorPhase) {
          case 'validating':
            return TranscriptPreparationStage.checkingMedia;
          case 'probing_media':
            return TranscriptPreparationStage.readingMedia;
          case 'normalizing_audio':
            return TranscriptPreparationStage.preparingAudio;
          case 'transcribing':
            return TranscriptPreparationStage.transcribing;
          case 'building_package':
            return TranscriptPreparationStage.organizing;
        }
        return TranscriptPreparationStage.starting;
      case ContentPackageJourneyPhase.preparing:
      case ContentPackageJourneyPhase.retrying:
        return TranscriptPreparationStage.starting;
      default:
        return null;
    }
  }

  bool _sameTracks(List<SubtitleTrack> a, List<SubtitleTrack> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index].id != b[index].id) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    subtitle.store.removeListener(_recompute);
    _refreshTrigger?.removeListener(_recompute);
    final journey = _journey;
    if (journey != null) {
      journey.removeListener(_onJourneyChanged);
      journey.dispose();
    }
    super.dispose();
  }
}
