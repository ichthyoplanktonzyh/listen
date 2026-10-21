import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/realtime_recording.dart';

abstract interface class RealtimeAudioSession {
  Stream<Uint8List> get pcmInput;

  Future<void> start({required int inputSampleRateHz});
  Future<void> beginTurn(String turnId, {int? audioStartMs});
  Future<CapturedRecording> endTurn();
  Future<void> discardTurn();
  Future<void> play(Uint8List pcm);
  Future<void> stopPlayback();
  Future<void> shutdown();
  Future<CapturedRecording> stop();
  Future<void> cancel();
}

class RealtimeAudioBridge implements RealtimeAudioSession {
  RealtimeAudioBridge({
    MethodChannel? methods,
    EventChannel? input,
    this.recordingsDirectory,
  }) : _methods =
           methods ?? const MethodChannel('app.llplayernext/realtime_audio'),
       _input =
           input ?? const EventChannel('app.llplayernext/realtime_audio_input');

  final MethodChannel _methods;
  final EventChannel _input;
  final Directory? recordingsDirectory;
  String? _path;
  String? _turnPath;
  int _startGeneration = 0;
  Future<void>? _startInFlight;

  @override
  Stream<Uint8List> get pcmInput =>
      _input.receiveBroadcastStream().map((value) => value as Uint8List);

  @override
  Future<void> start({required int inputSampleRateHz}) async {
    final home = Platform.environment['HOME'];
    if (recordingsDirectory == null && (!Platform.isMacOS || home == null)) {
      throw const FileSystemException('Realtime audio requires macOS.');
    }
    final generation = ++_startGeneration;
    final directory =
        recordingsDirectory ??
        Directory(
          p.join(home!, 'Library/Application Support/LLPlayerNext/recordings'),
        );
    await directory.create(recursive: true);
    if (generation != _startGeneration) return;
    final path = p.join(
      directory.path,
      'realtime-${DateTime.now().microsecondsSinceEpoch}.wav',
    );
    _path = path;
    final operation = _startCapture(
      generation: generation,
      path: path,
      inputSampleRateHz: inputSampleRateHz,
    );
    _startInFlight = operation;
    try {
      await operation;
    } catch (_) {
      if (generation == _startGeneration) _path = null;
      rethrow;
    } finally {
      if (identical(_startInFlight, operation)) _startInFlight = null;
    }
  }

  Future<void> _startCapture({
    required int generation,
    required String path,
    required int inputSampleRateHz,
  }) async {
    final granted =
        await _methods.invokeMethod<bool>('requestPermission') ?? false;
    if (generation != _startGeneration) return;
    if (!granted) {
      throw PlatformException(
        code: 'microphone_permission',
        message:
            'Microphone permission was denied. Enable it in System Settings.',
      );
    }
    await _methods.invokeMethod<bool>('start', {
      'path': path,
      'inputSampleRateHz': inputSampleRateHz,
    });
  }

  @override
  Future<void> beginTurn(String turnId, {int? audioStartMs}) async {
    final directory = _captureDirectory();
    if (_path == null || directory == null) {
      throw const FileSystemException('Realtime audio session is not active.');
    }
    final safeId = turnId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    _turnPath = p.join(directory.path, '$safeId.wav');
    await _methods.invokeMethod<bool>('beginTurn', {
      'path': _turnPath,
      'audioStartMs': audioStartMs,
    });
  }

  @override
  Future<CapturedRecording> endTurn() async {
    final result = await _methods.invokeMapMethod<String, Object?>('endTurn');
    final path = result?['path'] as String? ?? _turnPath;
    final duration = result?['durationMs'] as int? ?? 0;
    _turnPath = null;
    if (path == null) {
      throw const FileSystemException(
        'Realtime turn recorder returned no file.',
      );
    }
    return _readCapture(path, duration, 'Realtime turn recorder');
  }

  @override
  Future<void> discardTurn() async {
    if (_turnPath == null) return;
    await _methods.invokeMethod<bool>('discardTurn');
    _turnPath = null;
  }

  @override
  Future<void> play(Uint8List pcm) =>
      _methods.invokeMethod<bool>('playPcm', pcm);

  @override
  Future<void> stopPlayback() => _methods.invokeMethod<bool>('stopPlayback');

  @override
  Future<void> shutdown() async {
    ++_startGeneration;
    await _awaitPendingStart();
    await _methods.invokeMethod<bool>('shutdown');
    _path = null;
    _turnPath = null;
  }

  @override
  Future<CapturedRecording> stop() async {
    final result = await _methods.invokeMapMethod<String, Object?>('stop');
    final path = result?['path'] as String? ?? _path;
    final duration = result?['durationMs'] as int? ?? 0;
    _path = null;
    _turnPath = null;
    if (path == null) {
      throw const FileSystemException('Realtime recorder returned no file.');
    }
    return _readCapture(path, duration, 'Realtime recorder');
  }

  @override
  Future<void> cancel() async {
    ++_startGeneration;
    await _awaitPendingStart();
    final hadSession = _path != null;
    _path = null;
    _turnPath = null;
    if (hadSession) await _methods.invokeMethod<bool>('cancel');
  }

  Future<void> _awaitPendingStart() async {
    final pending = _startInFlight;
    if (pending == null) return;
    try {
      await pending;
    } catch (_) {
      // Start reports its own error; cleanup still releases partial capture.
    }
  }

  Directory? _captureDirectory() {
    final injected = recordingsDirectory;
    if (injected != null) return injected;
    final home = Platform.environment['HOME'];
    if (!Platform.isMacOS || home == null) return null;
    return Directory(
      p.join(home, 'Library/Application Support/LLPlayerNext/recordings'),
    );
  }

  Future<CapturedRecording> _readCapture(
    String path,
    int duration,
    String description,
  ) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (duration <= 0 || bytes.isEmpty) {
        throw FileSystemException('$description produced empty audio.', path);
      }
      return CapturedRecording(
        path: path,
        durationMs: duration,
        byteLength: bytes.length,
        contentSha256: sha256.convert(bytes).toString(),
      );
    } catch (_) {
      try {
        await File(path).delete();
      } on FileSystemException {
        // Native or prior cleanup may already have removed the recording.
      }
      rethrow;
    }
  }
}
