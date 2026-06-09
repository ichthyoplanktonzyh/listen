import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class DesktopPlayerAdapter {
  DesktopPlayerAdapter() : player = Player() {
    videoController = VideoController(player);
  }

  final Player player;
  late final VideoController videoController;

  Stream<Duration> get position => player.stream.position;
  Stream<Duration> get duration => player.stream.duration;
  Stream<bool> get playing => player.stream.playing;
  Stream<String> get errors => player.stream.error;
  Stream<Tracks> get tracks => player.stream.tracks;
  Duration get currentPosition => player.state.position;

  Future<void> open(String path) => player.open(Media(path));
  Future<void> playOrPause() => player.playOrPause();
  Future<void> stop() => player.stop();
  Future<void> seek(Duration position) => player.seek(position);
  Future<void> setRate(double rate) => player.setRate(rate);
  Future<void> setVolume(double volume) => player.setVolume(volume);
  Future<void> selectAudio(AudioTrack track) => player.setAudioTrack(track);
  Future<void> selectSubtitle(SubtitleTrack track) =>
      player.setSubtitleTrack(track);

  Future<void> dispose() => player.dispose();
}
