import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'macOS realtime audio taps the voice-processed input node output bus',
    () {
      final source = File(
        'macos/Runner/MainFlutterWindow.swift',
      ).readAsStringSync();
      final enable = source.indexOf(
        'try input.setVoiceProcessingEnabled(true)',
      );
      final outputFormat = source.indexOf(
        'let inputFormat = input.outputFormat(forBus: 0)',
      );
      final tap = source.indexOf('input.installTap(onBus: 0');
      final explicitChannelMap = source.indexOf(
        'streamConverter?.channelMap = [0]',
      );
      final monoRecordingConverter = source.indexOf(
        'AVAudioConverter(from: streamFormat, to: fileFormat)',
      );
      final monoRecordingInput = source.indexOf(
        'converted(stream, converter: fileConverter, format: fileFormat)',
      );
      final providerAudioStart = source.indexOf(
        'arguments["audioStartMs"] as? Int',
      );
      final onsetFrame = source.indexOf('audioStartMs * 16');
      final disable = source.indexOf(
        'engine.inputNode.setVoiceProcessingEnabled(false)',
      );

      expect(enable, greaterThanOrEqualTo(0));
      expect(outputFormat, greaterThan(enable));
      expect(tap, greaterThan(outputFormat));
      expect(monoRecordingConverter, greaterThan(outputFormat));
      expect(explicitChannelMap, greaterThan(monoRecordingConverter));
      expect(monoRecordingInput, greaterThan(explicitChannelMap));
      expect(providerAudioStart, greaterThanOrEqualTo(0));
      expect(onsetFrame, greaterThan(providerAudioStart));
      expect(disable, greaterThan(tap));
    },
  );
}
