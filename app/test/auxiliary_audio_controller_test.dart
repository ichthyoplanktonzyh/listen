import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/data/repositories/speech_synthesis_repository.dart';
import 'package:llplayer_next/services/auxiliary_audio_player.dart';
import 'package:llplayer_next/services/api_service.dart';

class _FakePlayer implements AuxiliaryAudioPlayer {
  _FakePlayer(this.events);

  final List<String> events;

  @override
  Future<void> initialize() async => events.add('initialize');

  @override
  Future<void> play() async => events.add('play');

  @override
  Future<void> pause() async => events.add('pause');

  @override
  Future<void> dispose() async => events.add('dispose');
}

class _FakePlaybackService implements AuxiliaryAudioPlaybackService {
  _FakePlaybackService(this.events);

  final List<String> events;
  Uri? remoteSource;
  String? localPath;

  @override
  AuxiliaryAudioPlayer createLocalFile(String path) {
    localPath = path;
    return _FakePlayer(events);
  }

  @override
  AuxiliaryAudioPlayer createRemote(Uri source) {
    remoteSource = source;
    return _FakePlayer(events);
  }
}

void main() {
  test('synthetic playback acquires focus and exposes provenance', () async {
    final events = <String>[];
    String? requestBody;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'token',
      transport: (method, path, body) async {
        expect(method, 'POST');
        expect(path, '/v1/speech-synthesis');
        requestBody = body;
        return (
          statusCode: 200,
          body: jsonEncode({
            'audio_path': '/tmp/voice.aiff',
            'mime_type': 'audio/aiff',
            'provider_id': 'local-test',
            'provider_version': '1',
            'voice_id': 'voice-en',
            'language': 'en',
            'rate_words_per_minute': 180,
            'purpose': 'writing_readback',
            'content_hash': 'abc',
            'cache_hit': false,
            'synthetic': true,
          }),
        );
      },
    );
    final playback = _FakePlaybackService(events);
    final controller = AuxiliaryAudioController(
      speechRepository: LocalSpeechSynthesisRepository(() => api),
      playbackService: playback,
    );

    final asset = await controller.speak(
      'My own draft.',
      language: 'en',
      purpose: 'writing_readback',
      acquireAudioFocus: () async => events.add('focus'),
    );

    expect(events, ['focus', 'initialize', 'play']);
    expect(asset?.synthetic, isTrue);
    expect(controller.asset?.providerId, 'local-test');
    expect(playback.localPath, '/tmp/voice.aiff');
    expect(jsonDecode(requestBody!), containsPair('text', 'My own draft.'));
    controller.dispose();
  });

  test('a newer request disposes the previous auxiliary player', () async {
    final events = <String>[];
    final playback = _FakePlaybackService(events);
    final controller = AuxiliaryAudioController(playbackService: playback);

    await controller.playRemote(
      'https://example.test/one.mp3',
      acquireAudioFocus: () async => events.add('focus-one'),
    );
    await controller.playRemote(
      'https://example.test/two.mp3',
      acquireAudioFocus: () async => events.add('focus-two'),
    );

    expect(events, [
      'focus-one',
      'initialize',
      'play',
      'focus-two',
      'pause',
      'dispose',
      'initialize',
      'play',
    ]);
    expect(playback.remoteSource, Uri.parse('https://example.test/two.mp3'));
    await controller.stop();
    expect(events.sublist(events.length - 2), ['pause', 'dispose']);
    controller.dispose();
  });
}
