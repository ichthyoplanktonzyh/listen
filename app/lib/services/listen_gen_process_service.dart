import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'content_generator_setup.dart';

import 'package:crypto/crypto.dart';

import '../models/content_package.dart';
import 'listen_gen_release_service.dart';

final RegExp _sha256Reference = RegExp(r'^sha256:[0-9a-f]{64}$');

/// [expectedToolVersion] is the version the verified release bundle declares.
/// Binding it here means a machine event stamped by any other build of the
/// tool is a protocol violation, not something to trust and continue on.
ListenGenMachineEvent parseListenGenMachineEvent(
  Map<String, dynamic> json, {
  required String expectedToolVersion,
}) {
  if (json['schema'] != 'listen_gen.machine-event.v1') {
    throw const FormatException('Unsupported listen-gen event schema');
  }
  if (json['protocol_version'] != 1) {
    throw const FormatException('Unsupported listen-gen protocol version');
  }
  final tool = json['tool'];
  if (tool is! Map<String, dynamic> ||
      tool['id'] != 'listen-gen' ||
      tool['version'] != expectedToolVersion) {
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
  const ListenGenProcessFailure(this.code, {
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
  Stream<ListenGenMachineEvent> get events;
  Future<String> get packagePath;
  void cancel();
  Future<void> cleanUp();
}

abstract interface class ListenGenProcessService {
  bool get isConfigured;

  /// Which piece is missing, when [isConfigured] is false. "Not configured"
  /// is not an actionable sentence; "no speech model installed" is.
  ContentGeneratorState get state;
  Future<ListenGenProcessRun> start(ContentPackageGenerationRequest request);
}

final class LocalListenGenProcessService implements ListenGenProcessService {
  /// The app runs exactly one generator: the pinned release bundle the
  /// [ListenGenReleaseService] verifies byte-for-byte before each run. There is
  /// no executable override — an arbitrary `listen-gen` on the machine is not
  /// something this app is willing to launch.
  LocalListenGenProcessService({
    ListenGenReleaseService? releaseService,
    List<String>? providerArgs,
  }) : _releaseService = releaseService ?? LocalListenGenReleaseService(),
       _providerArgs = List.unmodifiable(
         providerArgs ?? _providerArgsFromEnvironment(),
       );

  final ListenGenReleaseService _releaseService;
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
  bool get isConfigured =>
      _releaseService.isConfigured && _providerArgs.isNotEmpty;

  @override
  ContentGeneratorState get state =>
      isConfigured
          ? ContentGeneratorState.ready
          : ContentGeneratorState.generatorMissing;

  @override
  Future<ListenGenProcessRun> start(
    ContentPackageGenerationRequest request,
  ) async {
    if (!isConfigured) {
      throw const ListenGenProcessFailure(
        'generator_not_configured',
        retryable: false,
      );
    }
    // Re-verify the pinned bundle on every run. A release failure must abort
    // before any temporary output directory exists or any process is started.
    final verified = await _releaseService.verify();
    final directory = await Directory.systemTemp.createTemp(
      'listen-package-generation-',
    );
    final outputPath = '${directory.path}/generated.listenpkg';

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

    try {
      // `/usr/bin/env python3 <copy>` matches the zipapp's own
      // `#!/usr/bin/env python3` shebang without depending on an executable
      // bit the copy does not carry. No shell is involved.
      final process = await Process.start('/usr/bin/env', [
        'python3',
        verifiedCopyPath,
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
      _completeFailure(terminal.code ?? 'generator_failed', terminal.message);
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
