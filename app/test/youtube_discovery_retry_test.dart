import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/data/repositories/discovery_repository.dart';

/// A throttled channel feed is not a missing channel.
///
/// The real incident: TED-Ed and Vox reported "this source could not be
/// loaded" perhaps half the times they were opened. The channel ids were
/// correct — resolved from the channels' own pages — and the feed URL answered
/// 200, 404 and 500 in no pattern when requested seconds apart, identically
/// under a browser user agent. YouTube throttles this endpoint by answering
/// "not found", and `entriesFor` made exactly one attempt, so a throttled
/// response and a deleted channel rendered as the same sentence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late List<int> statuses;
  late int requests;

  YoutubeDiscoveryRepository repositoryFor(HttpServer server) =>
      YoutubeDiscoveryRepository(
        // The test binding installs an HttpOverrides that answers every
        // request with 400, so the repository gets a client built outside it.
        client: HttpOverrides.runWithHttpOverrides(
          HttpClient.new,
          _RealHttpOverrides(),
        ),
        feedBaseUrl:
            'http://${server.address.host}:${server.port}/feeds/videos.xml',
        retryBackoff: Duration.zero,
      );

  setUp(() async {
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        final status = statuses[requests.clamp(0, statuses.length - 1)];
        requests++;
        request.response.statusCode = status;
        if (status == HttpStatus.ok) request.response.write(_feed);
        await request.response.close();
      }),
    );
  });

  tearDown(() async => server.close(force: true));

  test('a throttled answer is retried rather than reported as failure', () async {
    statuses = [HttpStatus.notFound, HttpStatus.internalServerError, 200];

    final entries = await repositoryFor(server).entriesFor('UC-channel');

    expect(requests, 3);
    expect(entries.single.id, 'abc123');
    expect(entries.single.title, 'How memory works');
  });

  test('a source that never answers still fails, and says so', () async {
    // Retrying forever would be its own dishonesty: a channel that really is
    // gone answers the same way, and the person has to be told.
    statuses = [HttpStatus.notFound];

    await expectLater(
      repositoryFor(server).entriesFor('UC-gone'),
      throwsA(isA<HttpException>()),
    );
    expect(requests, 3);
  });

  test('a body that arrived is never re-requested', () async {
    // An empty channel and a throttled one are different facts. Retrying
    // because the feed parsed to nothing would hide the first.
    statuses = [200];

    final entries = await repositoryFor(server).entriesFor('UC-channel');

    expect(requests, 1);
    expect(entries, hasLength(1));
  });

  test('every starter channel id is the shape YouTube answers to', () async {
    // Two of them — Wired and SciShow — were invented strings that could never
    // load, which read on screen as the same failure as the throttling above.
    final ids = (await YoutubeDiscoveryRepository().sources()).map(
      (source) => source.id,
    );

    for (final id in ids) {
      expect(
        id,
        matches(RegExp(r'^UC[A-Za-z0-9_-]{22}$')),
        reason: 'a channel id is UC plus 22 base64url characters',
      );
    }
  });

  test('no starter claims artwork it does not have', () async {
    // The six avatar URLs that used to be here were fabricated and 404'd.
    // Nothing renders them today; a real one has to be fetched when something
    // does.
    final sources = await YoutubeDiscoveryRepository().sources();

    expect(sources.every((source) => source.avatarUrl == null), isTrue);
  });
}

class _RealHttpOverrides extends HttpOverrides {}

const _feed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015"
      xmlns:media="http://search.yahoo.com/mrss/">
  <entry>
    <yt:videoId>abc123</yt:videoId>
    <title>How memory works</title>
    <published>2026-08-01T10:00:00+00:00</published>
    <media:description>A short explainer.</media:description>
    <media:thumbnail url="https://i.ytimg.com/vi/abc123/hqdefault.jpg"/>
    <media:statistics views="4210"/>
  </entry>
</feed>
''';
