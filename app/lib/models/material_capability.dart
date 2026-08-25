import 'learning_edition.dart';
import 'learning_material.dart';

/// One capability run's lifecycle view, as the coordinator exposes it to the
/// UI. States are honest: no phase is faked into another.
enum CapabilityRunPhase {
  /// No run and no durable fact: the capability projection decides what to
  /// show next.
  idle,

  /// The coordinator is resolving what already exists (adopted composition,
  /// installed candidates) before deciding whether to produce.
  resolving,

  /// A production run is active: Gen is producing the package.
  generating,

  /// The produced package is being installed (candidate) through Core.
  installing,

  /// The installed candidate is being adopted as the Learning Edition.
  adopting,

  /// Terminal: the capability is satisfied and the composition is adopted.
  completed,

  /// Terminal: the run failed; the durable Core attempt records the failure.
  failed,

  /// Terminal: the run was cancelled.
  cancelled,
}

/// The coordinator's live view of one capability of one material.
class CapabilityRunView {
  const CapabilityRunView({
    required this.materialId,
    required this.capability,
    required this.phase,
    this.stage,
    this.warnings = const [],
    this.failureCode,
    this.failureMessage,
    this.attemptId,
    this.producedPackageSha256,
  });

  final String materialId;
  final MaterialCapability capability;
  final CapabilityRunPhase phase;

  /// Human-stage of the active run (e.g. "transcribing"), when known.
  final String? stage;
  final List<String> warnings;
  final String? failureCode;
  final String? failureMessage;
  final String? attemptId;
  final String? producedPackageSha256;

  bool get busy => switch (phase) {
    CapabilityRunPhase.resolving ||
    CapabilityRunPhase.generating ||
    CapabilityRunPhase.installing ||
    CapabilityRunPhase.adopting => true,
    _ => false,
  };

  bool get terminal => switch (phase) {
    CapabilityRunPhase.completed ||
    CapabilityRunPhase.failed ||
    CapabilityRunPhase.cancelled => true,
    _ => false,
  };
}

/// Whether a [CapabilityRunPhase] has settled and can no longer change.
extension CapabilityRunPhaseTerminal on CapabilityRunPhase {
  bool get terminal => switch (this) {
    CapabilityRunPhase.completed ||
    CapabilityRunPhase.failed ||
    CapabilityRunPhase.cancelled => true,
    _ => false,
  };
}

/// Result of one requested capability, after resolution and (when needed)
/// production.
sealed class CapabilityOutcome {
  const CapabilityOutcome();
}

/// The capability is available from the adopted composition.
final class CapabilityAvailable extends CapabilityOutcome {
  const CapabilityAvailable({this.edition});
  final LearningEdition? edition;
}

/// The capability cannot be produced for this material (structural fact).
final class CapabilityUnavailable extends CapabilityOutcome {
  const CapabilityUnavailable({this.reason});
  final String? reason;
}

/// The capability could not be produced; the durable Core attempt records the
/// failure and the projection shows `failed_attempt`.
final class CapabilityFailed extends CapabilityOutcome {
  const CapabilityFailed({required this.error, this.retryable = true});
  final Object error;
  final bool retryable;
}

/// The run was superseded by a newer request (latest-request-wins); its
/// results were dropped.
final class CapabilityReplaced extends CapabilityOutcome {
  const CapabilityReplaced();
}

/// The run was cancelled by the learner; the attempt records `cancelled`.
final class CapabilityCancelled extends CapabilityOutcome {
  const CapabilityCancelled();
}
