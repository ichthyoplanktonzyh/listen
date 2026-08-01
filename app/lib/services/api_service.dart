import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/api_failure.dart';
import '../models/coach_dashboard.dart';
import '../models/listening.dart';
import '../models/llm_provider.dart';
import '../models/personal_expression.dart';
import '../models/practice.dart';
import '../models/production_corpus.dart';
import '../models/projection_review.dart';
import '../models/reading.dart';
import '../models/realtime_conversation.dart';
import '../models/runtime_resources.dart';
import '../models/semantic_embedding.dart';
import '../models/semantic_task.dart';
import '../models/speech_synthesis.dart';
import '../models/syntax_capability.dart';
import '../models/timeline.dart';
import '../models/types.dart';
import '../models/vocabulary_transfer.dart';

part 'api/media.dart';
part 'api/subtitles.dart';
part 'api/timelines.dart';
part 'api/speech.dart';
part 'api/transcription.dart';
part 'api/lexical.dart';
part 'api/practice.dart';
part 'api/production_corpus.dart';
part 'api/projection_review.dart';
part 'api/personal_expression.dart';
part 'api/listening_hunting.dart';
part 'api/coach_llm.dart';
part 'api/reading.dart';
part 'api/realtime.dart';
part 'api/semantic.dart';
part 'api/semantic_embedding.dart';

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

/// Aggregate saved-vocabulary total for the home readiness surface. [capped]
/// signals that at least one status page hit the backend limit, so [total]
/// under-reports very large collections.
class SavedVocabularyCount {
  const SavedVocabularyCount({required this.total, required this.capped});

  final int total;
  final bool capped;
}

/// Raw HTTP exchange result used by the [LocalApi] transport seam.
typedef ApiResponse = ({int statusCode, String body});

/// Turns whatever a failed [LocalApi] call threw into the typed
/// [ApiFailure] view.
///
/// This is the seam that stops transport text from becoming UI text.
/// [LocalApi._request] throws `HttpException(responseBody, uri: …)`, so
/// `'$error'` carries the backend's error envelope *and* the sidecar's
/// localhost URI. Callers that want to react to a failure — retry it, log it,
/// offer a disclosure — go through this instead of interpolating the
/// exception, and controllers hand the result on as a typed field rather than
/// a message string.
///
/// Lives here rather than in `models/` because recognising `HttpException` is
/// transport knowledge; [ApiFailure.parse] itself stays a pure body parser.
ApiFailure describeApiFailure(Object error) => error is HttpException
    ? ApiFailure.parse(error.message)
    : ApiFailure(raw: '$error');

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
      validateSidecarHandshake(handshake);
      final logs = Directory(
        '${Platform.environment['HOME']}/Library/Logs/listen',
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
    candidates.addAll(sidecarCandidatesFrom(Directory.current.absolute));
    if (configured != null) candidates.insert(0, configured);
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    throw StateError(
      'Local API sidecar not found. Build it with cargo build -p api-http.',
    );
  }

  // ── Phase 3.9.3 optional syntax capability ──

  // ── Phase 3.12 vendor-neutral LLM providers ──
  // Secrets are write-only: `registerLlmProvider` sends the key once; it is
  // stored in the OS keychain by the backend and never returned. All reads use
  // the secret-free view.

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

  /// Asks the sidecar to stop without awaiting it. Safe to call from
  /// [State.dispose] or any other synchronous teardown, where [close] cannot
  /// be awaited.
  ///
  /// Sends SIGINT rather than SIGKILL so the sidecar runs its own graceful
  /// shutdown and closes the database cleanly. Not awaiting it is safe: if the
  /// app exits first, the sidecar notices its parent is gone and reaps itself.
  void requestStop() {
    _closed = true;
    _client.close(force: true);
    _process?.kill(ProcessSignal.sigint);
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

const supportedApiVersion = 1;
const supportedContractMajor = 1;

void validateSidecarHandshake(Map<String, dynamic> handshake) {
  if (handshake['event'] != 'api.started' ||
      handshake['api_version'] != supportedApiVersion) {
    throw const FormatException('invalid local API handshake');
  }
  final contractVersion = handshake['contract_version'];
  final runtimeVersion = handshake['runtime_version'];
  if (contractVersion is! String ||
      runtimeVersion is! String ||
      !_isSemanticVersion(runtimeVersion)) {
    throw const FormatException('local core did not report version metadata');
  }
  final contractMatch = _semanticVersionPattern.firstMatch(contractVersion);
  if (contractMatch == null) {
    throw const FormatException(
      'local core reported an invalid contract version',
    );
  }
  final contractMajor = int.parse(contractMatch.group(1)!);
  if (contractMajor != supportedContractMajor) {
    throw FormatException(
      'incompatible local core contract $contractVersion; '
      'this app supports $supportedContractMajor.x',
    );
  }
}

final RegExp _semanticVersionPattern = RegExp(
  r'^([0-9]+)\.([0-9]+)\.([0-9]+)(?:[-+][0-9A-Za-z.-]+)?$',
);

bool _isSemanticVersion(String value) =>
    _semanticVersionPattern.hasMatch(value);

List<String> sidecarCandidatesFrom(Directory start) {
  final root = start.absolute.path;
  return ['$root/.backend/runtime/bin/api-http'];
}
