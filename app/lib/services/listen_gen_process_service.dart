import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/content_package.dart';

final RegExp _sha256Reference = RegExp(r'^sha256:[0-9a-f]{64}$');

ListenGenMachineEvent parseListenGenMachineEvent(Map<String, dynamic> json) {
  if (json['schema'] != 'listen_gen.machine-event.v1') {
    throw const FormatException('Unsupported listen-gen event schema');
  }
  if (json['protocol_version'] != 1) {
    throw const FormatException('Unsupported listen-gen protocol version');
  }
  final tool = json['tool'];
  if (tool is! Map<String, dynamic> ||
      tool['id'] != 'listen-gen' ||
      tool['version'] is! String ||
      (tool['version'] as String).isEmpty) {
    throw const FormatException('Invalid listen-gen tool identity');
  }
  final eventName = json['event'] as String;
  final kind = ListenGenEventKind.values.firstWhere(
    (value) => value.name == eventName,
    orElse: () =>
        throw FormatException('Unsupported listen-gen event type: $eventName'),
  );
  if (kind == ListenGenEventKind.protocol &&
      json['capabilities'] is! Map<String, dynamic>) {
    throw const FormatException('listen-gen protocol capabilities missing');
  }
  if (kind == ListenGenEventKind.completed &&
      (json['package_sha256'] is! String ||
          !_sha256Reference.hasMatch(json['package_sha256'] as String) ||
          json['media_fingerprint'] is! String ||
          !_sha256Reference.hasMatch(json['media_fingerprint'] as String) ||
          json['resources'] is! List<dynamic> ||
          json['warnings'] is! List<dynamic>)) {
    throw const FormatException('listen-gen completion fields missing');
  }
  if (kind == ListenGenEventKind.failed &&
      (json['code'] is! String || json['message'] is! String)) {
    throw const FormatException('listen-gen failure fields missing');
  }
  return ListenGenMachineEvent(
    sequence: json['sequence'] as int,
    kind: kind,
    phase: json['phase'] as String?,
    packageSha256: json['package_sha256'] as String?,
    mediaFingerprint: json['media_fingerprint'] as String?,
    code: json['code'] as String?,
    message: json['message'] as String?,
    resources: (json['resources'] as List<dynamic>? ?? const [])
        .map((value) => _parseListenGenResource(value as Map<String, dynamic>))
        .toList(growable: false),
    warnings: (json['warnings'] as List<dynamic>? ?? const []).cast<String>(),
  );
}

ListenGenResourceView _parseListenGenResource(Map<String, dynamic> json) =>
    ListenGenResourceView(
      resourceId: _validatedSha256(json['resource_id']),
      kind: json['kind'] as String,
      reviewStatus: json['review_status'] as String?,
    );

String _validatedSha256(Object? value) {
  if (value is! String || !_sha256Reference.hasMatch(value)) {
    throw const FormatException('Invalid SHA-256 reference');
  }
  return value;
}

class ListenGenProcessFailure implements Exception {
  const ListenGenProcessFailure(this.code);
  final String code;
}

abstract interface class ListenGenProcessRun {
  Stream<ListenGenMachineEvent> get events;
  Future<String> get packagePath;
  void cancel();
  Future<void> cleanUp();
}

abstract interface class ListenGenProcessService {
  bool get isConfigured;
  Future<ListenGenProcessRun> start(ContentPackageGenerationRequest request);
}

final class LocalListenGenProcessService implements ListenGenProcessService {
  LocalListenGenProcessService({String? executable, List<String>? providerArgs})
    : _executable =
          executable ??
          Platform.environment['LISTEN_GEN_EXECUTABLE'] ??
          'listen-gen',
      _providerArgs = List.unmodifiable(
        providerArgs ?? _providerArgsFromEnvironment(),
      );

  final String _executable;
  final List<String> _providerArgs;

  static List<String> _providerArgsFromEnvironment() {
    final encoded = Platform.environment['LISTEN_GEN_PROVIDER_ARGUMENTS'];
    if (encoded == null || encoded.isEmpty) return const [];
    try {
      final value = jsonDecode(encoded);
      if (value is! List<dynamic> || value.any((item) => item is! String)) {
        return const [];
      }
      return value.cast<String>();
    } catch (_) {
      return const [];
    }
  }

  @override
  bool get isConfigured => _providerArgs.isNotEmpty;

  @override
  Future<ListenGenProcessRun> start(
    ContentPackageGenerationRequest request,
  ) async {
    if (!isConfigured) {
      throw const ListenGenProcessFailure('generator_not_configured');
    }
    final directory = await Directory.systemTemp.createTemp(
      'listen-package-generation-',
    );
    final outputPath = '${directory.path}/generated.listenpkg';
    try {
      final process = await Process.start(_executable, [
        'package',
        'from-media',
        request.mediaPath,
        ..._providerArgs,
        '--title',
        request.title,
        '--media-kind',
        request.mediaKind,
        '--duration-ms',
        '${request.durationMs}',
        '--created-at-ms',
        '${request.createdAtMs}',
        '--output',
        outputPath,
        '--machine-events',
      ]);
      return _LocalListenGenProcessRun(
        process: process,
        directory: directory,
        outputPath: outputPath,
      );
    } catch (_) {
      await directory.delete(recursive: true);
      throw const ListenGenProcessFailure('generator_start_failed');
    }
  }
}

final class _LocalListenGenProcessRun implements ListenGenProcessRun {
  _LocalListenGenProcessRun({
    required this._process,
    required this._directory,
    required this._outputPath,
  }) {
    _stdoutDone = _consumeStdout();
    _processDone = _settleProcessSafely();
    // Drain stderr without retaining provider/tool output.
    _process.stderr.listen((_) {});
  }

  final Process _process;
  final Directory _directory;
  final String _outputPath;
  final StreamController<ListenGenMachineEvent> _eventController =
      StreamController<ListenGenMachineEvent>();
  final Completer<String> _packagePathCompleter = Completer<String>();
  late final Future<void> _stdoutDone;
  late final Future<void> _processDone;
  bool _cancelled = false;
  bool _sawProtocol = false;
  bool _sawStarted = false;
  int _nextSequence = 0;
  ListenGenMachineEvent? _terminal;
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
        final event = parseListenGenMachineEvent(
          jsonDecode(line) as Map<String, dynamic>,
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

  void _validateSequence(ListenGenMachineEvent event) {
    if (event.sequence != _nextSequence) {
      throw const FormatException(
        'listen-gen event sequence is not contiguous',
      );
    }
    _nextSequence++;
  }

  void _validateLifecycle(ListenGenMachineEvent event) {
    if (!_sawProtocol) {
      if (event.kind != ListenGenEventKind.protocol) {
        throw const FormatException('listen-gen protocol event must be first');
      }
      _sawProtocol = true;
      return;
    }
    if (event.kind == ListenGenEventKind.protocol) {
      throw const FormatException('listen-gen protocol event was repeated');
    }
    if (event.kind == ListenGenEventKind.started) {
      if (_sawStarted || _terminal != null) {
        throw const FormatException('invalid listen-gen started event');
      }
      _sawStarted = true;
      return;
    }
    if (!_sawStarted) {
      throw const FormatException('listen-gen started event is missing');
    }
    if (_terminal != null) {
      throw const FormatException('listen-gen emitted events after terminal');
    }
    if (event.kind == ListenGenEventKind.completed ||
        event.kind == ListenGenEventKind.failed ||
        event.kind == ListenGenEventKind.cancelled) {
      _terminal = event;
    }
  }

  @override
  Stream<ListenGenMachineEvent> get events => _eventController.stream;

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
    if (_protocolFailure != null || !_sawProtocol || !_sawStarted) {
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
    if (terminal.kind == ListenGenEventKind.cancelled) {
      _completeFailure('cancelled');
      return;
    }
    if (terminal.kind == ListenGenEventKind.failed) {
      _completeFailure(terminal.code ?? 'generator_failed');
      return;
    }
    if (terminal.kind != ListenGenEventKind.completed || exitCode != 0) {
      _completeFailure('generator_failed');
      return;
    }
    final package = File(_outputPath);
    if (!await package.exists() || await package.length() == 0) {
      _completeFailure('generator_output_missing');
      return;
    }
    final expectedDigest = terminal.packageSha256!;
    final actualDigest =
        'sha256:${await sha256.bind(package.openRead()).first}';
    if (actualDigest != expectedDigest) {
      _completeFailure('generator_package_digest_mismatch');
      return;
    }
    _packagePathCompleter.complete(_outputPath);
  }

  void _completeFailure(String code) {
    if (!_packagePathCompleter.isCompleted) {
      _packagePathCompleter.completeError(ListenGenProcessFailure(code));
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
