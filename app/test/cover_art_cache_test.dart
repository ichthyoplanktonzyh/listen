import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/cover_art_cache.dart';

/// Cover art is fetched once, not once per place it is drawn.
///
/// The real incident: bounding the decode stopped the flicker and none of the
/// waiting. A measured NPR episode cover is 524 KB and about 3.6 s cold; a
/// first screen is roughly twenty of them, none of it survived a restart, and
/// opening the detail panel downloaded the same file again because Flutter's
/// image cache is keyed by decode size and the panel decodes at 380 pt where
/// the card decodes at 168.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late Directory directory;
  late int requests;
  late int status;

  String urlFor(String name) =>
      'http://${server.address.host}:${server.port}/$name.jpg';

  CoverArtCache cacheOn(Directory? directory) {
    // The test binding installs an HttpOverrides that answers every request
    // with 400, so the cache gets a client built outside it.
    final client = HttpOverrides.runWithHttpOverrides(
      HttpClient.new,
      _RealHttpOverrides(),
    );
    return directory == null
        ? CoverArtCache.memoryOnly(client: client)
        : CoverArtCache(directory: directory, client: client);
  }

  setUp(() async {
    requests = 0;
    status = HttpStatus.ok;
    directory = await Directory.systemTemp.createTemp('cover-art-test');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        requests++;
        request.response.statusCode = status;
        if (status == HttpStatus.ok) request.response.add(_artwork);
        await request.response.close();
      }),
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test('a second read of the same cover does not go to the network', () async {
    final cache = cacheOn(directory);

    final first = await cache.bytesOf(urlFor('art'));
    final second = await cache.bytesOf(urlFor('art'));

    expect(first, _artwork);
    expect(second, _artwork);
    expect(requests, 1);
  });

  test('a cover survives the launch it was fetched in', () async {
    // The whole point of the disk layer: the memory cache is emptied by
    // quitting, so every launch used to re-download the entire first screen.
    await cacheOn(directory).bytesOf(urlFor('art'));

    final relaunched = await cacheOn(directory).bytesOf(urlFor('art'));

    expect(relaunched, _artwork);
    expect(requests, 1);
  });

  test('the card and the hero share one download', () async {
    // They are two decode sizes of one file, and used to be two downloads.
    final cache = cacheOn(directory);

    final both = await Future.wait([
      cache.bytesOf(urlFor('art')),
      cache.bytesOf(urlFor('art')),
    ]);

    expect(both.first, _artwork);
    expect(both.last, _artwork);
    expect(requests, 1);
  });

  test('two covers are two entries', () async {
    final cache = cacheOn(directory);

    await cache.bytesOf(urlFor('one'));
    await cache.bytesOf(urlFor('two'));

    expect(requests, 2);
  });

  test('without a directory nothing is written', () async {
    // Only the composition root hands out a disk-backed cache; a default
    // reaching for the support directory would have tests writing into it.
    final cache = cacheOn(null);

    await cache.bytesOf(urlFor('art'));
    await cache.bytesOf(urlFor('art'));

    expect(requests, 2);
    expect(directory.listSync(), isEmpty);
  });

  test('artwork that failed is not stored as if it had arrived', () async {
    status = HttpStatus.notFound;
    final cache = cacheOn(directory);

    await expectLater(
      cache.bytesOf(urlFor('art')),
      throwsA(isA<HttpException>()),
    );

    expect(directory.listSync(), isEmpty);
    // And the failure is not remembered either: a host that answers next time
    // must be allowed to.
    status = HttpStatus.ok;
    expect(await cache.bytesOf(urlFor('art')), _artwork);
  });

  test('download progress is reported while bytes arrive', () async {
    // The loading state exists to be told apart from the unavailable one, and
    // it is these events that let the widget do it.
    final progress = <int>[];

    await cacheOn(directory).bytesOf(
      urlFor('art'),
      onProgress: (loaded, total) => progress.add(loaded),
    );

    expect(progress, isNotEmpty);
    expect(progress.last, _artwork.length);
  });
}

class _RealHttpOverrides extends HttpOverrides {}

/// Not a real JPEG: the cache moves bytes and never decodes them.
final _artwork = List<int>.generate(4096, (index) => index % 256);
