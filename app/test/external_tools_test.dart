import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/external_tools.dart';

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
}
