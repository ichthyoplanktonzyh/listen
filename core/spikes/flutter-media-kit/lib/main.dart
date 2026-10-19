import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

const sampleVideo =
    '/Users/shadow/LLPlayerNext/testdata/generated/sample-video.mp4';
const sampleAudio =
    '/Users/shadow/LLPlayerNext/testdata/generated/sample-audio.m4a';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const M0App());
}

class M0App extends StatelessWidget {
  const M0App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const PlayerSpike(),
    );
  }
}

class PlayerSpike extends StatefulWidget {
  const PlayerSpike({super.key});

  @override
  State<PlayerSpike> createState() => _PlayerSpikeState();
}

class _PlayerSpikeState extends State<PlayerSpike> {
  static const diagnosticsPath = '/tmp/llplayernext-flutter-m0.log';
  late final Player player = Player();
  late final VideoController controller = VideoController(player);
  late final StreamSubscription<Duration> positionSubscription;
  late final StreamSubscription<Tracks> tracksSubscription;
  late final StreamSubscription<String> errorSubscription;
  final timers = <Timer>[];
  bool looping = false;
  String message = 'media_kit ready';
  int lastLoggedSecond = -1;

  @override
  void initState() {
    super.initState();
    File(diagnosticsPath).writeAsStringSync('flutter-media-kit M0 started\n');
    positionSubscription = player.stream.position.listen((position) {
      if (position.inSeconds != lastLoggedSecond) {
        lastLoggedSecond = position.inSeconds;
        _log('positionMs=${position.inMilliseconds}');
      }
      if (looping &&
          (position < const Duration(seconds: 3) ||
              position >= const Duration(milliseconds: 4800))) {
        _log('loopSeekMs=3000');
        player.seek(const Duration(seconds: 3));
      }
    });
    tracksSubscription = player.stream.tracks.listen((tracks) {
      _log(
        'tracks=${tracks.audio.length + tracks.video.length + tracks.subtitle.length}',
      );
    });
    errorSubscription = player.stream.error.listen((error) => _log('error=$error'));
    unawaited(open(sampleVideo));
    timers.add(Timer(const Duration(seconds: 2), overlaySeek));
    timers.add(Timer(const Duration(seconds: 5), toggleLoop));
    timers.add(Timer(const Duration(seconds: 9), () async {
      await toggleLoop();
      await open(sampleAudio);
    }));
  }

  Future<void> open(String path) async {
    _log('open=$path');
    setState(() => message = 'Opening ${path.split('/').last}');
    await player.open(Media(path));
    _log('opened=$path');
    setState(() => message = 'Playing ${path.split('/').last}');
  }

  Future<void> toggleLoop() async {
    setState(() => looping = !looping);
    _log('looping=$looping');
    if (looping) await player.seek(const Duration(seconds: 3));
  }

  void overlaySeek() {
    _log('overlayClickSeekMs=3000');
    player.seek(const Duration(seconds: 3));
  }

  @override
  void dispose() {
    positionSubscription.cancel();
    tracksSubscription.cancel();
    errorSubscription.cancel();
    for (final timer in timers) {
      timer.cancel();
    }
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black,
                    child: Video(controller: controller, controls: NoVideoControls),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: FilledButton.tonal(
                    onPressed: () {
                      overlaySeek();
                    },
                    child: const Text(
                      "I can't re-enter. Click this subtitle to seek.",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            color: const Color(0xff14161d),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Flutter + media_kit M0',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(message, style: const TextStyle(color: Color(0xff98d8ff))),
                const SizedBox(height: 6),
                StreamBuilder<Duration>(
                  stream: player.stream.position,
                  initialData: Duration.zero,
                  builder: (context, position) => StreamBuilder<Duration>(
                    stream: player.stream.duration,
                    initialData: Duration.zero,
                    builder: (context, duration) => Text(
                      '${_seconds(position.data)} / ${_seconds(duration.data)} | '
                      '${_trackCount()} tracks | loop ${looping ? 'on' : 'off'}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => open(sampleVideo),
                      child: const Text('Open video'),
                    ),
                    FilledButton(
                      onPressed: () => open(sampleAudio),
                      child: const Text('Open audio'),
                    ),
                    FilledButton(
                      onPressed: player.playOrPause,
                      child: const Text('Play / pause'),
                    ),
                    FilledButton(onPressed: player.stop, child: const Text('Stop')),
                    FilledButton(
                      onPressed: () => player.seek(
                        player.state.position + const Duration(seconds: 1),
                      ),
                      child: const Text('+1s'),
                    ),
                    FilledButton(
                      onPressed: () => player.seek(
                        player.state.position - const Duration(seconds: 1),
                      ),
                      child: const Text('-1s'),
                    ),
                    FilledButton(
                      onPressed: () => player.setRate(0.75),
                      child: const Text('0.75x'),
                    ),
                    FilledButton(
                      onPressed: () => player.setRate(1),
                      child: const Text('1x'),
                    ),
                    FilledButton(
                      onPressed: () => player.setVolume(50),
                      child: const Text('Volume 50%'),
                    ),
                    FilledButton(
                      onPressed: toggleLoop,
                      child: const Text('Toggle cue loop'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _seconds(Duration? duration) =>
      '${((duration ?? Duration.zero).inMilliseconds / 1000).toStringAsFixed(2)}s';

  int _trackCount() {
    final tracks = player.state.tracks;
    return tracks.audio.length + tracks.video.length + tracks.subtitle.length;
  }

  void _log(String line) {
    File(diagnosticsPath).writeAsStringSync(
      '${DateTime.now().toIso8601String()} $line\n',
      mode: FileMode.append,
    );
  }
}
