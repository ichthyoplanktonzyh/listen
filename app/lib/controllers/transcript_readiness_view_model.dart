import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/api_failure.dart';
import '../models/learning_material.dart';
import '../models/material_capability.dart';
import '../models/timeline.dart';
import 'material_capability_coordinator.dart';
import 'media_session_coordinator.dart';
import 'subtitle_controller.dart';

/// What the workbench shows for "does this media have a learning transcript".
///
/// These are product states, not package-lifecycle states: a user who just
/// opened a media file should never have to know that behind the scenes a
/// package was generated, installed and adopted.
enum TranscriptReadinessPhase {
  /// A learning transcript is selected and the normal transcript UI is up.
  ready,

  /// Several usable transcripts exist and none is selected; the user picks.
  choosing,

  /// No usable transcript exists; offer to prepare one (or import a file).
  missing,

  /// A preparation run (request → generate → install → adopt) is in flight.
  preparing,

  /// The last preparation run failed. The failure is typed and retryable per
  /// the generator's own semantics; it never silently changes the selection.
  failed,

  /// No usable transcript exists and automatic preparation is not possible on
  /// this machine right now (no configured generator / no media round-trip).
  unavailable,
}

/// User-facing stage of an in-flight preparation, derived from the coordinator
/// run stage. Kept product-shaped: the UI never sees stage identifiers.
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
/// It reuses [MaterialCapabilityCoordinator] for the whole completion flow
/// (resolution, generation through the pinned bundle, installation and
/// adoption) and projects its run onto readiness states.
class TranscriptReadinessViewModel extends ChangeNotifier {
  TranscriptReadinessViewModel({
    required this.subtitle,
    required this.mediaSession,
    required this.canAutoPrepare,
    required this.coordinator,
    required this.currentMaterial,
    Listenable? refreshTrigger,
  })
    // The public seam stays an explicit `refreshTrigger` parameter rather than
    // a private initializing formal, whose call-site name would depend on the
    // `private-named-parameters` language feature.
    // ignore: prefer_initializing_formals
    : _refreshTrigger = refreshTrigger {
    subtitle.store.addListener(_recompute);
    coordinator.addListener(_recompute);
    _refreshTrigger?.addListener(_recompute);
    _recompute();
  }

  final SubtitleController subtitle;
  final MediaSessionCoordinator mediaSession;

  /// Whether a preparation run can start right now: the generator is
  /// configured and the current media is registered with the core.
  final bool Function() canAutoPrepare;

  /// The deep completion coordinator.
  final MaterialCapabilityCoordinator coordinator;

  /// The current media's material, when one is registered.
  final MaterialDetails? Function() currentMaterial;
  final Listenable? _refreshTrigger;

  late String Function(String key) text;
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
    final material = currentMaterial();
    if (material == null) return;
    await coordinator.requestCapability(material, MaterialCapability.read);
    _recompute();
  }

  void cancel() {
    final material = currentMaterial();
    if (material == null) return;
    unawaited(coordinator.cancel(material.material.id, MaterialCapability.read));
    _recompute();
  }

  Future<void> retry() async {
    final material = currentMaterial();
    if (material == null) return;
    await coordinator.requestCapability(material, MaterialCapability.read);
    _recompute();
  }

  Future<void> importSubtitle() =>
      mediaSession.openSubtitle(secondary: false);

  void _recompute() {
    if (_disposed) return;
    final material = currentMaterial();
    final run = material == null
        ? null
        : coordinator.runViewFor(material.material.id, MaterialCapability.read);
    final runFailure = run?.failureCode;
    final phase = switch (subtitle.primaryTrack) {
      != null => TranscriptReadinessPhase.ready,
      // A completed production run leaves the transcript available as the
      // adopted composition, even before any subtitle track selection.
      _ when run?.phase == CapabilityRunPhase.completed =>
        TranscriptReadinessPhase.ready,
      _ when run?.busy ?? false => TranscriptReadinessPhase.preparing,
      _ when run?.phase == CapabilityRunPhase.failed =>
        TranscriptReadinessPhase.failed,
      _ when _usableTracks.isNotEmpty => TranscriptReadinessPhase.choosing,
      _ when canAutoPrepare() => TranscriptReadinessPhase.missing,
      _ => TranscriptReadinessPhase.unavailable,
    };
    final next = TranscriptReadinessState(
      phase: phase,
      preparationStage: phase == TranscriptReadinessPhase.preparing
          ? _preparationStageOf(run?.stage)
          : null,
      failure: runFailure == null ? null : ApiFailure(raw: runFailure),
      fingerprintMismatch: false,
      canCancel: run?.busy ?? false,
      canRetry: run?.phase == CapabilityRunPhase.failed,
      usableTracks: _usableTracks,
    );
    if (identical(next, _state) ||
        (next.phase == _state.phase &&
            next.preparationStage == _state.preparationStage &&
            next.fingerprintMismatch == _state.fingerprintMismatch &&
            next.canCancel == _state.canCancel &&
            next.canRetry == _state.canRetry &&
            next.failure?.raw == _state.failure?.raw &&
            _sameTracks(next.usableTracks, _state.usableTracks))) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  TranscriptPreparationStage? _preparationStageOf(String? stage) {
    if (stage == null) return TranscriptPreparationStage.starting;
    final lower = stage.toLowerCase();
    if (lower.contains('transcrib')) return TranscriptPreparationStage.transcribing;
    if (lower.contains('decoding') || lower.contains('read')) {
      return TranscriptPreparationStage.readingMedia;
    }
    if (lower.contains('normaliz') ||
        lower.contains('tts') ||
        lower.contains('synthesi')) {
      return TranscriptPreparationStage.preparingAudio;
    }
    if (lower.contains('validat') || lower.contains('prob')) {
      return TranscriptPreparationStage.checkingMedia;
    }
    if (lower.contains('build') || lower.contains('qualify')) {
      return TranscriptPreparationStage.organizing;
    }
    if (lower.contains('install') || lower.contains('adopt')) {
      return TranscriptPreparationStage.importing;
    }
    return TranscriptPreparationStage.starting;
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
    coordinator.removeListener(_recompute);
    _refreshTrigger?.removeListener(_recompute);
    super.dispose();
  }
}