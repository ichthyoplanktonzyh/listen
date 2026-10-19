import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import '../models/practice.dart';

class CapturedRecording {
  const CapturedRecording({
    required this.path,
    required this.durationMs,
    required this.byteLength,
    required this.contentSha256,
  });

  final String path;
  final int durationMs;
  final int byteLength;
  final String contentSha256;
}

abstract interface class ShadowingRecorder {
  Future<MicrophonePermissionStatus> permissionStatus();
  Future<MicrophonePermissionStatus> requestPermission();
  Future<void> openSettings();
  Future<void> start();
  Future<CapturedRecording> stop();
  Future<void> cancel();
}

class MacosShadowingRecorder implements ShadowingRecorder {
  MacosShadowingRecorder({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'app.llplayernext/shadowing_recorder';
  static const sampleRateHz = 16000;
  final MethodChannel _channel;
  String? _activePath;

  @override
  Future<MicrophonePermissionStatus> permissionStatus() async {
    if (!Platform.isMacOS) return MicrophonePermissionStatus.unavailable;
    return _permission(await _channel.invokeMethod<String>('permissionStatus'));
  }

  @override
  Future<MicrophonePermissionStatus> requestPermission() async {
    if (!Platform.isMacOS) return MicrophonePermissionStatus.unavailable;
    return _permission(
      await _channel.invokeMethod<String>('requestPermission'),
    );
  }

  @override
  Future<void> openSettings() async {
    if (Platform.isMacOS) await _channel.invokeMethod<bool>('openSettings');
  }

  @override
  Future<void> start() async {
    final home = Platform.environment['HOME'];
    if (!Platform.isMacOS || home == null || home.isEmpty) {
      throw const FileSystemException('Shadowing recording requires macOS.');
    }
    final directory = Directory(
      '$home/Library/Application Support/LLPlayerNext/recordings',
    );
    await directory.create(recursive: true);
    final path =
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}.wav';
    await _channel.invokeMethod<bool>('start', {
      'path': path,
      'sampleRateHz': sampleRateHz.toDouble(),
    });
    _activePath = path;
  }

  @override
  Future<CapturedRecording> stop() async {
    final result = await _channel.invokeMapMethod<String, Object?>('stop');
    final path = result?['path'] as String? ?? _activePath;
    final durationMs = result?['durationMs'] as int? ?? 0;
    _activePath = null;
    if (path == null) {
      throw const FileSystemException('Recorder returned no file.');
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    if (durationMs <= 0 || bytes.isEmpty) {
      try {
        await file.delete();
      } on FileSystemException {
        // Preserve the primary empty-recording error below.
      }
      throw const FileSystemException('Recorder produced an empty audio file.');
    }
    return CapturedRecording(
      path: path,
      durationMs: durationMs,
      byteLength: bytes.length,
      contentSha256: sha256.convert(bytes).toString(),
    );
  }

  @override
  Future<void> cancel() async {
    if (_activePath == null) return;
    await _channel.invokeMethod<bool>('cancel');
    _activePath = null;
  }

  MicrophonePermissionStatus _permission(String? raw) => switch (raw) {
    'granted' => MicrophonePermissionStatus.granted,
    'denied' => MicrophonePermissionStatus.denied,
    'restricted' => MicrophonePermissionStatus.restricted,
    'not_determined' => MicrophonePermissionStatus.notDetermined,
    _ => MicrophonePermissionStatus.unavailable,
  };
}
