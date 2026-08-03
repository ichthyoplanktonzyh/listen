import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/external_tools.dart';

void main() {
  test('embedded subtitle labels disclose bitmap tracks', () {
    const subtitle = EmbeddedSubtitle(
      ordinal: 1,
      codec: 'hdmv_pgs_subtitle',
      title: 'English signs',
      language: 'eng',
      isText: false,
    );
    expect(subtitle.label, contains('bitmap'));
  });

  test('yt-dlp adapter accepts a configured executable', () async {
    final directory = await Directory.systemTemp.createTemp('llplayer-tools');
    addTearDown(() => directory.delete(recursive: true));
    final executable = File(
      '${directory.path}/yt-dlp',
    )..writeAsStringSync('#!/bin/sh\necho "https://media.example/video.mp4"\n');
    await Process.run('/bin/chmod', ['+x', executable.path]);

    final result = await ExternalTools(
      ytDlpPath: executable.path,
    ).resolveOnlineMedia('https://example.test/watch');

    expect(result, 'https://media.example/video.mp4');
  });

  test('yt-dlp download reports progress and downloaded path', () async {
    final directory = await Directory.systemTemp.createTemp('llplayer-tools');
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/yt-dlp')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'printf "%s\\n" "\$@" > "${directory.path}/arguments.txt"\n'
        'echo "__LLPLAYER_PROGRESS__:42.5%"\n'
        'echo "__LLPLAYER_FILE__:${directory.path}/video.mp4"\n',
      );
    final ffmpeg = File('${directory.path}/ffmpeg')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    await Process.run('/bin/chmod', ['+x', executable.path]);
    await Process.run('/bin/chmod', ['+x', ffmpeg.path]);

    final download = await ExternalTools(
      ytDlpPath: executable.path,
      ffmpegPath: ffmpeg.path,
    ).downloadOnlineMedia('https://example.test/watch', directory.path);
    final progress = <double>[];
    download.progress.listen(progress.add);

    expect(await download.completed, '${directory.path}/video.mp4');
    expect(progress, contains(closeTo(0.425, 0.001)));
    final arguments = await File(
      '${directory.path}/arguments.txt',
    ).readAsLines();
    expect(arguments, containsAllInOrder(['--ffmpeg-location', ffmpeg.path]));
    expect(arguments, containsAllInOrder(['--merge-output-format', 'mp4']));
    expect(
      arguments,
      contains(
        'bestvideo[vcodec^=avc1][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][vcodec^=avc1]/best[ext=mp4]/best',
      ),
    );
  });

  test('yt-dlp download can be cancelled', () async {
    final directory = await Directory.systemTemp.createTemp('llplayer-tools');
    addTearDown(() => directory.delete(recursive: true));
    final executable = File('${directory.path}/yt-dlp')
      ..writeAsStringSync('#!/bin/sh\nexec sleep 30\n');
    final ffmpeg = File('${directory.path}/ffmpeg')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    await Process.run('/bin/chmod', ['+x', executable.path]);
    await Process.run('/bin/chmod', ['+x', ffmpeg.path]);

    final download = await ExternalTools(
      ytDlpPath: executable.path,
      ffmpegPath: ffmpeg.path,
    ).downloadOnlineMedia('https://example.test/watch', directory.path);
    download.cancel();

    await expectLater(
      download.completed,
      throwsA(
        isA<ExternalToolError>().having(
          (value) => value.message,
          'message',
          'Download cancelled.',
        ),
      ),
    );
  });

  test('bitmap subtitle extraction is rejected explicitly', () async {
    const subtitle = EmbeddedSubtitle(
      ordinal: 0,
      codec: 'dvd_subtitle',
      title: null,
      language: null,
      isText: false,
    );

    expect(
      () => ExternalTools().extractTextSubtitle('/tmp/media.mkv', subtitle),
      throwsA(isA<ExternalToolError>()),
    );
  });

  test('media duration probe accepts ffprobe string durations', () async {
    final directory = await Directory.systemTemp.createTemp('llplayer-tools');
    addTearDown(() => directory.delete(recursive: true));
    final ffprobe = File('${directory.path}/ffprobe')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'cat <<\'JSON\'\n'
        '{"format": {"duration": "400.660317"}}\n'
        'JSON\n',
      );
    await Process.run('/bin/chmod', ['+x', ffprobe.path]);

    final result = await ExternalTools(
      ffprobePath: ffprobe.path,
    ).probeMediaDurationMs('/tmp/media.mp4');

    expect(result, 400660);
  });

  test('media duration probe tolerates numeric durations', () async {
    final directory = await Directory.systemTemp.createTemp('llplayer-tools');
    addTearDown(() => directory.delete(recursive: true));
    final ffprobe = File('${directory.path}/ffprobe')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'cat <<\'JSON\'\n'
        '{"format": {"duration": 123.5}}\n'
        'JSON\n',
      );
    await Process.run('/bin/chmod', ['+x', ffprobe.path]);

    final result = await ExternalTools(
      ffprobePath: ffprobe.path,
    ).probeMediaDurationMs('/tmp/media.mp4');

    expect(result, 123500);
  });
}

