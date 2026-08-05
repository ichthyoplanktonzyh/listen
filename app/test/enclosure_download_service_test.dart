import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/enclosure_download_service.dart';

/// The podcast acquisition path, exercised against a real local HTTP server.
///
/// The behaviour worth pinning is what happens when the fetch does not go
/// well: an error page must not land on disk as a media file, and a cancelled
/// or failed download must not leave a partial one behind for the media
/// library to scan later and treat as a real episode.
void main() {
  late Directory directory;
  late HttpServer server;
  late EnclosureDownloadService service;

  /// Set per test to shape the next response.
  late Future<void> Function(HttpRequest request) handler;

  String urlFor(String path) =>
      'http://${server.address.host}:${server.port}$path';

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('enclosure_test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        await handler(request);
      }),
    );
    service = EnclosureDownloadService();
    handler = (request) async {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.add(List<int>.filled(2048, 7));
      await request.response.close();
    };
  });

  tearDown(() async {
    await server.close(force: true);
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  test('writes the enclosure to disk and reports progress', () async {
    final download = service.start(urlFor('/media/ep001.mp3'), directory.path);
    final progress = await download.progress.toList();
    final path = await download.completed;

    expect(path, '${directory.path}/ep001.mp3');
    expect(File(path!).lengthSync(), 2048);
    expect(progress, isNotEmpty);
    expect(progress.last, 1.0);
    expect(progress, everyElement(inInclusiveRange(0.0, 1.0)));
  });

  test('drops the query string when naming the file', () async {
    final download = service.start(
      urlFor('/media/ep001.mp3?token=abc&src=rss'),
      directory.path,
    );

    expect(await download.completed, '${directory.path}/ep001.mp3');
  });

  test('appends an extension from the media type when the URL has none',
      () async {
    final download = service.start(urlFor('/stream/12345'), directory.path);

    expect(await download.completed, '${directory.path}/12345.mp3');
  });

  test('leaves the name alone when the media type is unrecognised', () async {
    handler = (request) async {
      request.response.headers.contentType = ContentType('application', 'x-odd');
      request.response.add(List<int>.filled(16, 1));
      await request.response.close();
    };

    final download = service.start(urlFor('/stream/12345'), directory.path);

    expect(await download.completed, '${directory.path}/12345');
  });

  test('does not overwrite an episode that is already on disk', () async {
    await File('${directory.path}/ep001.mp3').writeAsString('first');

    final download = service.start(urlFor('/media/ep001.mp3'), directory.path);

    expect(await download.completed, '${directory.path}/ep001 (2).mp3');
    expect(File('${directory.path}/ep001.mp3').readAsStringSync(), 'first');
  });

  test('fails on a non-200 answer instead of saving the error page', () async {
    handler = (request) async {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('<html>gone</html>');
      await request.response.close();
    };

    final download = service.start(urlFor('/media/ep001.mp3'), directory.path);

    await expectLater(
      download.completed,
      throwsA(
        isA<EnclosureDownloadError>().having(
          (e) => e.message,
          'message',
          contains('404'),
        ),
      ),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('fails on an empty body rather than registering a zero-byte episode',
      () async {
    handler = (request) async {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      await request.response.close();
    };

    final download = service.start(urlFor('/media/ep001.mp3'), directory.path);

    await expectLater(
      download.completed,
      throwsA(isA<EnclosureDownloadError>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('refuses an enclosure address that is not http', () async {
    final download = service.start('file:///etc/passwd', directory.path);

    await expectLater(
      download.completed,
      throwsA(isA<EnclosureDownloadError>()),
    );
    expect(directory.listSync(), isEmpty);
  });

  test('cancelling fails the download and leaves nothing partial behind',
      () async {
    final started = Completer<void>();
    handler = (request) async {
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.add(List<int>.filled(1024, 3));
      await request.response.flush();
      started.complete();
      // Hold the response open so the download is genuinely mid-flight.
      await Future<void>.delayed(const Duration(seconds: 30));
    };

    final download = service.start(urlFor('/media/ep001.mp3'), directory.path);
    await started.future;
    download.cancel();

    await expectLater(
      download.completed,
      throwsA(
        isA<EnclosureDownloadError>().having(
          (e) => e.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(directory.listSync(), isEmpty);
  });
}
