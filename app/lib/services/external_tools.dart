import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/embedded_subtitle.dart';
import '../models/media_download.dart';
import '../models/media_resolution.dart';

export '../models/embedded_subtitle.dart';
export '../models/media_resolution.dart';

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

  Future<int?> probeMediaDurationMs(String mediaPath) async {
    try {
      final executable = await _resolve(ffprobePath, 'ffprobe');
      final result = await _run(executable, [
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'json',
        mediaPath,
      ]);
      final format =
          (jsonDecode(result) as Map<String, dynamic>)['format']
              as Map<String, dynamic>?;
      // ffprobe emits the duration as a string ("400.660317") in its JSON
      // output; tolerate numeric values from test fixtures as well.
      final raw = format?['duration'];
      final duration = switch (raw) {
        num value => value.toDouble(),
        String value => double.tryParse(value),
        _ => null,
      };
      return duration == null ? null : (duration * 1000).round();
    } catch (_) {
      return null;
    }
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
      '${Platform.environment['HOME']}/Library/Caches/listen/subtitles',
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

  Future<String> extractPcm16AudioSegment(
    String mediaPath, {
    required int startMs,
    required int endMs,
  }) async {
    if (startMs < 0 || endMs <= startMs) {
      throw const ExternalToolError('Audio segment range is invalid.');
    }
    final executable = await _resolve(ffmpegPath, 'ffmpeg');
    final directory = Directory(
      '${Platform.environment['HOME']}/Library/Caches/LLPlayerNext/shadowing-reference',
    );
    await directory.create(recursive: true);
    final output =
        '${directory.path}/${DateTime.now().microsecondsSinceEpoch}.wav';
    await _run(executable, [
      '-v',
      'error',
      '-y',
      '-ss',
      (startMs / 1000).toStringAsFixed(3),
      '-i',
      mediaPath,
      '-t',
      ((endMs - startMs) / 1000).toStringAsFixed(3),
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'pcm_s16le',
      output,
    ], timeout: const Duration(minutes: 1));
    final file = File(output);
    if (!await file.exists() || await file.length() <= 44) {
      throw const ExternalToolError(
        'ffmpeg completed without producing comparison audio.',
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

  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl) async {
    final executable = await _resolve(ytDlpPath, 'yt-dlp');
    final result = await _run(executable, [
      '--no-playlist',
      '--no-warnings',
      '-J',
      pageUrl,
    ], timeout: const Duration(seconds: 30));
    final data = jsonDecode(result) as Map<String, dynamic>;
    return ResolvedVideoDetails(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? 'YouTube Video',
      description: data['description'] as String? ?? '',
      durationMs: (((data['duration'] as num?)?.toDouble() ?? 0) * 1000)
          .round(),
      viewCount: (data['view_count'] as num?)?.toInt() ?? 0,
      thumbnail: data['thumbnail'] as String?,
      channelId: data['channel_id'] as String? ?? '',
      uploadDate: data['upload_date'] as String? ?? '',
    );
  }

  Future<ResolvedChannelDetails> resolveChannelDetails(
    String channelUrl,
  ) async {
    final executable = await _resolve(ytDlpPath, 'yt-dlp');
    final result = await _run(executable, [
      '--playlist-end',
      '1',
      '--print',
      'channel_id',
      '--print',
      'channel',
      channelUrl,
    ], timeout: const Duration(seconds: 30));
    final lines = const LineSplitter()
        .convert(result)
        .where((line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      throw const ExternalToolError('Could not resolve channel details.');
    }
    return ResolvedChannelDetails(id: lines[0].trim(), name: lines[1].trim());
  }

  Future<OnlineMediaDownload> downloadOnlineMedia(
    String pageUrl,
    String directory,
  ) async {
    final executable = await _resolve(ytDlpPath, 'yt-dlp');
    final ffmpeg = await _resolve(ffmpegPath, 'ffmpeg');
    final process = await Process.start(executable, [
      '--no-playlist',
      '--newline',
      '--no-warnings',
      '--progress',
      '--progress-template',
      'download:__LLPLAYER_PROGRESS__:%(progress._percent_str)s',
      '--print',
      'after_move:__LLPLAYER_FILE__:%(filepath)s',
      '--paths',
      directory,
      '--ffmpeg-location',
      ffmpeg,
      '--output',
      '%(title).200B [%(id)s].%(ext)s',
      '--format',
      'bestvideo[vcodec^=avc1][ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4][vcodec^=avc1]/best[ext=mp4]/best',
      '--merge-output-format',
      'mp4',
      pageUrl,
    ]);
    return OnlineMediaDownload(process);
  }

  Future<String> _resolve(String configured, String name) async {
    if (configured.isNotEmpty && await File(configured).exists()) {
      return configured;
    }
    for (final candidate in [
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/runtime/$name',
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

class OnlineMediaDownload implements MediaDownloadHandle {
  OnlineMediaDownload(this._process) {
    _finish();
  }

  final Process _process;
  final _progress = StreamController<double>.broadcast();
  final _result = Completer<String?>();
  String? _outputPath;
  String _lastError = '';
  bool _cancelled = false;

  @override
  Stream<double> get progress => _progress.stream;
  @override
  Future<String?> get completed => _result.future;

  @override
  void cancel() {
    _cancelled = true;
    _process.kill(ProcessSignal.sigterm);
  }

  Future<void> _finish() async {
    final stdoutFuture = _read(_process.stdout);
    final stderrFuture = _read(_process.stderr);
    final code = await _process.exitCode;
    await Future.wait([stdoutFuture, stderrFuture]);
    if (_cancelled) {
      _result.completeError(const ExternalToolError('Download cancelled.'));
    } else if (code != 0) {
      _result.completeError(
        ExternalToolError(
          _lastError.isEmpty ? 'yt-dlp exited with status $code.' : _lastError,
        ),
      );
    } else if (_outputPath == null) {
      _result.completeError(
        const ExternalToolError('yt-dlp did not report a downloaded file.'),
      );
    } else {
      _result.complete(_outputPath);
    }
    await _progress.close();
  }

  Future<void> _read(Stream<List<int>> source) async {
    await for (final line
        in source.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('__LLPLAYER_PROGRESS__:')) {
        final raw = line
            .substring('__LLPLAYER_PROGRESS__:'.length)
            .replaceAll('%', '')
            .trim();
        final value = double.tryParse(raw);
        if (value != null) _progress.add(value.clamp(0, 100) / 100);
      } else if (line.startsWith('__LLPLAYER_FILE__:')) {
        _outputPath = line.substring('__LLPLAYER_FILE__:'.length).trim();
      } else if (line.trim().isNotEmpty) {
        _lastError = line.trim();
      }
    }
  }
}

class ExternalToolError implements Exception {
  const ExternalToolError(this.message);
  final String message;

  @override
  String toString() => message;
}
