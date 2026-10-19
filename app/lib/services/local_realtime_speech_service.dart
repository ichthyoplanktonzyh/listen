import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LocalRealtimeSpeechException implements Exception {
  const LocalRealtimeSpeechException(this.message);
  final String message;

  @override
  String toString() => 'LocalRealtimeSpeechException: $message';
}

class LocalRealtimeSpeechNotInstalledException
    extends LocalRealtimeSpeechException {
  const LocalRealtimeSpeechNotInstalledException([
    super.message = 'Local Speech-to-Speech environment is not installed.',
  ]);
}

class LocalRealtimeSpeechLaunchException extends LocalRealtimeSpeechException {
  const LocalRealtimeSpeechLaunchException(super.message);
}

abstract interface class LocalRealtimeSpeechService {
  /// Whether the local speech service binary/environment is installed.
  Future<bool> isInstalled();

  /// Whether the local speech service is currently running and ready on loopback.
  Future<bool> isReady();

  /// Start the local speech service if not running, and wait until it's ready.
  Future<void> ensureStarted({
    void Function(String status)? onProgress,
    Duration timeout = const Duration(seconds: 45),
  });

  /// Stop the managed service if it was spawned by this service instance.
  Future<void> stop();

  /// Notify that a conversation is actively using the service.
  void markConversationActive();

  /// Notify that a conversation has ended. Starts idle auto-shutdown timer.
  void markConversationInactive();

  /// Release resources and terminate any managed process.
  void dispose();
}

class DefaultLocalRealtimeSpeechService implements LocalRealtimeSpeechService {
  DefaultLocalRealtimeSpeechService({
    Uri? readinessUri,
    Duration? idleTimeout,
    Future<bool> Function()? isInstalledProbe,
    Future<bool> Function(Uri uri)? readinessProbe,
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    })?
    processStarter,
  }) : readinessUri = readinessUri ?? Uri.parse('http://127.0.0.1:8765/v1/pool'),
       idleTimeout = idleTimeout ?? const Duration(minutes: 10),
       // ignore: prefer_initializing_formals
       _isInstalledProbe = isInstalledProbe,
       // ignore: prefer_initializing_formals
       _readinessProbe = readinessProbe,
       _processStarter = processStarter ?? Process.start;

  final Uri readinessUri;
  final Duration idleTimeout;

  final Future<bool> Function()? _isInstalledProbe;
  final Future<bool> Function(Uri uri)? _readinessProbe;
  final Future<Process> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  })
  _processStarter;

  Process? _managedProcess;
  Timer? _idleTimer;
  bool _isStarting = false;
  Completer<void>? _startCompleter;

  /// Path to the dedicated venv executable.
  static String get venvExecutablePath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.listen/local-speech-venv/bin/speech-to-speech';
  }

  @override
  Future<bool> isInstalled() async {
    if (_isInstalledProbe != null) {
      return _isInstalledProbe();
    }
    final file = File(venvExecutablePath);
    return file.existsSync();
  }

  @override
  Future<bool> isReady() async {
    if (_readinessProbe != null) {
      return _readinessProbe(readinessUri);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client.getUrl(readinessUri);
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<void> ensureStarted({
    void Function(String status)? onProgress,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (await isReady()) {
      markConversationActive();
      return;
    }

    if (_isStarting && _startCompleter != null) {
      return _startCompleter!.future;
    }

    _isStarting = true;
    final completer = Completer<void>();
    _startCompleter = completer;
    completer.future.ignore();

    try {
      if (!await isInstalled()) {
        throw const LocalRealtimeSpeechNotInstalledException();
      }

      onProgress?.call('starting');

      // Spawn process via python3 launcher or dedicated venv executable
      final launcherScript = File('tool/run_local_speech_to_speech.py');
      Process process;
      if (launcherScript.existsSync()) {
        process = await _processStarter(
          'python3',
          ['tool/run_local_speech_to_speech.py'],
        );
      } else {
        process = await _processStarter(venvExecutablePath, [
          '--mode',
          'realtime',
          '--host',
          '127.0.0.1',
          '--port',
          '8765',
          '--mac-optimal-settings',
        ]);
      }
      _managedProcess = process;

      // Handle unexpected process exit
      unawaited(
        process.exitCode.then((code) {
          if (_managedProcess == process) {
            _managedProcess = null;
          }
          if (_isStarting && !completer.isCompleted) {
            completer.completeError(
              LocalRealtimeSpeechLaunchException(
                'Process exited prematurely with code $code',
              ),
            );
          }
        }),
      );

      // Poll for readiness
      final stopwatch = Stopwatch()..start();
      var ready = false;
      while (stopwatch.elapsed < timeout) {
        if (_managedProcess == null) {
          throw const LocalRealtimeSpeechLaunchException(
            'Speech-to-Speech process stopped during startup.',
          );
        }
        ready = await isReady();
        if (ready) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      if (!ready) {
        await stop();
        throw LocalRealtimeSpeechLaunchException(
          'Timed out after ${timeout.inSeconds}s waiting for local speech service.',
        );
      }

      markConversationActive();
      completer.complete();
    } catch (e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
      rethrow;
    } finally {
      _isStarting = false;
      _startCompleter = null;
    }
  }

  @override
  void markConversationActive() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  @override
  void markConversationInactive() {
    _idleTimer?.cancel();
    if (_managedProcess != null) {
      _idleTimer = Timer(idleTimeout, () {
        debugPrint(
          'LocalRealtimeSpeechService: idle timeout reached (${idleTimeout.inMinutes}m); stopping service.',
        );
        stop();
      });
    }
  }

  @override
  Future<void> stop() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    final process = _managedProcess;
    if (process == null) return;
    _managedProcess = null;

    try {
      process.kill(ProcessSignal.sigterm);
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (e) {
      debugPrint('LocalRealtimeSpeechService: error stopping process: $e');
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    stop();
  }
}
