/// The v2 machine protocol exchange with `listen-gen` (slice 3 capability
/// production). Event sequence: `protocol`, `accepted`, `planned`, zero or
/// more `running`/`warning` pairs, then exactly one terminal event
/// (`completed` | `cancelled` | `failed`). `failed` may also follow the
/// `protocol` event directly when the invocation itself is rejected.
enum GenEventKind {
  protocol,
  accepted,
  planned,
  running,
  warning,
  completed,
  cancelled,
  failed,
}

final class GenEventTerminal {
  const GenEventTerminal(
    this.kind, {
    this.code,
    this.message,
    this.packageSha256,
  });
  final GenEventKind kind;
  final String? code;
  final String? message;

  /// `completed` artifact digest (`sha256:` reference), null for an empty
  /// plan.
  final String? packageSha256;
}

/// One parsed machine event, with the fields the event kind carries. Fields
/// not present in an event kind stay null; a malformed event fails parsing
/// instead of degrading a field.
final class GenMachineEvent {
  const GenMachineEvent({
    required this.sequence,
    required this.kind,
    this.attemptId,
    this.stage,
    this.warningCode,
    this.warningMessage,
    this.packageSha256,
    this.producedRenditions = const [],
    this.producedResources = const [],
    this.completedWarnings = const [],
    this.code,
    this.message,
  });

  final int sequence;
  final GenEventKind kind;
  final String? attemptId;

  /// `running` stage label.
  final String? stage;
  final String? warningCode;
  final String? warningMessage;

  /// `completed` artifact digest (`sha256:` reference), null for an empty
  /// plan.
  final String? packageSha256;

  /// `completed` produced rendition ids (`sha256:` references).
  final List<String> producedRenditions;

  /// `completed` produced resource ids (`sha256:` references).
  final List<String> producedResources;

  /// `completed` warnings as `code: message` pairs.
  final List<String> completedWarnings;

  /// `failed` / `cancelled` fields.
  final String? code;
  final String? message;

  GenEventTerminal? get terminal => switch (kind) {
    GenEventKind.completed => GenEventTerminal(
      kind,
      packageSha256: packageSha256,
    ),
    GenEventKind.cancelled ||
    GenEventKind.failed => GenEventTerminal(kind, code: code, message: message),
    _ => null,
  };
}
