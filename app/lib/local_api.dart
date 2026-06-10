import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class LocalApi {
  LocalApi._(
    this.baseUrl,
    this.token,
    this._process,
    this.logPath,
    this._logSink,
  );

  final String baseUrl;
  final String token;
  final Process? _process;
  final String? logPath;
  final IOSink? _logSink;
  final HttpClient _client = HttpClient();
  bool _closed = false;

  static Future<LocalApi> connect() async {
    final configuredUrl = Platform.environment['LLPLAYERNEXT_API_URL'];
    final configuredToken = Platform.environment['LLPLAYERNEXT_API_TOKEN'];
    if (configuredUrl != null && configuredToken != null) {
      return LocalApi._(configuredUrl, configuredToken, null, null, null);
    }
    final binary = await _findSidecar();
    final process = await Process.start(binary, const []);
    final lines = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream();
    final line = await lines.first.timeout(const Duration(seconds: 10));
    final handshake = jsonDecode(line) as Map<String, dynamic>;
    if (handshake['event'] != 'api.started') {
      process.kill();
      throw const FormatException('invalid local API handshake');
    }
    final logs = Directory(
      '${Platform.environment['HOME']}/Library/Logs/LLPlayerNext',
    );
    await logs.create(recursive: true);
    final logPath = '${logs.path}/core.log';
    final sink = File(logPath).openWrite(mode: FileMode.append);
    lines.listen(sink.writeln);
    process.stderr.transform(utf8.decoder).listen(sink.write);
    return LocalApi._(
      'http://${handshake['address']}',
      handshake['token'] as String,
      process,
      logPath,
      sink,
    );
  }

  static Future<String> _findSidecar() async {
    final configured = Platform.environment['LLPLAYERNEXT_API_BINARY'];
    final candidates = <String>[
      '${Directory.current.path}/target/release/api-http',
      '${Directory.current.path}/target/debug/api-http',
      '${File(Platform.resolvedExecutable).parent.path}/api-http',
    ];
    if (configured != null) candidates.insert(0, configured);
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    throw StateError(
      'Local API sidecar not found. Build it with cargo build -p api-http.',
    );
  }

  Future<Map<String, dynamic>> registerMedia(String path) async {
    final fingerprint = await fingerprintFile(path);
    return (await _request('POST', '/v1/media', {
          'path': path,
          'fingerprint': fingerprint.toString(),
          'title': path.split(Platform.pathSeparator).last,
          'kind': _isAudio(path) ? 'audio' : 'video',
        }))
        as Map<String, dynamic>;
  }

  Future<String> fingerprintFile(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  Future<Map<String, dynamic>> readMedia(String mediaId) async =>
      (await _request('GET', '/v1/media/${Uri.encodeComponent(mediaId)}'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> importSubtitle(
    String mediaId,
    String path,
  ) async =>
      (await _request('POST', '/v1/media/$mediaId/subtitles', {
            'path': path,
            'language': 'en',
          }))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> readWordProfiles(
    List<String> lemmas,
  ) async {
    final values =
        await _request('POST', '/v1/word-profiles/batch', {
              'language': 'en',
              'lemmas': lemmas,
            })
            as List<dynamic>;
    return values.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> updateWordProfile(
    String lemma,
    String displayForm,
    String? status,
    [Map<String, dynamic>? source]
  ) async =>
      (await _request('PUT', '/v1/word-profiles', {
            'language': 'en',
            'lemma': lemma,
            'display_form': displayForm,
            'status': status,
            'source': source,
          }))
          as Map<String, dynamic>;

  Future<void> createObservation({
    required String wordProfileId,
    required String sentenceId,
    required String originalForm,
    required bool heard,
    Map<String, dynamic>? source,
  }) async {
    await _request('POST', '/v1/word-observations', {
      'word_profile_id': wordProfileId,
      'sentence_id': sentenceId,
      'original_form': originalForm,
      'result': heard ? 'recognized_in_context' : 'not_recognized_in_context',
      'source': source,
    });
  }

  Future<void> clearObservation({
    required String wordProfileId,
    required String sentenceId,
  }) async {
    await _request('POST', '/v1/word-observations', {
      'word_profile_id': wordProfileId,
      'sentence_id': sentenceId,
      'original_form': '',
      'clear': true,
    });
  }

  Future<List<Map<String, dynamic>>> listVocabulary(
    String status, {
    String search = '',
  }) async {
    final values = await _request(
      'GET',
      '/v1/vocabulary?language=en&status=$status&search=${Uri.encodeQueryComponent(search)}&limit=200&offset=0',
    ) as List<dynamic>;
    return values.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> wordDetails(String profileId) async =>
      (await _request('GET', '/v1/word-profiles/$profileId/details'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> exportVocabulary() async =>
      (await _request('GET', '/v1/vocabulary/export')) as Map<String, dynamic>;

  Future<void> importVocabulary(Map<String, dynamic> bundle) async {
    await _request('POST', '/v1/vocabulary/import', bundle);
  }

  Future<void> setMediaAvailability(String mediaId, String availability) async {
    await _request('PUT', '/v1/media/$mediaId/availability', {
      'availability': availability,
    });
  }

  Future<Map<String, dynamic>?> lookupDictionary(String lemma) async =>
      (await _request(
            'GET',
            '/v1/dictionary?language=en&lemma=${Uri.encodeQueryComponent(lemma)}',
          ))
          as Map<String, dynamic>?;

  Future<Map<String, dynamic>> diagnose(String sentenceId) async =>
      (await _request(
            'GET',
            '/v1/sentences/${Uri.encodeComponent(sentenceId)}/diagnosis',
          ))
          as Map<String, dynamic>;

  Stream<Map<String, dynamic>> events() async* {
    while (!_closed) {
      try {
        final request = await _client.getUrl(Uri.parse('$baseUrl/v1/events'));
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('event stream returned ${response.statusCode}');
        }
        yield {
          'version': 1,
          'event': 'service-started',
          'payload': {'resync_required': true},
        };
        await for (final line
            in response
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          if (line.startsWith('data:')) {
            yield jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
          }
        }
      } catch (_) {
        if (!_closed) await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  Future<void> saveProgress(String mediaId, Duration position) async {
    await _request('PUT', '/v1/media/$mediaId/progress', {
      'position_ms': position.inMilliseconds,
    });
  }

  Future<Duration?> readProgress(String mediaId) async {
    final value =
        (await _request('GET', '/v1/media/$mediaId/progress'))
            as Map<String, dynamic>;
    final milliseconds = value['position_ms'] as int?;
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  Future<dynamic> _request(String method, String path, [Object? body]) async {
    final request = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(text, uri: Uri.parse('$baseUrl$path'));
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }

  Future<void> close() async {
    _closed = true;
    _client.close(force: true);
    final process = _process;
    if (process != null) {
      process.kill(ProcessSignal.sigint);
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
    }
    await _logSink?.flush();
    await _logSink?.close();
  }

  static bool _isAudio(String path) {
    final lower = path.toLowerCase();
    return [
      '.m4a',
      '.mp3',
      '.wav',
      '.flac',
      '.aac',
      '.ogg',
    ].any(lower.endsWith);
  }
}
