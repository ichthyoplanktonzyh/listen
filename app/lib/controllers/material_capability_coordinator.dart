import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/capability_repository.dart';
import '../models/gen_machine_event.dart';
import '../models/learning_edition.dart';
import '../models/learning_material.dart';
import '../models/material_capability.dart';
import '../models/timeline.dart';
import '../services/api_service.dart' show describeApiFailure;
import '../services/capability_file_resolver.dart';
import '../services/capability_generation_request.dart';
import '../services/capability_request_encoder.dart';
import '../services/listen_gen_process_service.dart';

/// The deep Material Capability coordinator. One learner intent — prepare a
/// transcript, listen, watch, or synchronize transcript and audio —
/// hides package lookup, generation, installation, and adoption while
/// preserving their distinct domain outcomes.
///
/// Resolution order: an already adopted compatible composition; a compatible
/// installed candidate (adopted explicitly); an explicit local package import
/// when the caller chooses one; Gen production when the capability is
/// derivable. Community lookup is out of Phase 1 scope.
///
/// Every production run is a durable Core attempt; retry creates a new
/// attempt and never rewrites old facts. Latest-request-wins: when a newer
/// request replaces a run, the stale run's events and results are dropped and
/// its process is terminated without leaving orphans.
class MaterialCapabilityCoordinator extends ChangeNotifier {
  MaterialCapabilityCoordinator({
    required this._repository,
    required this._generator,
    this.mediaFilePath,
    this.mediaPathResolver,
    this.subtitleTrackForMedia,
    this.providerArguments = _noProviderArguments,
    this.generatorToolId = 'listen-gen',
    CapabilityFileResolver? fileResolver,
  }) : _fileResolver =
           fileResolver ??
           _defaultFileResolver(mediaFilePath, mediaPathResolver);

  final CapabilityRepository _repository;
  final ListenGenProcessService _generator;
  final CapabilityFileResolver _fileResolver;

  /// Resolves the local file behind a media rendition, or null when the file
  /// is not available on this machine.
  final Future<String?> Function(MediaRendition rendition)? mediaFilePath;

  /// The authoritative media path resolver: snapshot misses (a freshly
  /// registered media is not yet in any app-side list) round-trip to Core.
  /// Defaults to the file resolver's own path resolution.
  final Future<String?> Function(MediaRendition rendition)? mediaPathResolver;

  /// The currently selected learning subtitle for a media rendition. The
  /// coordinator serializes its exact cue text and timing into a run-owned
  /// SRT input so Gen can skip ASR and force-align the authoritative text.
  final SubtitleTrack? Function(MediaRendition rendition)?
  subtitleTrackForMedia;

  /// CLI arguments selecting the media transcription provider for a run;
  /// provider choice and secrets never enter the request document. Evaluated
  /// per run so a toolchain resolved after construction still applies.
  final List<String> Function() providerArguments;
  final String generatorToolId;

  final Map<String, _CapabilitySession> _sessions = {};
  bool _disposed = false;

  /// Resolves the authoritative local file behind a media rendition: the
  /// injected resolver when present, otherwise the file resolver's own path
  /// resolution (which itself may round-trip).
  Future<String?> _resolveMediaPath(MediaRendition rendition) async {
    final resolver = mediaPathResolver;
    if (resolver != null) return resolver(rendition);
    return _fileResolver.mediaPath(rendition);
  }

  static CapabilityFileResolver _defaultFileResolver(
    Future<String?> Function(MediaRendition rendition)? mediaFilePath,
    Future<String?> Function(MediaRendition rendition)? mediaPathResolver,
  ) {
    final pathResolver = mediaPathResolver ?? mediaFilePath;
    return pathResolver == null
        ? const _UnresolvingCapabilityFileResolver()
        : LocalCapabilityFileResolver(mediaFilePath: pathResolver);
  }

  bool get isConfigured => _generator.isConfigured;

  /// The live run view for one capability of one material, when a run exists.
  CapabilityRunView? runViewFor(
    String materialId,
    MaterialCapability capability,
  ) => _sessions[_sessionKey(materialId, capability)]?.view;

  /// Requests one capability for one material through the resolution order.
  ///
  /// [localPackagePath] selects the explicit local package import branch:
  /// when present, it is installed and adopted before Gen production is
  /// considered.
  ///
  /// When [forceProduce] is true, already installed and adopted editions are
  /// bypassed and a fresh production run with `listen-gen` is forced.
  /// Returns the outcome after the full resolution.
  Future<CapabilityOutcome> requestCapability(
    MaterialDetails material,
    MaterialCapability capability, {
    String? localPackagePath,
    bool forceProduce = false,
  }) async {
    final session = _sessions.putIfAbsent(
      _sessionKey(material.material.id, capability),
      () => _CapabilitySession(material.material.id, capability),
    );
    final run = session.replaceRun();
    _emit();
    try {
      return await _resolve(
        material,
        capability,
        session,
        run,
        localPackagePath,
        forceProduce: forceProduce,
      );
    } finally {
      run.finished = true;
      _emit();
    }
  }

  /// Cancels the active run of one capability and records a cancelled Core
  /// attempt when production has already started.
  Future<void> cancel(
    String materialId,
    MaterialCapability capability, {
    int? requestToken,
  }) async {
    final session = _sessions[_sessionKey(materialId, capability)];
    final run = session?.activeRun;
    if (run == null ||
        (requestToken != null && run.token != requestToken) ||
        run.phase.terminal ||
        run.phase == CapabilityRunPhase.adopting ||
        run.replaced ||
        run.finished ||
        run.finalizationStatus != null) {
      return;
    }
    run.markCancelled();
    _emit();
  }

  /// Drops all sessions and releases resolver-owned temporary files.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final session in _sessions.values) {
      session.activeRun?.markReplaced();
    }
    unawaited(_fileResolver.dispose());
    _sessions.clear();
    super.dispose();
  }

  Future<CapabilityOutcome> _resolve(
    MaterialDetails material,
    MaterialCapability capability,
    _CapabilitySession session,
    _CapabilityRun run,
    String? localPackagePath, {
    bool forceProduce = false,
  }) async {
    final stopped = await _finishIfStopped(run);
    if (stopped != null) return stopped;
    if (forceProduce) {
      return _produce(material, capability, run);
    }

    // 1. Already adopted compatible composition.
    final editions = await _guard(
      run,
      () => _repository.listEditions(material.material.id),
    );
    final stoppedAfterEditions = await _finishIfStopped(run);
    if (stoppedAfterEditions != null) return stoppedAfterEditions;
    if (editions != null) {
      final adopted = _firstSatisfying(
        editions.where((edition) => edition.adopted),
        capability,
      );
      if (adopted != null) {
        run.phase = CapabilityRunPhase.completed;
        return CapabilityAvailable(edition: adopted);
      }

      // 2. Compatible installed candidate: adopt it explicitly.
      final candidate = _firstSatisfying(editions, capability);
      if (candidate != null) {
        run.phase = CapabilityRunPhase.adopting;
        _emit();
        try {
          final adoptedEdition = await _repository.adoptEdition(
            material.material.id,
            candidate.releaseId,
          );
          if (run.replaced) return const CapabilityReplaced();
          run.phase = CapabilityRunPhase.completed;
          return CapabilityAvailable(edition: adoptedEdition);
        } on Object catch (error) {
          run.warnings.add(_friendly(error));
          run.phase = CapabilityRunPhase.resolving;
        }
      }
    }

    // 3. Explicit local package import when chosen.
    if (localPackagePath != null && localPackagePath.isNotEmpty) {
      run.phase = CapabilityRunPhase.installing;
      _emit();
      try {
        final installed = await _repository.installPackage(
          material.material.id,
          localPackagePath,
        );
        final stoppedAfterInstall = await _finishIfStopped(run);
        if (stoppedAfterInstall != null) return stoppedAfterInstall;
        run.phase = CapabilityRunPhase.adopting;
        _emit();
        final adopted = await _repository.adoptEdition(
          material.material.id,
          installed.releaseId,
        );
        if (run.replaced) return const CapabilityReplaced();
        run.phase = CapabilityRunPhase.completed;
        return CapabilityAvailable(edition: adopted);
      } on Object catch (error) {
        final stopped = await _finishIfStopped(run);
        if (stopped != null) return stopped;
        return _fail(run, error);
      }
    }

    // 4. Gen production when derivable.
    final projections = await _guard(
      run,
      () => _repository.listCapabilities(material.material.id),
    );
    final stoppedAfterProjection = await _finishIfStopped(run);
    if (stoppedAfterProjection != null) return stoppedAfterProjection;
    if (projections == null) return _fail(run, const _CoordinatorUnavailable());
    final status = projections
        .where((projection) => projection.capability == capability)
        ._firstOrNull
        ?.status;
    switch (status) {
      // The capability is already satisfied by current media facts or an
      // adopted composition, so no production run starts. The projection
      // carries the evidence; report it as available, never as broken.
      case MaterialCapabilityStatus.available:
        run.phase = CapabilityRunPhase.completed;
        return const CapabilityAvailable();
      case MaterialCapabilityStatus.unavailable:
        run.phase = CapabilityRunPhase.completed;
        return const CapabilityUnavailable();
      case MaterialCapabilityStatus.derivable:
      case MaterialCapabilityStatus.failedAttempt:
      // A projection still marked generating (a leftover running attempt)
      // is superseded by a fresh attempt: latest-request-wins.
      case MaterialCapabilityStatus.generating:
        return _produce(material, capability, run);
      case null:
        run.phase = CapabilityRunPhase.completed;
        return const CapabilityUnavailable();
    }
  }

  Future<CapabilityOutcome> _produce(
    MaterialDetails material,
    MaterialCapability capability,
    _CapabilityRun run,
  ) async {
    final stoppedBeforeAttempt = await _finishIfStopped(run);
    if (stoppedBeforeAttempt != null) return stoppedBeforeAttempt;

    // The durable attempt: retry creates a new attempt, never rewrites facts.
    final CapabilityAttempt attempt;
    try {
      attempt = await _repository.startAttempt(
        material.material.id,
        _capabilityName(capability),
      );
    } on Object catch (error) {
      final stopped = await _finishIfStopped(run);
      if (stopped != null) return stopped;
      return _fail(run, error);
    }
    run.attemptId = attempt.attemptId;
    _emit();
    final stoppedAfterAttempt = await _finishIfStopped(run);
    if (stoppedAfterAttempt != null) return stoppedAfterAttempt;

    // Core 5.0 media renditions carry no byte digest; when the rendition's
    // file is on this machine the file resolver computes the authoritative
    // blob facts the request must declare. The path map feeds the Gen run;
    // snapshot misses fall through to the authoritative resolver (a freshly
    // registered media is not yet in any app-side list).
    final mediaBlobFacts = <String, MediaBlobFacts>{};
    final mediaPaths = <String, String>{};
    for (final rendition in material.currentRevision.mediaRenditions) {
      final path = await _resolveMediaPath(rendition);
      final stoppedAfterMediaPath = await _finishIfStopped(run);
      if (stoppedAfterMediaPath != null) return stoppedAfterMediaPath;
      if (path != null) mediaPaths[rendition.id] = path;
      final facts = await _fileResolver.mediaBlobFacts(rendition);
      final stoppedAfterBlobFacts = await _finishIfStopped(run);
      if (stoppedAfterBlobFacts != null) return stoppedAfterBlobFacts;
      if (facts != null) mediaBlobFacts[rendition.id] = facts;
    }

    final subtitleSrt = _selectedSubtitleSrt(
      material.currentRevision.mediaRenditions,
    );

    final requestJson = CapabilityRequestEncoder.encode(
      materialId: material.material.id,
      materialRevisionId: material.currentRevision.id,
      materialTitle: material.currentRevision.title,
      editionId: CapabilityRequestEncoder.editionIdFor(material.material.id),
      editionTitle: material.currentRevision.title,
      targetLanguage: _targetLanguageFor(material),
      supportLanguages: const [],
      requestedCapability: _capabilityName(capability),
      createdAtMs: attempt.startedAtMs,
      attemptId: attempt.attemptId,
      mediaRenditions: material.currentRevision.mediaRenditions,
      mediaFilePath: (rendition) => mediaPaths[rendition.id],
      mediaBlobFacts: mediaBlobFacts,
    );
    final stoppedBeforeGeneratorStart = await _finishIfStopped(run);
    if (stoppedBeforeGeneratorStart != null) {
      return stoppedBeforeGeneratorStart;
    }

    final ListenGenProcessRun processRun;
    try {
      processRun = await _generator.start(
        CapabilityGenerationRequest(
          requestJson: requestJson,
          providerArguments: providerArguments(),
          subtitleSrt: subtitleSrt,
        ),
      );
    } on Object catch (error) {
      final stopped = await _finishIfStopped(run);
      if (stopped != null) return stopped;
      await _finalizeAttempt(
        run,
        status: CapabilityAttemptFinalStatus.failed,
        failureReason: _stableCode(error),
      );
      return _fail(run, error);
    }
    run.processRun = processRun;
    final stoppedAfterGeneratorStart = await _finishIfStopped(
      run,
      processRun: processRun,
    );
    if (stoppedAfterGeneratorStart != null) return stoppedAfterGeneratorStart;
    run.phase = CapabilityRunPhase.generating;
    _emit();

    final terminal = Completer<GenEventTerminal>();
    final subscription = processRun.events.listen(
      (event) {
        if (run.replaced || run.cancelled) return;
        switch (event.kind) {
          case GenEventKind.running:
            run.stage = event.stage;
            _emit();
          case GenEventKind.warning:
            run.warnings.add('${event.warningCode}: ${event.warningMessage}');
            _emit();
          case GenEventKind.accepted:
            // The accepted attempt id must name the attempt this run opened;
            // a mismatch is a protocol violation.
            if (event.attemptId != null &&
                event.attemptId != attempt.attemptId) {
              run.warnings.add(
                'attempt_id_mismatch: generator accepted a different attempt',
              );
              _requestTermination(processRun);
            }
          case GenEventKind.protocol:
          case GenEventKind.planned:
          case GenEventKind.completed ||
              GenEventKind.cancelled ||
              GenEventKind.failed:
            final value = event.terminal;
            if (value != null && !terminal.isCompleted) {
              terminal.complete(value);
            }
        }
      },
      onError: (Object _) {
        if (!terminal.isCompleted) {
          terminal.complete(GenEventTerminal(GenEventKind.failed));
        }
      },
    );
    unawaited(
      processRun.packagePath
          .then<void>((path) {
            // The terminal outcome is driven by the machine events: a real Gen run
            // emits `completed` before it resolves the artifact path. A success
            // here never fabricates an empty-plan completion; only a failed
            // artifact handoff (process died without a terminal event, protocol
            // violation, digest mismatch) completes the run as failed.
          })
          .catchError((Object error) {
            if (!terminal.isCompleted) {
              final failure = error is ListenGenProcessFailure
                  ? error
                  : const ListenGenProcessFailure('generation_failed');
              terminal.complete(
                GenEventTerminal(
                  GenEventKind.failed,
                  code: failure.code,
                  message: failure.message,
                ),
              );
            }
          }),
    );

    final awaited = await Future.any<GenEventTerminal?>([
      terminal.future,
      run.stopSignal.then<GenEventTerminal?>((_) => null),
    ]);
    await subscription.cancel();
    final stoppedAfterTerminal = await _finishIfStopped(
      run,
      processRun: processRun,
    );
    if (stoppedAfterTerminal != null) return stoppedAfterTerminal;
    if (awaited == null) {
      throw StateError('Capability run stopped without a stop reason.');
    }
    if (awaited.kind == GenEventKind.cancelled) {
      run.markCancelled();
      final stoppedByGenerator = await _finishIfStopped(
        run,
        processRun: processRun,
      );
      return stoppedByGenerator ?? const CapabilityCancelled();
    }
    if (awaited.kind != GenEventKind.completed) {
      final code = awaited.code ?? 'generation_failed';
      await _finalizeAttempt(
        run,
        status: CapabilityAttemptFinalStatus.failed,
        failureReason: code,
      );
      await _cleanupProcessRun(processRun);
      return _fail(
        run,
        ListenGenProcessFailure(code, message: awaited.message),
      );
    }

    final String? packagePath;
    if (awaited.packageSha256 == null) {
      packagePath = null;
    } else {
      try {
        packagePath = await processRun.packagePath;
      } on Object catch (error) {
        final stopped = await _finishIfStopped(run, processRun: processRun);
        if (stopped != null) return stopped;
        await _finalizeAttempt(
          run,
          status: CapabilityAttemptFinalStatus.failed,
          failureReason: _stableCode(error),
        );
        await _cleanupProcessRun(processRun);
        return _fail(run, error);
      }
    }
    final stoppedAfterPackageHandoff = await _finishIfStopped(
      run,
      processRun: processRun,
    );
    if (stoppedAfterPackageHandoff != null) return stoppedAfterPackageHandoff;
    if (packagePath == null) {
      // An empty plan is a satisfied outcome, not a failure: the generator
      // found the capability already provided by the available media resources and
      // produced no package. The durable attempt records the success and the
      // run completes without an installed edition.
      await _finalizeAttempt(
        run,
        status: CapabilityAttemptFinalStatus.succeeded,
        toolId: generatorToolId,
        toolVersion: processRun.verifiedToolVersion,
      );
      run.phase = CapabilityRunPhase.completed;
      _emit();
      await _cleanupProcessRun(processRun);
      if (run.replaced) return const CapabilityReplaced();
      return const CapabilityAvailable();
    }

    // Candidate-only installation, then explicit adoption. The produced
    // carrier is Core-owned from here on: adopted content resolves through
    // Core's composition interface, never through an app-side retained copy.
    run.phase = CapabilityRunPhase.installing;
    _emit();
    final LearningEdition installed;
    try {
      installed = await _repository.installPackage(
        material.material.id,
        packagePath,
      );
    } on Object catch (error) {
      final stopped = await _finishIfStopped(run, processRun: processRun);
      if (stopped != null) return stopped;
      await _finalizeAttempt(
        run,
        status: CapabilityAttemptFinalStatus.failed,
        failureReason: _stableCode(error),
      );
      await _cleanupProcessRun(processRun);
      return _fail(run, error);
    }
    final stoppedAfterInstall = await _finishIfStopped(
      run,
      processRun: processRun,
    );
    if (stoppedAfterInstall != null) return stoppedAfterInstall;
    run.phase = CapabilityRunPhase.adopting;
    _emit();
    final LearningEdition adopted;
    try {
      adopted = await _repository.adoptEdition(
        material.material.id,
        installed.releaseId,
      );
    } on Object catch (error) {
      final stopped = await _finishIfStopped(run, processRun: processRun);
      if (stopped != null) return stopped;
      await _finalizeAttempt(
        run,
        status: CapabilityAttemptFinalStatus.failed,
        failureReason: _stableCode(error),
      );
      await _cleanupProcessRun(processRun);
      return _fail(run, error);
    }
    await _finalizeAttempt(
      run,
      status: CapabilityAttemptFinalStatus.succeeded,
      toolId: generatorToolId,
      toolVersion: processRun.verifiedToolVersion,
    );
    run.phase = CapabilityRunPhase.completed;
    run.producedPackageSha256 = awaited.packageSha256;
    _emit();
    await _cleanupProcessRun(processRun);
    if (run.replaced) return const CapabilityReplaced();
    return CapabilityAvailable(edition: adopted);
  }

  String? _selectedSubtitleSrt(List<MediaRendition> renditions) {
    SubtitleTrack? track;
    for (final rendition in renditions) {
      final candidate = subtitleTrackForMedia?.call(rendition);
      if (candidate != null && candidate.usableForLearning) {
        track = candidate;
        break;
      }
    }
    if (track == null) return null;
    final buffer = StringBuffer();
    for (var index = 0; index < track.cues.length; index += 1) {
      final cue = track.cues[index];
      buffer
        ..writeln(index + 1)
        ..writeln(
          '${_srtTimestamp(cue.start.inMilliseconds)} --> '
          '${_srtTimestamp(cue.end.inMilliseconds)}',
        )
        ..writeln(cue.text)
        ..writeln();
    }
    return buffer.toString();
  }

  static String _srtTimestamp(int milliseconds) {
    final hours = milliseconds ~/ 3600000;
    final minutes = (milliseconds % 3600000) ~/ 60000;
    final seconds = (milliseconds % 60000) ~/ 1000;
    final millis = milliseconds % 1000;
    String pad(int value, int width) => value.toString().padLeft(width, '0');
    return '${pad(hours, 2)}:${pad(minutes, 2)}:${pad(seconds, 2)},${pad(millis, 3)}';
  }

  /// The media subtitle language is the only declared target language for
  /// generation; unknown remains `und` rather than guessing from preferences.
  String _targetLanguageFor(MaterialDetails material) {
    for (final rendition in material.currentRevision.mediaRenditions) {
      final language = subtitleTrackForMedia?.call(rendition)?.language;
      if (language != null && language.isNotEmpty) return language;
    }
    return 'und';
  }

  static List<String> _noProviderArguments() => const [];

  Future<CapabilityOutcome?> _finishIfStopped(
    _CapabilityRun run, {
    ListenGenProcessRun? processRun,
    StreamSubscription<GenMachineEvent>? subscription,
  }) async {
    if (run.finalizationStatus == CapabilityAttemptFinalStatus.succeeded ||
        (!run.cancelled && !run.replaced)) {
      return null;
    }
    await subscription?.cancel();
    final process = processRun ?? run.processRun;
    if (process != null) {
      _observePackageOutcome(process);
      process.cancel();
      await _cleanupProcessRun(process);
    }
    await _finalizeAttempt(run, status: CapabilityAttemptFinalStatus.cancelled);
    return run.replaced
        ? const CapabilityReplaced()
        : const CapabilityCancelled();
  }

  Future<void> _cleanupProcessRun(ListenGenProcessRun processRun) async {
    try {
      await processRun.cleanUp();
    } on Object catch (_) {
      // Cleanup must not strand the user-visible run after child reaping.
    }
  }

  void _observePackageOutcome(ListenGenProcessRun processRun) {
    unawaited(
      processRun.packagePath.then<void>((_) {}).catchError((Object _) {}),
    );
  }

  Future<void> _finalizeAttempt(
    _CapabilityRun run, {
    required CapabilityAttemptFinalStatus status,
    String? failureReason,
    String? toolId,
    String? toolVersion,
  }) {
    final existing = run.finalizationFuture;
    if (existing != null) return existing;
    final attemptId = run.attemptId;
    if (attemptId == null) return Future<void>.value();

    run.finalizationStatus = status;
    final finalization = _repository
        .finalizeAttempt(
          materialId: run.materialId,
          attemptId: attemptId,
          status: status,
          failureReason: failureReason,
          toolId: toolId,
          toolVersion: toolVersion,
        )
        .then<void>((_) {})
        .catchError((Object _) {
          // Attempt finalization is best-effort; the run view remains the
          // source of immediate status and Core's projection is refreshed.
        });
    run.finalizationFuture = finalization;
    return finalization;
  }

  /// Runs [action], mapping every failure into the run state. Returns null
  /// when the action failed.
  Future<T?> _guard<T>(_CapabilityRun run, Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error) {
      if (run.cancelled || run.replaced) return null;
      run.phase = CapabilityRunPhase.failed;
      run.failure = _friendly(error);
      run.failureDetail = _detail(error);
      _emit();
      return null;
    }
  }

  CapabilityOutcome _fail(_CapabilityRun run, Object error) {
    if (run.replaced) return const CapabilityReplaced();
    run.phase = CapabilityRunPhase.failed;
    run.failure = _friendly(error);
    run.failureDetail = _detail(error);
    _emit();
    return CapabilityFailed(
      error: error,
      retryable: error is ListenGenProcessFailure && error.retryable,
    );
  }

  static void _requestTermination(ListenGenProcessRun run) {
    run.cancel();
  }

  static String _stableCode(Object error) {
    if (error is ListenGenProcessFailure) return error.code;
    // Core answers a rejected install with a typed envelope
    // (`package_installation_invalid`, ...). It arrives as an HttpException
    // carrying that body, so it goes through the transport's own describer
    // rather than collapsing into `unexpected_error` — a run that names the
    // rejection is the difference between a fixable report and a shrug.
    final api = describeApiFailure(error);
    return api.code ??
        (api.isStructured ? 'request_failed' : 'unexpected_error');
  }

  static String _friendly(Object error) {
    if (error is ListenGenProcessFailure) return error.message ?? error.code;
    final api = describeApiFailure(error);
    return api.code ??
        (api.isStructured ? 'request_failed' : 'unexpected_error');
  }

  /// The one sentence behind [_friendly], when the failure carries one.
  ///
  /// Gen failures speak through their own path-free message; Core failures
  /// speak through the envelope's `message`. Anything unstructured stays
  /// silent rather than leaking raw exception text into the UI.
  static String? _detail(Object error) {
    if (error is ListenGenProcessFailure) return error.message;
    return describeApiFailure(error).message;
  }

  static String _capabilityName(MaterialCapability capability) =>
      switch (capability) {
        MaterialCapability.read => 'read',
        MaterialCapability.listen => 'listen',
        MaterialCapability.watch => 'watch',
        MaterialCapability.synchronizedReadListen => 'synchronized_read_listen',
      };

  static String _sessionKey(String materialId, MaterialCapability capability) =>
      '$materialId:${_capabilityName(capability)}';

  LearningEdition? _firstSatisfying(
    Iterable<LearningEdition> editions,
    MaterialCapability capability,
  ) {
    for (final edition in editions) {
      if (_editionSatisfies(edition, capability)) return edition;
    }
    return null;
  }

  bool _editionSatisfies(
    LearningEdition edition,
    MaterialCapability capability,
  ) => edition.availableCapabilities.contains(_capabilityName(capability));

  void _emit() {
    if (!_disposed) notifyListeners();
  }
}

/// One requested capability's session: the current run plus the replacement
/// token for latest-request-wins.
final class _CapabilitySession {
  _CapabilitySession(this.materialId, this.capability);

  final String materialId;
  final MaterialCapability capability;
  int _requestToken = 0;
  _CapabilityRun? _activeRun;

  _CapabilityRun replaceRun() {
    _requestToken++;
    final previous = _activeRun;
    previous?.markReplaced();
    _activeRun = _CapabilityRun(materialId, capability, _requestToken);
    return _activeRun!;
  }

  _CapabilityRun? get activeRun => _activeRun;

  CapabilityRunView? get view => _activeRun?.view;
}

final class _CapabilityRun {
  _CapabilityRun(this.materialId, this.capability, this.token);

  final String materialId;
  final MaterialCapability capability;
  final int token;
  bool replaced = false;
  bool cancelled = false;
  bool finished = false;
  final Completer<void> _stopCompleter = Completer<void>();
  CapabilityRunPhase phase = CapabilityRunPhase.resolving;
  String? stage;
  final List<String> warnings = [];
  String? failure;
  String? failureDetail;
  String? attemptId;
  String? producedPackageSha256;
  ListenGenProcessRun? processRun;
  CapabilityAttemptFinalStatus? finalizationStatus;
  Future<void>? finalizationFuture;

  Future<void> get stopSignal => _stopCompleter.future;

  void markCancelled() {
    if (replaced || finalizationStatus != null) return;
    cancelled = true;
    phase = CapabilityRunPhase.cancelled;
    if (!_stopCompleter.isCompleted) _stopCompleter.complete();
    processRun?.cancel();
  }

  void markReplaced() {
    replaced = true;
    if (!_stopCompleter.isCompleted) _stopCompleter.complete();
    if (finalizationStatus != CapabilityAttemptFinalStatus.succeeded) {
      processRun?.cancel();
    }
  }

  CapabilityRunView get view => CapabilityRunView(
    materialId: materialId,
    capability: capability,
    phase: phase,
    requestToken: token,
    stage: stage,
    warnings: List.unmodifiable(warnings),
    failureCode: failure,
    failureMessage: failureDetail,
    attemptId: attemptId,
    producedPackageSha256: producedPackageSha256,
  );
}

/// A local core lookup failed without a typed code (repository returned
/// null). Treated as a failed attempt, not a capability verdict.
final class _CoordinatorUnavailable implements Exception {
  const _CoordinatorUnavailable();
}

/// Default file resolver when no real one is wired: resolves nothing. The
/// coordinator is testable without a file system; production wiring injects
/// the local resolver at the composition root.
final class _UnresolvingCapabilityFileResolver
    implements CapabilityFileResolver {
  const _UnresolvingCapabilityFileResolver();

  @override
  Future<String?> mediaPath(MediaRendition rendition) async => null;

  @override
  Future<MediaBlobFacts?> mediaBlobFacts(MediaRendition rendition) async =>
      null;

  @override
  Future<void> dispose() async {}
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get _firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
