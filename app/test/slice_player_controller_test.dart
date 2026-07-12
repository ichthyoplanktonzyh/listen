import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:video_player/video_player.dart';

class _FakeSlicePlaybackAdapter implements SlicePlaybackAdapter {
  Duration currentPosition = Duration.zero;
  bool playing = false;
  bool disposed = false;
  final seeks = <Duration>[];

  @override
  VideoPlayerController? get videoController => null;
  @override
  bool get isPlaying => playing;
  @override
  Future<Duration?> readPosition() async => currentPosition;
  @override
  Future<void> dispose() async => disposed = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> seek(Duration position) async {
    currentPosition = position;
    seeks.add(position);
  }

  @override
  Future<void> setRate(double rate) async {}
}

Map<String, dynamic> _occurrence() => {
  'original_form': 'approval',
  'media_title_snapshot': 'source.mp4',
  'sentence_text_snapshot': 'Great, I have approval for 7 million.',
  'start_ms_snapshot': 2000,
  'end_ms_snapshot': 5000,
};

void main() {
  test(
    'opens a separate adapter at the source range and disposes it on close',
    () async {
      final adapter = _FakeSlicePlaybackAdapter();
      final controller = SlicePlayerController(
        createAdapter: (_) async => adapter,
      );

      await controller.open(
        path: '/media/source.mp4',
        occurrence: _occurrence(),
      );

      expect(controller.state.open, isTrue);
      expect(controller.state.loading, isFalse);
      expect(controller.state.playing, isTrue);
      expect(controller.state.start, const Duration(seconds: 2));
      expect(controller.state.end, const Duration(seconds: 5));
      expect(adapter.seeks, [const Duration(seconds: 2)]);
      await controller.close();
      expect(adapter.disposed, isTrue);
      expect(controller.state.open, isFalse);
      controller.dispose();
    },
  );

  test(
    'loops at the end of the range and pauses when loop is disabled',
    () async {
      final adapter = _FakeSlicePlaybackAdapter();
      final controller = SlicePlayerController(
        createAdapter: (_) async => adapter,
      );
      await controller.open(
        path: '/media/source.mp4',
        occurrence: _occurrence(),
      );

      adapter.currentPosition = const Duration(seconds: 5);
      await controller.pollNow();
      expect(adapter.currentPosition, const Duration(seconds: 2));
      expect(adapter.playing, isTrue);

      controller.toggleLooping();
      adapter.currentPosition = const Duration(seconds: 5);
      await controller.pollNow();
      expect(adapter.playing, isFalse);
      expect(controller.state.playing, isFalse);
      controller.dispose();
    },
  );
}
