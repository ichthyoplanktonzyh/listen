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

class OnlineMediaDownload {
  OnlineMediaDownload(this._process) {
    _finish();
  }

  final Process _process;
  final _progress = StreamController<double>.broadcast();
  final _result = Completer<String?>();
  String? _outputPath;
  String _lastError = '';
  bool _cancelled = false;

  Stream<double> get progress => _progress.stream;
  Future<String?> get completed => _result.future;

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
