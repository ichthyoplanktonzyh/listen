import 'dart:async';
import 'dart:convert';
import 'dart:io';

class EmbeddedSubtitle {
  const EmbeddedSubtitle({
    required this.ordinal,
    required this.codec,
    required this.title,
    required this.language,
    required this.isText,
  });

  final int ordinal;
  final String codec;
  final String? title;
  final String? language;
  final bool isText;

  String get label {
    final name = title ?? language ?? 'Subtitle ${ordinal + 1}';
    return '$name ($codec${isText ? '' : ', bitmap'})';
  }
}

class ExternalTools {
  ExternalTools({
    this.ffmpegPath = '',
    this.ffprobePath = '',
    this.ytDlpPath = '',
  });

  final String ffmpegPath;
  final String ffprobePath;
  final String ytDlpPath;

  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath) async {
    final executable = await _resolve(ffprobePath, 'ffprobe');
    final result = await _run(executable, [
      '-v',
      'error',
      '-select_streams',
      's',
      '-show_entries',
      'stream=codec_name:stream_tags=language,title',
      '-of',
      'json',
      mediaPath,
    ]);
    final streams =
        (jsonDecode(result) as Map<String, dynamic>)['streams']
            as List<dynamic>;
    return streams.indexed
        .map((entry) {
          final stream = entry.$2 as Map<String, dynamic>;
          final codec = stream['codec_name'] as String? ?? 'unknown';
          final tags = stream['tags'] as Map<String, dynamic>? ?? const {};
          return EmbeddedSubtitle(
            ordinal: entry.$1,
            codec: codec,
            title: tags['title'] as String?,
            language: tags['language'] as String?,
            isText: _textSubtitleCodecs.contains(codec),
          );
        })
        .toList(growable: false);
  }

  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  ) async {
    if (!subtitle.isText) {
      throw ExternalToolError(
        '${subtitle.codec} is a bitmap subtitle and cannot be made interactive yet.',
      );
    }
    final executable = await _resolve(ffmpegPath, 'ffmpeg');
    final directory = Directory(
      '${Platform.environment['HOME']}/Library/Caches/LLPlayerNext/subtitles',
    );
    await directory.create(recursive: true);
    final output =
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}-${subtitle.ordinal}.srt';
    await _run(executable, [
      '-v',
      'error',
      '-y',
      '-i',
      mediaPath,
      '-map',
      '0:s:${subtitle.ordinal}',
      output,
    ], timeout: const Duration(minutes: 2));
    final extracted = File(output);
    if (!await extracted.exists() || await extracted.length() == 0) {
      throw const ExternalToolError(
        'ffmpeg completed without producing a text subtitle.',
      );
    }
    return output;
  }

  Future<String> resolveOnlineMedia(String pageUrl) async {
    final executable = await _resolve(ytDlpPath, 'yt-dlp');
    final result = await _run(executable, [
      '--no-playlist',
      '--no-warnings',
      '--get-url',
      '--format',
      'best',
      pageUrl,
    ], timeout: const Duration(seconds: 45));
    final urls = const LineSplitter()
        .convert(result)
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    if (urls.isEmpty) {
      throw const ExternalToolError('yt-dlp returned no media URL.');
    }
    return urls.first;
  }

  Future<String> _resolve(String configured, String name) async {
    if (configured.isNotEmpty && await File(configured).exists()) {
      return configured;
    }
    for (final candidate in [
      '/opt/homebrew/bin/$name',
      '/usr/local/bin/$name',
      '/usr/bin/$name',
    ]) {
      if (await File(candidate).exists()) return candidate;
    }
    final result = await Process.run('/usr/bin/which', [name]);
    final path = (result.stdout as String).trim();
    if (result.exitCode == 0 && path.isNotEmpty) return path;
    throw ExternalToolError(
      '$name was not found. Install it or configure its path in Settings.',
    );
  }

  Future<String> _run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final process = await Process.start(executable, arguments);
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final timer = Timer(timeout, () => process.kill(ProcessSignal.sigkill));
    final exitCode = await process.exitCode;
    timer.cancel();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    if (exitCode != 0) {
      throw ExternalToolError(
        stderr.trim().isEmpty
            ? '$executable exited with status $exitCode.'
            : stderr.trim(),
      );
    }
    return stdout.trim();
  }

  static const _textSubtitleCodecs = {
    'ass',
    'ssa',
    'subrip',
    'srt',
    'webvtt',
    'mov_text',
    'text',
    'microdvd',
    'jacosub',
    'sami',
    'realtext',
  };
}

class ExternalToolError implements Exception {
  const ExternalToolError(this.message);
  final String message;

  @override
  String toString() => message;
}
