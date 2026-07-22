import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'shadowing_recorder.dart';

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
  RealtimeAudioBridge({MethodChannel? methods, EventChannel? input})
    : _methods =
          methods ?? const MethodChannel('app.llplayernext/realtime_audio'),
      _input =
          input ?? const EventChannel('app.llplayernext/realtime_audio_input');

  final MethodChannel _methods;
  final EventChannel _input;
  String? _path;
  String? _turnPath;

  @override
  Stream<Uint8List> get pcmInput =>
      _input.receiveBroadcastStream().map((value) => value as Uint8List);

  @override
  Future<void> start({required int inputSampleRateHz}) async {
    final home = Platform.environment['HOME'];
    if (!Platform.isMacOS || home == null) {
      throw const FileSystemException('Realtime audio requires macOS.');
    }
    final directory = Directory(
      '$home/Library/Application Support/LLPlayerNext/recordings',
    );
    await directory.create(recursive: true);
    _path =
        '${directory.path}/realtime-${DateTime.now().microsecondsSinceEpoch}.wav';
    final granted =
        await _methods.invokeMethod<bool>('requestPermission') ?? false;
    if (!granted) {
      _path = null;
      throw PlatformException(
        code: 'microphone_permission',
        message:
            'Microphone permission was denied. Enable it in System Settings.',
      );
    }
    await _methods.invokeMethod<bool>('start', {
      'path': _path,
      'inputSampleRateHz': inputSampleRateHz,
    });
  }

  @override
  Future<void> beginTurn(String turnId, {int? audioStartMs}) async {
    final home = Platform.environment['HOME'];
    if (_path == null || home == null) {
      throw const FileSystemException('Realtime audio session is not active.');
    }
    final safeId = turnId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    _turnPath =
        '$home/Library/Application Support/LLPlayerNext/recordings/$safeId.wav';
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
    final bytes = await File(path).readAsBytes();
    if (duration <= 0 || bytes.isEmpty) {
      throw const FileSystemException(
        'Realtime turn recorder produced empty audio.',
      );
    }
    return CapturedRecording(
      path: path,
      durationMs: duration,
      byteLength: bytes.length,
      contentSha256: sha256.convert(bytes).toString(),
    );
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
  Future<void> shutdown() => _methods.invokeMethod<bool>('shutdown');

  @override
  Future<CapturedRecording> stop() async {
    final result = await _methods.invokeMapMethod<String, Object?>('stop');
    final path = result?['path'] as String? ?? _path;
    final duration = result?['durationMs'] as int? ?? 0;
    _path = null;
    if (path == null) {
      throw const FileSystemException('Realtime recorder returned no file.');
    }
    final bytes = await File(path).readAsBytes();
    if (duration <= 0 || bytes.isEmpty) {
      throw const FileSystemException(
        'Realtime recorder produced empty audio.',
      );
    }
    return CapturedRecording(
      path: path,
      durationMs: duration,
      byteLength: bytes.length,
      contentSha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<void> cancel() async {
    if (_path == null) return;
    await _methods.invokeMethod<bool>('cancel');
    _path = null;
    _turnPath = null;
  }
}
