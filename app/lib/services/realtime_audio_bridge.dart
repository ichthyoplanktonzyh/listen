import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'shadowing_recorder.dart';

class RealtimeAudioBridge {
  RealtimeAudioBridge({MethodChannel? methods, EventChannel? input})
    : _methods =
          methods ?? const MethodChannel('app.llplayernext/realtime_audio'),
      _input =
          input ?? const EventChannel('app.llplayernext/realtime_audio_input');

  final MethodChannel _methods;
  final EventChannel _input;
  String? _path;

  Stream<Uint8List> get pcmInput =>
      _input.receiveBroadcastStream().map((value) => value as Uint8List);

  Future<void> start() async {
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
    await _methods.invokeMethod<bool>('start', {'path': _path});
  }

  Future<void> play(Uint8List pcm) =>
      _methods.invokeMethod<bool>('playPcm', pcm);

  Future<void> stopPlayback() => _methods.invokeMethod<bool>('stopPlayback');

  Future<void> shutdown() => _methods.invokeMethod<bool>('shutdown');

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

  Future<void> cancel() async {
    if (_path == null) return;
    await _methods.invokeMethod<bool>('cancel');
    _path = null;
  }
}
