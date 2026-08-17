import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'content_generator_setup.dart';

import 'package:crypto/crypto.dart';

import '../models/gen_machine_event.dart';
import 'capability_generation_request.dart';
import 'listen_gen_release_service.dart';

final RegExp _sha256Reference = RegExp(r'^sha256:[0-9a-f]{64}$');

/// Parses one v2 machine event line. Any schema, protocol, tool identity, or
/// shape violation is a protocol failure, not something to trust and continue
/// on.
GenMachineEvent parseListenGenMachineEventV2(
  Map<String, dynamic> json, {
  required String expectedToolVersion,
}) {
  if (json['schema'] != 'listen_gen.machine-event.v2') {
    throw const FormatException('Unsupported listen-gen event schema');
  }
  if (json['protocol_version'] != 2) {
    throw const FormatException('Unsupported listen-gen protocol version');
  }
  final tool = json['tool'];
  if (tool is! Map<String, dynamic> ||
      tool['id'] != 'listen-gen' ||
      tool['version'] != expectedToolVersion) {
    throw const FormatException('Invalid listen-gen tool identity');
  }
  final eventName = json['event'] as String;
  final kind = GenEventKind.values.firstWhere(
    (value) => value.name == eventName,
    orElse: () =>
        throw FormatException('Unsupported listen-gen event type: $eventName'),
  );
  switch (kind) {
    case GenEventKind.protocol:
      if (json['capabilities'] is! Map<String, dynamic>) {
        throw const FormatException('listen-gen protocol capabilities missing');
      }
    case GenEventKind.accepted:
      if (json['attempt_id'] is! String) {
        throw const FormatException('listen-gen accepted attempt id missing');
      }
    case GenEventKind.planned:
      if (json['plan'] is! Map<String, dynamic>) {
        throw const FormatException('listen-gen planned plan missing');
      }
    case GenEventKind.running:
      if (json['stage'] is! String) {
        throw const FormatException('listen-gen running stage missing');
      }
    case GenEventKind.warning:
      if (json['code'] is! String || json['message'] is! String) {
        throw const FormatException('listen-gen warning fields missing');
      }
    case GenEventKind.completed:
      if (json['document_renditions'] is! List<dynamic> ||
          json['media_renditions'] is! List<dynamic> ||
          json['resources'] is! List<dynamic> ||
          json['warnings'] is! List<dynamic>) {
        throw const FormatException('listen-gen completion fields missing');
      }
      final packageSha256 = json['package_sha256'];
      if (packageSha256 != null &&
          (packageSha256 is! String ||
              !_sha256Reference.hasMatch(packageSha256))) {
        throw const FormatException('listen-gen completion digest missing');
      }
    case GenEventKind.failed:
      if (json['code'] is! String || json['message'] is! String) {
        throw const FormatException('listen-gen failure fields missing');
      }
    case GenEventKind.cancelled:
      break;
  }
  return GenMachineEvent(
    sequence: json['sequence'] as int,
    kind: kind,
    attemptId: json['attempt_id'] as String?,
    stage: json['stage'] as String?,
    warningCode: json['code'] as String?,
    warningMessage: json['message'] as String?,
    packageSha256: json['package_sha256'] as String?,
    producedRenditions: [
      ...(json['document_renditions'] as List<dynamic>? ?? const []).map(
        (value) => _validatedSha256((value as Map)['rendition_id']),
      ),
      ...(json['media_renditions'] as List<dynamic>? ?? const []).map(
        (value) => _validatedSha256((value as Map)['rendition_id']),
      ),
    ],
    producedResources: (json['resources'] as List<dynamic>? ?? const [])
        .map((value) => _validatedSha256((value as Map)['resource_id']))
        .toList(growable: false),
    completedWarnings: (json['warnings'] as List<dynamic>? ?? const [])
        .map((value) {
          final map = value as Map;
          return '${map['code']}: ${map['message']}';
        })
        .toList(growable: false),
    code: json['code'] as String?,
    message: json['message'] as String?,
  );
}

String _validatedSha256(Object? value) {
  if (value is! String || !_sha256Reference.hasMatch(value)) {
    throw const FormatException('Invalid SHA-256 reference');
  }
  return value;
}

class ListenGenProcessFailure implements Exception {
  const ListenGenProcessFailure(
    this.code, {
    this.message,
    this.retryable = true,
  });
  final String code;

  /// Human-readable, path-free detail for surfaces that can show it.
  final String? message;

  /// Whether retrying the same request could plausibly succeed. Release
  /// verification failures are integrity/configuration problems — the same
  /// pinned bundle fails identically — so they are not retryable; provider and
  /// process runtime failures keep the default retryable semantics.
  final bool retryable;
}

abstract interface class ListenGenProcessRun {
  Stream<GenMachineEvent> get events;
  Future<String> get packagePath;
  void cancel();
  Future<void> cleanUp();
}

abstract interface class ListenGenProcessService {
  bool get isConfigured;

  /// Which piece is missing, when [isConfigured] is false. "Not configured"
  /// is not an actionable sentence; "no speech model installed" is.
  ContentGeneratorState get state;
  Future<ListenGenProcessRun> start(CapabilityGenerationRequest request);
}

final class LocalListenGenProcessService implements ListenGenProcessService {
  /// The app runs exactly one generator: the pinned release bundle the
  /// [ListenGenReleaseService] verifies byte-for-byte before each run. There is
  /// no executable override — an arbitrary `listen-gen` on the machine is not
  /// something this app is willing to launch.
  LocalListenGenProcessService({
    required this.pythonExecutable,
    ListenGenReleaseService? releaseService,
  }) : _releaseService = releaseService ?? LocalListenGenReleaseService();

  final ListenGenReleaseService _releaseService;
  final String Function() pythonExecutable;

  @override
  bool get isConfigured => _releaseService.isConfigured;

  @override
  ContentGeneratorState get state => isConfigured
      ? ContentGeneratorState.ready
      : ContentGeneratorState.generatorMissing;

  @override
  Future<ListenGenProcessRun> start(CapabilityGenerationRequest request) async {
    if (!isConfigured) {
      throw const ListenGenProcessFailure(
        'generator_not_configured',
        retryable: false,
      );
    }
    final resolvedPython = pythonExecutable();
    if (resolvedPython.isEmpty || !await File(resolvedPython).exists()) {
      throw const ListenGenProcessFailure(
        'generator_python_unavailable',
        retryable: false,
      );
    }
    // Re-verify the pinned bundle on every run. A release failure must abort
    // before any temporary output directory exists or any process is started.
    final verified = await _releaseService.verify();
    final directory = await Directory.systemTemp.createTemp(
      'listen-capability-generation-',
    );
    final outputPath = '${directory.path}/generated.content-package.zip';

    // Freeze the verified bytes into a private copy this run owns, and launch
    // that copy. Between verify() and launch the original file could still be
    // swapped on disk; binding execution to a re-hashed private copy closes
    // that window — we run exactly the bytes we verified, nothing else.
    final String verifiedCopyPath;
    try {
      verifiedCopyPath = await _materializeVerifiedArtifact(
        verified,
        directory,
      );
    } catch (error) {
      await directory.delete(recursive: true);
      // A swapped original, a failed copy, or a copy whose hash no longer
      // matches is an integrity failure, never a transient start failure.
      if (error is ListenGenProcessFailure) rethrow;
      throw const ListenGenProcessFailure(
        'generator_release_artifact_invalid',
        retryable: false,
      );
    }

    // The capability request is caller-owned data: write it next to the run
    // and launch the pinned bundle against that exact document.
    final requestPath = '${directory.path}/capability-request.json';
    String? subtitlePath;
    try {
      await File(
        requestPath,
      ).writeAsString(jsonEncode(request.requestJson), flush: true);
      final subtitle = request.subtitleSrt;
      if (subtitle != null) {
        subtitlePath = '${directory.path}/selected-subtitle.srt';
        await File(subtitlePath).writeAsString(subtitle, flush: true);
      }
    } catch (_) {
      await directory.delete(recursive: true);
      throw const ListenGenProcessFailure('generator_start_failed');
    }

    try {
      // Launch the already-probed Python >=3.11 runtime by absolute path.
      // Finder's PATH resolves python3 to macOS Python 3.9 on supported hosts,
      // which exits before Gen can emit its machine protocol. No shell or
      // second PATH lookup is involved here.
      final process = await Process.start(resolvedPython, [
        verifiedCopyPath,
        'package',
        'from-capability',
        requestPath,
        '--output',
        outputPath,
        '--machine-events',
        ...request.providerArguments,
        if (subtitlePath != null) ...['--subtitle', subtitlePath],
      ]);
      return _LocalListenGenProcessRun(
        process: process,
        directory: directory,
        outputPath: outputPath,
        expectedToolVersion: verified.toolVersion,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      throw const ListenGenProcessFailure('generator_start_failed');
    }
  }

  /// Copies the verified artifact into [directory] and re-hashes the copy
  /// against the verified digest. The launched bytes are therefore the exact
  /// bytes that passed verification, even if the original is swapped in the
  /// meantime. Throws [ListenGenProcessFailure] `generator_release_artifact_invalid`
  /// (non-retryable) when the original cannot be read or the copy's hash does
  /// not match; the caller removes [directory].
  static Future<String> _materializeVerifiedArtifact(
    VerifiedListenGenRelease verified,
    Directory directory,
  ) async {
    const invalid = ListenGenProcessFailure(
      'generator_release_artifact_invalid',
      retryable: false,
    );
    // The launched copy keeps the verified artifact's own filename; the
    // version lives in the committed lock, never hardcoded here.
    final copyPath = '${directory.path}/${verified.artifactFilename}';
    List<int> bytes;
    try {
      bytes = await File(verified.artifactPath).readAsBytes();
      await File(copyPath).writeAsBytes(bytes, flush: true);
      // Hash the copy we are about to run, not the source we just left behind.
      bytes = await File(copyPath).readAsBytes();
    } catch (_) {
      throw invalid;
    }
    if ('sha256:${sha256.convert(bytes)}' != verified.artifactSha256) {
      throw invalid;
    }
    return copyPath;
  }
}

final class _LocalListenGenProcessRun implements ListenGenProcessRun {
  _LocalListenGenProcessRun({
    required this._process,
    required this._directory,
    required this._outputPath,
    required this._expectedToolVersion,
  }) {
    _stdoutDone = _consumeStdout();
    _processDone = _settleProcessSafely();
    // Drain stderr without retaining provider/tool output.
    _process.stderr.listen((_) {});
  }

  final Process _process;
  final Directory _directory;
  final String _outputPath;
  final String _expectedToolVersion;
  final StreamController<GenMachineEvent> _eventController =
      StreamController<GenMachineEvent>();
  final Completer<String> _packagePathCompleter = Completer<String>();
  late final Future<void> _stdoutDone;
  late final Future<void> _processDone;
  bool _cancelled = false;
  int _nextSequence = 0;
  GenEventTerminal? _terminal;
  Object? _protocolFailure;
  Timer? _termTimer;
  Timer? _killTimer;

  Future<void> _consumeStdout() async {
    try {
      await for (final line
          in _process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final event = parseListenGenMachineEventV2(
          jsonDecode(line) as Map<String, dynamic>,
          expectedToolVersion: _expectedToolVersion,
        );
        _validateSequence(event);
        _validateLifecycle(event);
        _eventController.add(event);
      }
    } catch (error) {
      _protocolFailure = error;
      _completeFailure('generator_protocol_invalid');
      _requestTermination();
      _eventController.addError(
        const ListenGenProcessFailure('generator_protocol_invalid'),
      );
    } finally {
      // Do not couple process completion to an optional event subscriber.
      // The controller buffers for a late UI listener; awaiting close here
      // would leave packagePath pending forever when no listener is attached.
      unawaited(_eventController.close());
    }
  }

  void _validateSequence(GenMachineEvent event) {
    if (event.sequence != _nextSequence) {
      throw const FormatException(
        'listen-gen event sequence is not contiguous',
      );
    }
    _nextSequence++;
  }

  // Lifecycle: protocol → accepted → planned → (running|warning)* →
  // terminal, with `failed` also allowed right after `protocol` (the
  // invocation itself was rejected) and after `accepted` (planning failed).
  // Everything after a terminal event is a violation.
  void _validateLifecycle(GenMachineEvent event) {
    switch (event.kind) {
      case GenEventKind.protocol:
        if (event.sequence != 0) {
          throw const FormatException(
            'listen-gen protocol event must be first',
          );
        }
        if (_nextSequence > 1) {
          throw const FormatException('listen-gen protocol event was repeated');
        }
      case GenEventKind.accepted:
        if (_nextSequence <= 1) {
          throw const FormatException(
            'listen-gen accepted must follow protocol',
          );
        }
        if (_terminal != null) {
          throw const FormatException(
            'listen-gen emitted events after terminal',
          );
        }
      case GenEventKind.planned:
        if (_nextSequence <= 2) {
          throw const FormatException(
            'listen-gen planned must follow accepted',
          );
        }
        if (_terminal != null) {
          throw const FormatException(
            'listen-gen emitted events after terminal',
          );
        }
      case GenEventKind.running || GenEventKind.warning:
        if (_nextSequence <= 3) {
          throw const FormatException(
            'listen-gen running/warning must follow planned',
          );
        }
        if (_terminal != null) {
          throw const FormatException(
            'listen-gen emitted events after terminal',
          );
        }
      case GenEventKind.failed:
        // Allowed right after protocol (sequence 1) or later.
        if (_nextSequence < 1) {
          throw const FormatException(
            'listen-gen failed event is out of place',
          );
        }
        if (_terminal != null) {
          throw const FormatException(
            'listen-gen emitted events after terminal',
          );
        }
        _terminal = event.terminal;
      case GenEventKind.completed || GenEventKind.cancelled:
        if (_nextSequence < 2) {
          throw const FormatException(
            'listen-gen terminal event is out of place',
          );
        }
        if (_terminal != null) {
          throw const FormatException(
            'listen-gen emitted events after terminal',
          );
        }
        _terminal = event.terminal;
    }
  }

  @override
  Stream<GenMachineEvent> get events => _eventController.stream;

  @override
  Future<String> get packagePath => _packagePathCompleter.future;

  Future<void> _settleProcessSafely() async {
    try {
      await _settleProcess();
    } catch (_) {
      _completeFailure('generator_output_invalid');
    }
  }

  Future<void> _settleProcess() async {
    final exitCode = await _process.exitCode;
    _termTimer?.cancel();
    _killTimer?.cancel();
    await _stdoutDone;
    if (_packagePathCompleter.isCompleted) return;
    if (_protocolFailure != null) {
      _completeFailure('generator_protocol_invalid');
      return;
    }
    if (_cancelled) {
      _completeFailure('cancelled');
      return;
    }
    final terminal = _terminal;
    if (terminal == null) {
      _completeFailure('generator_terminal_missing');
      return;
    }
    if (terminal.kind == GenEventKind.cancelled) {
      _completeFailure('cancelled');
      return;
    }
    if (terminal.kind == GenEventKind.failed) {
      _completeFailure(terminal.code ?? 'generator_failed', terminal.message);
      return;
    }
    if (terminal.kind != GenEventKind.completed || exitCode != 0) {
      _completeFailure('generator_failed');
      return;
    }
    final expectedDigest = terminal.packageSha256;
    if (expectedDigest == null) {
      // A completed run without a package is an empty plan (the capability
      // was already satisfied by the available resources). The run hands the
      // outcome back without an artifact path; the coordinator treats it as a
      // satisfied result, never as a fabricated package.
      _completeFailure('generator_plan_was_empty');
      return;
    }
    final package = File(_outputPath);
    if (!await package.exists() || await package.length() == 0) {
      _completeFailure('generator_output_missing');
      return;
    }
    final actualDigest =
        'sha256:${await sha256.bind(package.openRead()).first}';
    if (actualDigest != expectedDigest) {
      _completeFailure('generator_package_digest_mismatch');
      return;
    }
    _packagePathCompleter.complete(_outputPath);
  }

  void _completeFailure(String code, [String? message]) {
    if (!_packagePathCompleter.isCompleted) {
      _packagePathCompleter.completeError(
        ListenGenProcessFailure(code, message: message),
      );
    }
  }

  void _requestTermination() {
    _process.kill(ProcessSignal.sigint);
    _termTimer ??= Timer(const Duration(seconds: 2), () {
      _process.kill(ProcessSignal.sigterm);
    });
    _killTimer ??= Timer(const Duration(seconds: 4), () {
      _process.kill(ProcessSignal.sigkill);
    });
  }

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completeFailure('cancelled');
    _requestTermination();
  }

  @override
  Future<void> cleanUp() async {
    // packagePath can fail immediately, but temporary output remains owned by
    // the run until the child process and stdout stream have been reclaimed.
    await _processDone;
    if (await _directory.exists()) await _directory.delete(recursive: true);
  }
}
