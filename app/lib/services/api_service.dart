import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/practice.dart';

Future<String> computeOpenSubtitlesMovieHash(String path) async {
  final file = File(path);
  final size = await file.length();
  if (size < 131072) {
    throw const FileSystemException(
      'OpenSubtitles hash requires a file of at least 128 KiB',
    );
  }
  final handle = await file.open();
  try {
    var sum = BigInt.from(size);
    for (final offset in [0, size - 65536]) {
      await handle.setPosition(offset);
      final bytes = await handle.read(65536);
      for (var index = 0; index < bytes.length; index += 8) {
        var value = BigInt.zero;
        for (var byte = 0; byte < 8; byte++) {
          value |= BigInt.from(bytes[index + byte]) << (byte * 8);
        }
        sum = (sum + value) & BigInt.parse('ffffffffffffffff', radix: 16);
      }
    }
    return sum.toRadixString(16).padLeft(16, '0');
  } finally {
    await handle.close();
  }
}

/// Raw HTTP exchange result used by the [LocalApi] transport seam.
typedef ApiResponse = ({int statusCode, String body});

/// The pluggable transport behind [LocalApi]. Production uses a `dart:io`
/// [HttpClient]; tests inject a fake so the client can be exercised without a
/// live sidecar (see CONCERNS.md A1).
typedef ApiTransport =
    Future<ApiResponse> Function(String method, String path, String? body);

class LocalApi {
  LocalApi._(
    this.baseUrl,
    this.token,
    this._process,
    this.logPath,
    this._logSink, [
    this._transport,
  ]);

  /// Test-only constructor that drives the API through an injected
  /// [ApiTransport] instead of a live sidecar. See CONCERNS.md A1.
  factory LocalApi.withTransport({
    required String baseUrl,
    required String token,
    required ApiTransport transport,
  }) => LocalApi._(baseUrl, token, null, null, null, transport);

  final String baseUrl;
  final String token;
  final Process? _process;
  final String? logPath;
  final IOSink? _logSink;
  final HttpClient _client = HttpClient();
  final ApiTransport? _transport;
  bool _closed = false;

  static Future<LocalApi> connect() async {
    final configuredUrl = Platform.environment['LLPLAYERNEXT_API_URL'];
    final configuredToken = Platform.environment['LLPLAYERNEXT_API_TOKEN'];
    if (configuredUrl != null && configuredToken != null) {
      return LocalApi._(configuredUrl, configuredToken, null, null, null);
    }
    final binary = await _findSidecar();
    final process = await Process.start(binary, const []);
    try {
      final lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      final line = await lines.first.timeout(const Duration(seconds: 10));
      final handshake = jsonDecode(line) as Map<String, dynamic>;
      if (handshake['event'] != 'api.started') {
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
    } catch (_) {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      rethrow;
    }
  }

  static Future<String> _findSidecar() async {
    final configured = Platform.environment['LLPLAYERNEXT_API_BINARY'];
    final executableDirectory = File(Platform.resolvedExecutable).parent;
    final candidates = <String>['${executableDirectory.path}/api-http'];
    candidates.addAll(sidecarCandidatesFrom(executableDirectory));
    candidates.addAll(sidecarCandidatesFrom(Directory.current.absolute));
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

  /// Imports a subtitle file. When [language] is null the core detects the
  /// learning language from the subtitle script (so a Chinese subtitle is
  /// segmented as Chinese), instead of assuming English.
  Future<Map<String, dynamic>> importSubtitle(
    String mediaId,
    String path, {
    String? language,
  }) async =>
      (await _request('POST', '/v1/media/$mediaId/subtitles', {
            'path': path,
            'language': ?language,
          }))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> mediaSubtitles(String mediaId) async =>
      ((await _request('GET', '/v1/media/$mediaId/subtitles')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> importLLTimeline(
    Map<String, dynamic> document,
  ) async =>
      (await _request('POST', '/v1/lltimeline/import', document))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> importLLTimelineForMedia(
    String mediaId,
    Map<String, dynamic> document, {
    bool allowMismatch = false,
  }) async =>
      (await _request(
            'POST',
            '/v1/media/$mediaId/lltimeline/import?allow_mismatch=$allowMismatch',
            document,
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> readSubtitle(String trackId) async =>
      (await _request('GET', '/v1/subtitles/${Uri.encodeComponent(trackId)}'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archiveSubtitle(String trackId) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> restoreSubtitle(String trackId) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/restore',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> deleteSubtitle(String trackId) async =>
      (await _request(
            'DELETE',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> lookupPronunciation(String word) async =>
      (await _request(
            'GET',
            '/v1/pronunciation/lookup?word=${Uri.encodeQueryComponent(word)}',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> pronunciationProviders() async =>
      ((await _request('GET', '/v1/pronunciation/providers')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> analyzePronunciation(String sentenceId) async =>
      (await _request('POST', '/v1/pronunciation/analyze-sentence', {
            'sentence_id': sentenceId,
          }))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trackPronunciation(String trackId) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/pronunciation',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> trackWordTimings(String trackId) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timings',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> trackWordTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timelines/summary',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> wordTimeline(String timelineId) async =>
      (await _request(
            'GET',
            '/v1/word-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> createTrackWordTimeline(
    String trackId,
    Map<String, dynamic> payload,
  ) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/word-timelines',
            payload,
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> exportTrackLLTimeline(String trackId) async =>
      (await _request(
            'GET',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/lltimeline/export',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> activateWordTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/word-timelines/${Uri.encodeComponent(timelineId)}/activate',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trackChunkTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/chunk-timelines/summary',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> chunkTimeline(String timelineId) async =>
      (await _request(
            'GET',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> generateChunkTimeline(
    String trackId, {
    String status = 'candidate',
  }) async =>
      (await _request(
            'POST',
            '/v1/subtitles/${Uri.encodeComponent(trackId)}/chunk-timelines',
            {'status': status},
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> activateChunkTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}/activate',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archiveChunkTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> deleteChunkTimeline(String timelineId) async =>
      (await _request(
            'DELETE',
            '/v1/chunk-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trackPhoneTimelineSummaries(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/phone-timelines/summary',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> phoneTimeline(String timelineId) async =>
      (await _request(
            'GET',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> activatePhoneTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}/activate',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archivePhoneTimeline(String timelineId) async =>
      (await _request(
            'POST',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> deletePhoneTimeline(String timelineId) async =>
      (await _request(
            'DELETE',
            '/v1/phone-timelines/${Uri.encodeComponent(timelineId)}',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> trackPhoneticAnalyses(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/phonetic-analyses',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> trackChunkPartitions(
    String trackId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/subtitles/${Uri.encodeComponent(trackId)}/chunk-partitions',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> phoneticAnalysisModels() async =>
      ((await _request('GET', '/v1/phonetic-analysis/models')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> phoneticAnalysisProviders() async =>
      ((await _request('GET', '/v1/phonetic-analysis/providers'))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> installPhoneticAnalysisModel(
    String modelId,
  ) async =>
      (await _request('POST', '/v1/phonetic-analysis/models/install', {
            'model_id': modelId,
          }))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> phoneticAnalysisJobs() async =>
      ((await _request('GET', '/v1/phonetic-analysis/jobs')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createPhoneticAnalysisJob({
    required String trackId,
    required String modelId,
    String? sentenceId,
  }) async =>
      (await _request('POST', '/v1/phonetic-analysis/jobs', {
            'track_id': trackId,
            'sentence_id': sentenceId,
            'model_id': modelId,
          }))
          as Map<String, dynamic>;

  Future<String> exportSubtitleSrt(String trackId) async {
    final request = await _client.getUrl(
      Uri.parse(
        '$baseUrl/v1/subtitles/${Uri.encodeComponent(trackId)}/export?format=srt',
      ),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(text);
    }
    return text;
  }

  Future<List<Map<String, dynamic>>> transcriptionProviders() async =>
      ((await _request('GET', '/v1/transcription/providers')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> transcriptionModels() async =>
      ((await _request('GET', '/v1/transcription/models')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<void> installTranscriptionModel(String modelId) async {
    await _request('POST', '/v1/transcription/models/install', {
      'model_id': modelId,
    });
  }

  Future<Map<String, dynamic>> registerCustomTranscriptionModel(
    String path,
  ) async =>
      (await _request('POST', '/v1/transcription/models/register-custom', {
            'path': path,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancelTranscriptionModelInstall(
    String modelId,
  ) async =>
      (await _request(
            'POST',
            '/v1/transcription/models/${Uri.encodeComponent(modelId)}/cancel-install',
          ))
          as Map<String, dynamic>;

  Future<void> deleteTranscriptionModel(String modelId) async {
    await _request(
      'DELETE',
      '/v1/transcription/models/${Uri.encodeComponent(modelId)}',
    );
  }

  Future<List<Map<String, dynamic>>> transcriptionJobs() async =>
      ((await _request('GET', '/v1/transcription/jobs')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> createTranscriptionJob({
    required String mediaId,
    required String modelId,
    required bool secondary,
    required bool translate,
    String? language,
    int? audioTrack,
    bool force = false,
  }) async =>
      (await _request('POST', '/v1/transcription/jobs', {
            'media_id': mediaId,
            'model_id': modelId,
            'destination': secondary ? 'secondary' : 'primary',
            'purpose': translate ? 'translate_to_english' : 'transcribe',
            'language': language,
            'audio_track': audioTrack,
            'force': force,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancelTranscriptionJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/cancel',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> retryTranscriptionJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/retry',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> archiveTranscriptionJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/transcription/jobs/${Uri.encodeComponent(jobId)}/archive',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancelPhoneticAnalysisJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/phonetic-analysis/jobs/${Uri.encodeComponent(jobId)}/cancel',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> retryPhoneticAnalysisJob(String jobId) async =>
      (await _request(
            'POST',
            '/v1/phonetic-analysis/jobs/${Uri.encodeComponent(jobId)}/retry',
          ))
          as Map<String, dynamic>;

  Future<void> deletePhoneticAnalysisJob(String jobId) async {
    await _request(
      'DELETE',
      '/v1/phonetic-analysis/jobs/${Uri.encodeComponent(jobId)}',
    );
  }

  Future<Map<String, dynamic>> clearTerminalPhoneticAnalysisJobs() async =>
      (await _request('POST', '/v1/phonetic-analysis/jobs/clear'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updatePhoneticFindingFeedback({
    required String findingId,
    required String value,
    String? note,
  }) async =>
      (await _request(
            'PUT',
            '/v1/phonetic-analysis/findings/${Uri.encodeComponent(findingId)}/feedback',
            {'value': value, 'note': note},
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> readLexicalEntriesBatch(
    List<String> forms, {
    required String language,
    String kind = 'word',
  }) async {
    final values =
        await _request('POST', '/v1/lexical-entries/batch', {
              'language': language,
              'kind': kind,
              'forms': forms,
            })
            as List<dynamic>;
    return values.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> upsertWordLexicalEntry(
    String canonicalForm,
    String displayForm,
    String? status, {
    required String language,
    Map<String, dynamic>? source,
  }) async {
    final details = await upsertLexicalEntry({
      'language': language,
      'kind': 'word',
      'canonical_form': canonicalForm,
      'display_form': displayForm,
      'status': status,
      'source': source,
    });
    return details;
  }

  Future<void> createLexicalObservation({
    required String lexicalEntryId,
    required String sentenceId,
    required String originalForm,
    required bool heard,
    Map<String, dynamic>? source,
  }) async {
    await _request('POST', '/v1/lexical-observations', {
      'lexical_entry_id': lexicalEntryId,
      'sentence_id': sentenceId,
      'original_form': originalForm,
      'result': heard ? 'recognized_in_context' : 'not_recognized_in_context',
      'source': source,
    });
  }

  Future<void> clearLexicalObservation({
    required String lexicalEntryId,
    required String sentenceId,
  }) async {
    await _request('POST', '/v1/lexical-observations', {
      'lexical_entry_id': lexicalEntryId,
      'sentence_id': sentenceId,
      'original_form': '',
      'clear': true,
    });
  }

  Future<List<Map<String, dynamic>>> listVocabulary(
    String status, {
    required String language,
    String search = '',
  }) async {
    final values =
        await _request(
              'GET',
              '/v1/vocabulary?language=${Uri.encodeQueryComponent(language)}&status=$status&search=${Uri.encodeQueryComponent(search)}&limit=200&offset=0',
            )
            as List<dynamic>;
    return values.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> lexicalEntryDetails(String entryId) async =>
      (await _request('GET', '/v1/lexical-entries/$entryId'))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateLexicalLearningContent(
    String entryId, {
    String? userDefinition,
    String? personalNote,
  }) async =>
      (await _request('PUT', '/v1/lexical-entries/$entryId/learning-content', {
            'user_definition': userDefinition,
            'personal_note': personalNote,
          }))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> importExternalVocabulary(
    List<Map<String, dynamic>> entries, {
    required String language,
    String? defaultStatus,
    bool overwriteExisting = false,
  }) async =>
      (await _request('POST', '/v1/vocabulary/import-external', {
            'language': language,
            'entries': entries,
            'default_status': defaultStatus,
            'overwrite_existing': overwriteExisting,
          }))
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

  Future<List<String>> listLanguages() async =>
      ((await _request('GET', '/v1/languages')) as List<dynamic>)
          .cast<String>();

  Future<Map<String, dynamic>> lookupLanguageProfile(String code) async =>
      (await _request(
            'GET',
            '/v1/languages/${Uri.encodeComponent(code)}/profile',
          ))
          as Map<String, dynamic>;

  Future<void> updateTrackLanguage(String trackId, String language) async {
    await _request('PATCH', '/v1/subtitles/$trackId/language', {
      'language': language,
    });
  }

  Future<Map<String, dynamic>> lookupDictionary(
    String lemma, {
    required String language,
  }) async =>
      (await _request(
            'GET',
            '/v1/dictionary?language=${Uri.encodeQueryComponent(language)}&lemma=${Uri.encodeQueryComponent(lemma)}',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> diagnose(String sentenceId) async =>
      (await _request(
            'GET',
            '/v1/sentences/${Uri.encodeComponent(sentenceId)}/diagnosis',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> lexicalEntries({
    required String language,
    String? kind,
    String? status,
    String search = '',
  }) async {
    final query = <String, String>{
      'language': language,
      'search': search,
      'limit': '200',
      'offset': '0',
    };
    if (kind != null) query['kind'] = kind;
    if (status != null) query['status'] = status;
    final values =
        await _request(
              'GET',
              '/v1/lexical-entries?${Uri(queryParameters: query).query}',
            )
            as List<dynamic>;
    return values.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> upsertLexicalEntry(
    Map<String, dynamic> value,
  ) async =>
      (await _request('PUT', '/v1/lexical-entries', value))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> correctLemma(
    String original,
    String corrected, {
    required String language,
  }) async =>
      (await _request('POST', '/v1/lexical-normalization/correct', {
            'language': language,
            'original': original,
            'corrected': corrected,
          }))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> phraseCandidates(
    String sentenceId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/sentences/${Uri.encodeComponent(sentenceId)}/phrase-candidates',
              ))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<PracticeSession> createPracticeSession(
    CreatePracticeSession input,
  ) async => PracticeSession.fromJson(
    (await _request('POST', '/v1/practice/sessions', input.toJson()))
        as Map<String, dynamic>,
  );

  Future<PracticeItem> createPracticeItem(CreatePracticeItem input) async =>
      PracticeItem.fromJson(
        (await _request('POST', '/v1/practice/items', input.toJson()))
            as Map<String, dynamic>,
      );

  Future<PracticeAttempt> submitPracticeAttempt(
    SubmitPracticeAttempt input,
  ) async => PracticeAttempt.fromJson(
    (await _request('POST', '/v1/practice/attempts', input.toJson()))
        as Map<String, dynamic>,
  );

  Future<PracticeAttempt> practiceAttempt(String id) async =>
      PracticeAttempt.fromJson(
        (await _request(
              'GET',
              '/v1/practice/attempts/${Uri.encodeComponent(id)}',
            ))
            as Map<String, dynamic>,
      );

  Future<ReviewItem> createReviewItem(CreateReviewItem input) async =>
      ReviewItem.fromJson(
        (await _request('POST', '/v1/review/items', input.toJson()))
            as Map<String, dynamic>,
      );

  Future<ReviewItem> reviewItem(String id) async => ReviewItem.fromJson(
    (await _request('GET', '/v1/review/items/${Uri.encodeComponent(id)}'))
        as Map<String, dynamic>,
  );

  Future<List<Map<String, dynamic>>> learningResources() async =>
      ((await _request('GET', '/v1/learning-resources')) as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> installLearningResource(String id) async =>
      (await _request(
            'POST',
            '/v1/learning-resources/${Uri.encodeComponent(id)}/install',
          ))
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> removeLearningResource(String id) async =>
      (await _request(
            'DELETE',
            '/v1/learning-resources/${Uri.encodeComponent(id)}',
          ))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> searchOpenSubtitles({
    required String apiKey,
    String? query,
    String? moviehash,
    String language = 'en',
  }) async =>
      ((await _request('POST', '/v1/subtitle-search', {
                'provider': 'opensubtitles',
                'api_key': apiKey,
                'language': language,
                if (query != null && query.isNotEmpty) 'query': query,
                if (moviehash != null && moviehash.isNotEmpty)
                  'moviehash': moviehash,
              }))
              as List<dynamic>)
          .cast<Map<String, dynamic>>();

  Future<String> openSubtitlesMovieHash(String path) =>
      computeOpenSubtitlesMovieHash(path);

  Future<String> downloadOpenSubtitle({
    required String apiKey,
    required int fileId,
  }) async {
    final request = await _client.postUrl(
      Uri.parse('$baseUrl/v1/subtitle-search/download'),
    );
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.write(
      jsonEncode({
        'provider': 'opensubtitles',
        'api_key': apiKey,
        'file_id': fileId,
      }),
    );
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      [],
      (all, next) => all..addAll(next),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(utf8.decode(bytes));
    }
    final directory = Directory.systemTemp.createTempSync(
      'llplayernext-subtitle-',
    );
    final path = '${directory.path}/opensubtitles-$fileId.srt';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

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
    final encoded = body != null ? jsonEncode(body) : null;
    final transport = _transport ?? _httpClientTransport;
    final response = await transport(method, path, encoded);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(response.body, uri: Uri.parse('$baseUrl$path'));
    }
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  /// Default transport: the real `dart:io` HttpClient. Preserves the original
  /// header and request behavior exactly; only the raw exchange is extracted so
  /// it can be swapped in tests.
  Future<ApiResponse> _httpClientTransport(
    String method,
    String path,
    String? encodedBody,
  ) async {
    final request = await _client.openUrl(method, Uri.parse('$baseUrl$path'));
    request.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (encodedBody != null) request.write(encodedBody);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return (statusCode: response.statusCode, body: text);
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

List<String> sidecarCandidatesFrom(Directory start) {
  final candidates = <String>[];
  var directory = start.absolute;
  while (true) {
    candidates.add('${directory.path}/target/debug/api-http');
    candidates.add('${directory.path}/target/release/api-http');
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return candidates;
}
