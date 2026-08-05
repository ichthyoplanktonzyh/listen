import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/data/repositories/podcast_discovery_repository.dart';
import 'package:llplayer_next/models/discovery.dart';
import 'package:llplayer_next/services/podcast_feed_parser.dart';

import 'discovery_test_helpers.dart';

/// Podcast discovery against a real local feed server.
///
/// The point of these is the boundary between what the feed said and what the
/// app claims: durations and acquisition come from the feed, absence stays
/// absent, and a feed that cannot be read fails rather than presenting as a
/// podcast that has published nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late PodcastDiscoveryRepository repository;
  late Future<void> Function(HttpRequest request) handler;

  String feedUrl() => 'http://${server.address.host}:${server.port}/show.xml';

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(server.forEach((request) async => handler(request)));
    // The test binding installs an HttpOverrides that answers every request
    // with 400, so the repository gets a client built outside it.
    repository = PodcastDiscoveryRepository(
      client: HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _RealHttpOverrides(),
      ),
    );
    handler = (request) async {
      request.response.headers.contentType = ContentType(
        'application',
        'rss+xml',
      );
      request.response.write(_feed);
      await request.response.close();
    };
  });

  tearDown(() async => server.close(force: true));

  test('maps feed items to entries the acquisition path can act on', () async {
    final entries = await repository.entriesFor(feedUrl());

    expect(entries, hasLength(2));
    final first = entries.first;
    expect(first.id, 'ep-001');
    expect(first.sourceId, feedUrl());
    expect(first.title, 'Why do we forget?');
    expect(first.durationMs, 360000);
    expect(first.acquisition, MediaAcquisition.enclosure);
    expect(first.mediaKind, MediaKind.audio);
    expect(first.mediaUrl, 'https://cdn.example.com/ep001.mp3');
    expect(first.mediaByteLength, 8123456);
    expect(first.language, 'en-us');
  });

  test('marks an item with no enclosure as nothing to acquire', () async {
    final entries = await repository.entriesFor(feedUrl());

    expect(entries.last.acquisition, MediaAcquisition.none);
    expect(entries.last.mediaUrl, isNull);
    expect(entries.last.durationMs, isNull);
  });

  test(
    'a feed host error fails rather than reading as an empty podcast',
    () async {
      handler = (request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      };

      await expectLater(
        repository.entriesFor(feedUrl()),
        throwsA(isA<HttpException>()),
      );
    },
  );

  test('a page that is not a feed fails as a format problem', () async {
    handler = (request) async {
      request.response.write('<html><body>Subscribe here</body></html>');
      await request.response.close();
    };

    await expectLater(
      repository.entriesFor(feedUrl()),
      throwsA(isA<PodcastFeedFormatException>()),
    );
  });

  test('subscribing reads the channel from the feed itself', () async {
    final source = await repository.resolveCustomChannel(
      feedUrl(),
      TestMediaImportRepository(),
    );

    expect(source.id, feedUrl());
    expect(source.name, 'Daily Listening');
    expect(source.type, MediaSourceType.podcast);
    expect(source.avatarUrl, 'https://cdn.example.com/cover.jpg');
    expect(await repository.sources(), contains(source));
  });

  test('subscribing to something that is not a feed adds no source', () async {
    handler = (request) async {
      request.response.write('nope');
      await request.response.close();
    };

    await expectLater(
      repository.resolveCustomChannel(feedUrl(), TestMediaImportRepository()),
      throwsA(isA<PodcastFeedFormatException>()),
    );
    expect(
      (await repository.sources()).where((s) => s.id == feedUrl()),
      isEmpty,
    );
  });

  test('claims URL-shaped source ids before the starter list is loaded', () {
    expect(repository.owns('https://feeds.example.com/show.xml'), isTrue);
    expect(repository.owns('UCsooa4yRKGN_zEE8iknghZA'), isFalse);
  });

  test('every starter feed is a well-formed entry', () async {
    final starters = await repository.sources();

    expect(starters, isNotEmpty);
    for (final source in starters) {
      expect(source.type, MediaSourceType.podcast);
      expect(source.name, isNotEmpty);
      expect(Uri.parse(source.id).isScheme('https'), isTrue, reason: source.id);
    }
  });

  group('a feed is fetched once per session', () {
    test('selecting the same channel again does not refetch', () async {
      // `entriesFor` used to hit the network on every selection, so clicking
      // away from The Daily and back paid its whole download a second time.
      var requests = 0;
      final served = handler;
      handler = (request) async {
        requests += 1;
        await served(request);
      };

      final first = await repository.entriesFor(feedUrl());
      final second = await repository.entriesFor(feedUrl());

      expect(requests, 1);
      expect(second.map((entry) => entry.id), first.map((entry) => entry.id));
    });

    test('forgetting a feed sends the next read back to the network', () async {
      // Refreshing has to remain possible; it is a deliberate act rather than
      // a side effect of navigating.
      var requests = 0;
      final served = handler;
      handler = (request) async {
        requests += 1;
        await served(request);
      };

      await repository.entriesFor(feedUrl());
      repository.forget(feedUrl());
      await repository.entriesFor(feedUrl());

      expect(requests, 2);
    });

    test('a failed fetch is not cached as an answer', () async {
      // Caching a failure would make one bad moment look like a permanently
      // broken channel for the rest of the session.
      handler = (request) async {
        request.response.statusCode = 503;
        await request.response.close();
      };
      await expectLater(repository.entriesFor(feedUrl()), throwsA(anything));

      handler = (request) async {
        request.response.write(_feed);
        await request.response.close();
      };
      expect(await repository.entriesFor(feedUrl()), hasLength(2));
    });
  });
}

/// The base class's own `createHttpClient` builds a real one.
class _RealHttpOverrides extends HttpOverrides {}

const _feed = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
  <channel>
    <title>Daily Listening</title>
    <description>Short conversations for learners.</description>
    <language>en-US</language>
    <itunes:image href="https://cdn.example.com/cover.jpg"/>
    <item>
      <title>Why do we forget?</title>
      <description>Memory researchers explain.</description>
      <guid>ep-001</guid>
      <pubDate>Tue, 28 Jul 2026 09:00:00 GMT</pubDate>
      <enclosure url="https://cdn.example.com/ep001.mp3" length="8123456" type="audio/mpeg"/>
      <itunes:duration>06:00</itunes:duration>
    </item>
    <item>
      <title>Show notes only</title>
      <guid>ep-002</guid>
      <pubDate>Wed, 29 Jul 2026 09:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>
''';
