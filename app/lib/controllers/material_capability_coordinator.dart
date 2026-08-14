import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/capability_repository.dart';
import '../models/api_failure.dart';
import '../models/gen_machine_event.dart';
import '../models/learning_edition.dart';
import '../models/learning_material.dart';
import '../models/material_capability.dart';
import '../services/capability_file_resolver.dart';
import '../services/capability_generation_request.dart';
import '../services/capability_request_encoder.dart';
import '../services/listen_gen_process_service.dart';
import '../services/reusable_resource_resolver.dart';

/// The deep Material Capability coordinator. One learner intent — "Read",
/// "Listen", "Watch", or synchronized Read-and-Listen for one Material —
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
    this.providerArguments = _noProviderArguments,
    this.generatorToolId = 'listen-gen',
    this.generatorToolVersion = '0.5.0',
    CapabilityFileResolver? fileResolver,
    ReusableResourceResolver? reusableResources,
  }) : _fileResolver = fileResolver ?? const _UnresolvingCapabilityFileResolver(),
       _reusableResources = reusableResources ??
           ReusableResourceResolver(_repository);

  final CapabilityRepository _repository;
  final ListenGenProcessService _generator;
  final CapabilityFileResolver _fileResolver;
  final ReusableResourceResolver _reusableResources;

  /// Resolves the local file behind a media rendition, or null when the file
  /// is not available on this machine.
  final String? Function(MediaRendition rendition)? mediaFilePath;

  /// CLI arguments selecting the Gen providers for a run (e.g.
  /// `--tts-provider say`, `--provider whisper-cpp --model …`); provider
  /// choice and secrets never enter the request document. Evaluated per run
  /// so a toolchain resolved after construction still applies.
  final List<String> Function() providerArguments;
  final String generatorToolId;
  final String generatorToolVersion;

  final Map<String, _CapabilitySession> _sessions = {};

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
  /// considered. Returns the outcome after the full resolution.
  Future<CapabilityOutcome> requestCapability(
    MaterialDetails material,
    MaterialCapability capability, {
    String? localPackagePath,
  }) async {
    final session = _sessions.putIfAbsent(
      _sessionKey(material.material.id, capability),
      () => _CapabilitySession(material.material.id, capability),
    );
    final run = session.replaceRun();
    _emit();
    try {
      return await _resolve(material, capability, session, run, localPackagePath);
    } finally {
      run.finished = true;
      _emit();
    }
  }

  /// Cancels the active production run of one capability. The durable Core
  /// attempt is finalized as a failed attempt with the stable `cancelled`
  /// reason; the Gen process is terminated without orphaning it.
  Future<void> cancel(String materialId, MaterialCapability capability) async {
    final session = _sessions[_sessionKey(materialId, capability)];
    final run = session?.activeRun;
    if (run == null || run.phase.terminal || run.finished) return;
    run.cancelled = true;
    run.phase = CapabilityRunPhase.cancelled;
    _emit();
    // The durable `cancelled` finalize note is written by the run's own
    // cancellation branch in _produce, which also owns the process teardown.
    run.processRun?.cancel();
  }

  /// Drops all sessions and releases resolver-owned temporary files.
  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.activeRun?.processRun?.cancel();
    }
    unawaited(_fileResolver.dispose());
    unawaited(_reusableResources.dispose());
    _sessions.clear();
    super.dispose();
  }

  Future<CapabilityOutcome> _resolve(
    MaterialDetails material,
    MaterialCapability capability,
    _CapabilitySession session,
    _CapabilityRun run,
    String? localPackagePath,
  ) async {
    // 1. Already adopted compatible composition.
    final editions = await _guard(
      run,
      () => _repository.listEditions(material.material.id),
    );
    if (editions != null) {
      final adopted = _firstSatisfying(
        editions.where((edition) => edition.adopted),
        material,
        capability,
      );
      if (adopted != null) {
        run.phase = CapabilityRunPhase.completed;
        return CapabilityAvailable(edition: adopted);
      }

      // 2. Compatible installed candidate: adopt it explicitly.
      final candidate = _firstSatisfying(editions, material, capability);
      if (candidate != null) {
        run.phase = CapabilityRunPhase.adopting;
        _emit();
        try {
          final adoptedEdition = await _repository.adoptEdition(
            material.material.id,
            candidate.releaseId,
          );
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
        final adopted = await _repository.adoptEdition(
          material.material.id,
          installed.releaseId,
        );
        run.phase = CapabilityRunPhase.completed;
        return CapabilityAvailable(edition: adopted);
      } on Object catch (error) {
        return _fail(run, error);
      }
    }

    // 4. Gen production when derivable.
    final projections = await _guard(
      run,
      () => _repository.listCapabilities(material.material.id),
    );
    if (projections == null) return _fail(run, const _CoordinatorUnavailable());
    final status = projections
        .where((projection) => projection.capability == capability)
        ._firstOrNull
        ?.status;
    switch (status) {
      // The capability is already satisfied by the current material facts —
      // a directly readable document or an adopted composition the learner
      // already has — so no production run starts. The projection carries
      // the evidence; the run reports it as available, never as broken.
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
    // The durable attempt: retry creates a new attempt, never rewrites facts.
    final CapabilityAttempt attempt;
    try {
      attempt = await _repository.startAttempt(
        material.material.id,
        _capabilityName(capability),
      );
    } on Object catch (error) {
      return _fail(run, error);
    }
    run.attemptId = attempt.attemptId;
    _emit();

    // Core 4.0 media renditions carry no byte digest; when the rendition's
    // file is on this machine the file resolver computes the authoritative
    // blob facts the request must declare.
    final mediaBlobFacts = <String, MediaBlobFacts>{};
    for (final rendition in material.currentRevision.mediaRenditions) {
      final facts = await _fileResolver.mediaBlobFacts(rendition);
      if (facts != null) mediaBlobFacts[rendition.id] = facts;
    }

    // Document renditions resolve to their exact Source Asset bytes — never a
    // fabricated extracted-text file. The path map feeds the Gen run; the
    // digest facts travel in the request.
    final revision = material.currentRevision;
    final assetsById = <String, SourceAsset>{
      for (final asset in revision.sourceAssets) asset.id: asset,
    };
    final documentSourcePaths = <String, String>{};
    final documentSourceAssetIds = <String, String>{};
    for (final rendition in revision.documentRenditions) {
      final asset = assetsById[rendition.sourceAssetId];
      final path = await _fileResolver.documentSourcePath(rendition, asset);
      if (path != null) {
        documentSourcePaths[rendition.id] = path;
        documentSourceAssetIds[rendition.id] =
            rendition.sourceAssetId ?? rendition.id;
      }
    }

    // Resources the current adopted composition already carries are declared
    // as reusable: a compatible Structured Reading is consumed by Gen instead
    // of being regenerated. The payload is materialized to a run-owned
    // temporary file so the generator can verify the exact bytes it reuses.
    final availableResources = await _reusableResources.resolve(material);

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
      documentRenditions: material.currentRevision.documentRenditions,
      documentSourcePaths: documentSourcePaths,
      documentSourceAssetIds: documentSourceAssetIds,
      mediaRenditions: material.currentRevision.mediaRenditions,
      mediaFilePath: mediaFilePath,
      mediaBlobFacts: mediaBlobFacts,
      availableResources: availableResources,
    );

    final ListenGenProcessRun processRun;
    try {
      processRun = await _generator.start(
        CapabilityGenerationRequest(
          requestJson: requestJson,
          providerArguments: providerArguments(),
        ),
      );
    } on Object catch (error) {
      await _finalizeFailure(run, _stableCode(error));
      return _fail(run, error);
    }
    run.processRun = processRun;
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
            if (event.attemptId != null && event.attemptId != attempt.attemptId) {
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
            if (value != null && !terminal.isCompleted) terminal.complete(value);
        }
      },
      onError: (Object _) {
        if (!terminal.isCompleted) {
          terminal.complete(GenEventTerminal(GenEventKind.failed));
        }
      },
    );
    unawaited(processRun.packagePath.then<void>((path) {
      // The terminal outcome is driven by the machine events: a real Gen run
      // emits `completed` before it resolves the artifact path. A success
      // here never fabricates an empty-plan completion; only a failed
      // artifact handoff (process died without a terminal event, protocol
      // violation, digest mismatch) completes the run as failed.
    }).catchError((Object _) {
      if (!terminal.isCompleted) {
        terminal.complete(GenEventTerminal(GenEventKind.failed));
      }
    }));

    final awaited = await terminal.future;
    await subscription.cancel();
    if (run.replaced) {
      // Latest-request-wins: the stale run's results are dropped.
      unawaited(processRun.cleanUp());
      return const CapabilityReplaced();
    }
    if (run.cancelled) {
      await _finalizeFailure(run, 'cancelled');
      unawaited(processRun.cleanUp());
      return const CapabilityCancelled();
    }
    if (awaited.kind != GenEventKind.completed) {
      final code = awaited.code ?? 'generation_failed';
      await _finalizeFailure(run, code);
      unawaited(processRun.cleanUp());
      return _fail(run, ListenGenProcessFailure(code));
    }

    final packagePath = awaited.packageSha256 == null
        ? null
        : await processRun.packagePath.catchError(
            (Object error) => throw error,
          );
    if (packagePath == null) {
      await _finalizeFailure(run, 'generator_plan_was_empty');
      unawaited(processRun.cleanUp());
      return _fail(run, const ListenGenProcessFailure('generator_plan_was_empty'));
    }

    // Candidate-only installation, then explicit adoption. The produced
    // carrier is Core-owned from here on: adopted content resolves through
    // Core's composition interface, never through an app-side retained copy.
    run.phase = CapabilityRunPhase.installing;
    _emit();
    final LearningEdition installed;
    try {
      installed = await _repository.installPackage(material.material.id, packagePath);
    } on Object catch (error) {
      await _finalizeFailure(run, _stableCode(error));
      unawaited(processRun.cleanUp());
      return _fail(run, error);
    }
    run.phase = CapabilityRunPhase.adopting;
    _emit();
    final LearningEdition adopted;
    try {
      adopted = await _repository.adoptEdition(material.material.id, installed.releaseId);
    } on Object catch (error) {
      await _finalizeFailure(run, _stableCode(error));
      unawaited(processRun.cleanUp());
      return _fail(run, error);
    }
    try {
      await _repository.finalizeAttempt(
        materialId: material.material.id,
        attemptId: attempt.attemptId,
        succeeded: true,
        toolId: generatorToolId,
        toolVersion: generatorToolVersion,
      );
    } on Object catch (_) {
      // The composition is adopted and durable; a failed finalize note does
      // not un-adopt it, and the projection stays honest via the adopted
      // composition itself.
    }
    run.phase = CapabilityRunPhase.completed;
    run.producedPackageSha256 = awaited.packageSha256;
    _emit();
    unawaited(processRun.cleanUp());
    return CapabilityAvailable(edition: adopted);
  }

  /// The language the generation must produce: the exact language of the
  /// source document when one is known. A material with no language fact
  /// declares `und` (undetermined) — never a guessed learner surface
  /// language — and the generators decide from the content itself.
  static String _targetLanguageFor(MaterialDetails material) {
    for (final rendition in material.currentRevision.documentRenditions) {
      final language = rendition.language;
      if (language != null && language.isNotEmpty) return language;
    }
    return 'und';
  }

  static List<String> _noProviderArguments() => const [];

  Future<void> _finalizeFailure(_CapabilityRun run, String reason) async {
    final attemptId = run.attemptId;
    if (attemptId == null) return;
    try {
      await _repository.finalizeAttempt(
        materialId: run.materialId,
        attemptId: attemptId,
        succeeded: false,
        failureReason: reason,
      );
    } on Object catch (_) {
      // The attempt note is best-effort; the run failure is already visible
      // in the session and the projection derives from the attempt record.
    }
  }

  /// Runs [action], mapping every failure into the run state. Returns null
  /// when the action failed.
  Future<T?> _guard<T>(_CapabilityRun run, Future<T> Function() action) async {
    try {
      return await action();
    } on Object catch (error) {
      run.phase = CapabilityRunPhase.failed;
      run.failure = _friendly(error);
      _emit();
      return null;
    }
  }

  CapabilityOutcome _fail(_CapabilityRun run, Object error) {
    run.phase = CapabilityRunPhase.failed;
    run.failure = _friendly(error);
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
    if (error is ApiFailure) return error.code ?? 'request_failed';
    return 'unexpected_error';
  }

  static String _friendly(Object error) {
    if (error is ListenGenProcessFailure) return error.message ?? error.code;
    if (error is ApiFailure) return error.code ?? 'request_failed';
    // The UI never speaks raw exception text; an unnamed failure degrades to
    // the stable code instead of leaking the error into a sentence.
    return 'unexpected_error';
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
    MaterialDetails material,
    MaterialCapability capability,
  ) {
    for (final edition in editions) {
      if (_editionSatisfies(edition, material, capability)) return edition;
    }
    return null;
  }

  bool _editionSatisfies(
    LearningEdition edition,
    MaterialDetails material,
    MaterialCapability capability,
  ) {
    switch (capability) {
      case MaterialCapability.read:
        return edition.providesRead;
      case MaterialCapability.listen:
        if (!edition.hasAvailableMediaRendition) return false;
        return _materialHasMediaKind(material, MediaRenditionKind.audio);
      case MaterialCapability.watch:
        if (!edition.hasAvailableMediaRendition) return false;
        return _materialHasMediaKind(material, MediaRenditionKind.video);
      case MaterialCapability.synchronizedReadListen:
        return edition.providesSynchronizedReadListen;
    }
  }

  static bool _materialHasMediaKind(
    MaterialDetails material,
    MediaRenditionKind kind,
  ) => material.currentRevision.mediaRenditions.any((r) => r.kind == kind);

  void _emit() => notifyListeners();
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
    if (previous != null) {
      previous.replaced = true;
      previous.processRun?.cancel();
    }
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
  CapabilityRunPhase phase = CapabilityRunPhase.resolving;
  String? stage;
  final List<String> warnings = [];
  String? failure;
  String? attemptId;
  String? producedPackageSha256;
  ListenGenProcessRun? processRun;

  CapabilityRunView get view => CapabilityRunView(
    materialId: materialId,
    capability: capability,
    phase: phase,
    stage: stage,
    warnings: List.unmodifiable(warnings),
    failureCode: failure,
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
final class _UnresolvingCapabilityFileResolver implements CapabilityFileResolver {
  const _UnresolvingCapabilityFileResolver();

  @override
  Future<String?> documentSourcePath(
    DocumentRendition rendition,
    SourceAsset? sourceAsset,
  ) async => null;

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
