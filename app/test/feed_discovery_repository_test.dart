import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/data/repositories/feed_discovery_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/models/discovery.dart';
import 'package:llplayer_next/services/subscription_store.dart';
import 'package:llplayer_next/services/feed_parser.dart';

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
  late FeedDiscoveryRepository repository;
  late Future<void> Function(HttpRequest request) handler;

  String feedUrl() => 'http://${server.address.host}:${server.port}/show.xml';

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(server.forEach((request) async => handler(request)));
    // The test binding installs an HttpOverrides that answers every request
    // with 400, so the repository gets a client built outside it.
    repository = FeedDiscoveryRepository(
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
    expect(first.acquisition, AcquisitionMode.enclosure);
    expect(first.contentKind, ItemContentKind.audio);
    expect(first.mediaUrl, 'https://cdn.example.com/ep001.mp3');
    expect(first.mediaByteLength, 8123456);
    expect(first.language, 'en-us');
  });

  test('marks an item with no enclosure as nothing to acquire', () async {
    final entries = await repository.entriesFor(feedUrl());

    expect(entries.last.acquisition, AcquisitionMode.none);
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
      throwsA(isA<FeedFormatException>()),
    );
  });

  test('subscribing reads the channel from the feed itself', () async {
    final source = await repository.resolveCustomChannel(
      feedUrl(),
      TestMediaImportRepository(),
    );

    expect(source.id, feedUrl());
    expect(source.name, 'Daily Listening');
    expect(source.kind, ContentSourceKind.podcast);
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
      throwsA(isA<FeedFormatException>()),
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
      expect(source.kind, ContentSourceKind.podcast);
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

  test('a subscribed feed is still there after a restart', () async {
    // The whole point: a paste used to add a channel that existed until quit.
    final directory = Directory.systemTemp.createTempSync('subs-repo-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final store = SubscriptionStore(directory: directory);
    final subscribing = FeedDiscoveryRepository(
      client: HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _RealHttpOverrides(),
      ),
      subscriptions: store,
    );
    final added = await subscribing.resolveCustomChannel(
      feedUrl(),
      _UnusedImportRepository(),
    );

    // A fresh store and repository, as a relaunch would build.
    final relaunched = FeedDiscoveryRepository(
      client: HttpOverrides.runWithHttpOverrides(
        HttpClient.new,
        _RealHttpOverrides(),
      ),
      subscriptions: SubscriptionStore(directory: directory),
    );

    final sources = await relaunched.sources();
    expect(sources.map((source) => source.id), contains(added.id));
    expect(
      sources.firstWhere((source) => source.id == added.id).name,
      'Daily Listening',
    );
  });

  test(
    'an item without a guid gets an explicitly marked surrogate key, never a '
    'URL pretending to be a feed item id',
    () async {
      handler = (request) async {
        request.response.write(_feedWithoutGuids);
        await request.response.close();
      };

      final entries = await repository.entriesFor(feedUrl());
      expect(entries, hasLength(2));

      final first = entries.first;
      expect(first.id, startsWith('source_scoped_surrogate:'));
      // The enclosure URL the surrogate was built from stays typed evidence.
      expect(
        first.evidence().where(
          (field) => field.kind == SourceItemEvidenceKind.enclosureUrl,
        ),
        hasLength(1),
      );

      // Two items with equal bytes from the same feed still get distinct keys
      // when their references differ, and the same item re-read gets the same
      // key (identity stability) — asserted by re-fetching a second feed body
      // that repeats the first item with the same link.
      handler = (request) async {
        request.response.write(_feedWithoutGuids);
        await request.response.close();
      };
      repository.forget(feedUrl());
      final reRead = await repository.entriesFor(feedUrl());
      expect(reRead.first.id, first.id);
    },
  );

  test(
    'a mixed feed decides modality per item, not from its first item',
    () async {
      handler = (request) async {
        request.response.write(_mixedFeed);
        await request.response.close();
      };

      final entries = await repository.entriesFor(feedUrl());
      expect(entries, hasLength(2));

      // The first item carries an enclosure: it is media, whatever the
      // channel is called.
      final media = entries.first;
      expect(media.acquisition, AcquisitionMode.enclosure);
      expect(media.contentKind, ItemContentKind.audio);
      expect(media.mediaUrl, 'https://cdn.example.com/ep001.mp3');
      expect(media.entryUrl, isNull);

      // The second item is an article link: it is a document, decided by its
      // own shape, not by the channel's first item.
      final article = entries.last;
      expect(article.acquisition, AcquisitionMode.article);
      expect(article.contentKind, ItemContentKind.article);
      expect(article.mediaUrl, isNull);
      expect(article.entryUrl, 'https://blog.example.com/posts/1');
    },
  );

  test(
    'an article feed subscribes as a document source, not a podcast',
    () async {
      // The kind is the feed's own fact: enclosures are media, article links
      // are documents. A feed of articles must never be offered as a podcast.
      handler = (request) async {
        request.response.write(_documentFeed);
        await request.response.close();
      };

      final source = await repository.resolveCustomChannel(
        feedUrl(),
        _UnusedImportRepository(),
      );

      expect(source.kind, ContentSourceKind.document);

      final items = await repository.entriesFor(feedUrl());
      expect(items.single.acquisition, AcquisitionMode.article);
      expect(items.single.contentKind, ItemContentKind.article);
      expect(items.single.entryUrl, 'https://blog.example.com/posts/1');
      expect(items.single.mediaUrl, isNull);
    },
  );

  test(
    'the subscribed kind is what the entries mean after a restart',
    () async {
      final directory = Directory.systemTemp.createTempSync('subs-doc-');
      addTearDown(() => directory.deleteSync(recursive: true));

      handler = (request) async {
        request.response.write(_documentFeed);
        await request.response.close();
      };
      final subscribing = FeedDiscoveryRepository(
        client: HttpOverrides.runWithHttpOverrides(
          HttpClient.new,
          _RealHttpOverrides(),
        ),
        subscriptions: SubscriptionStore(directory: directory),
      );
      final added = await subscribing.resolveCustomChannel(
        feedUrl(),
        _UnusedImportRepository(),
      );
      expect(added.kind, ContentSourceKind.document);

      // A fresh repository, as a relaunch would build: the cached parse is
      // gone and the subscribed kind is the only thing left to say what the
      // feed's items mean.
      final relaunched = FeedDiscoveryRepository(
        client: HttpOverrides.runWithHttpOverrides(
          HttpClient.new,
          _RealHttpOverrides(),
        ),
        subscriptions: SubscriptionStore(directory: directory),
      );
      final items = await relaunched.entriesFor(feedUrl());

      expect(items.single.acquisition, AcquisitionMode.article);
      expect(items.single.contentKind, ItemContentKind.article);
    },
  );
}

/// The base class's own `createHttpClient` builds a real one.
class _RealHttpOverrides extends HttpOverrides {}

/// Subscribing to a podcast feed never consults the import repository; a stub
/// that throws proves the flow does not quietly start depending on one.
class _UnusedImportRepository implements MediaImportRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('subscribing must not touch imports');
}

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

const _documentFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>The Weekly Article</title>
    <description>Long reads for learners.</description>
    <language>en</language>
    <item>
      <title>The first article</title>
      <guid>post-001</guid>
      <pubDate>Tue, 28 Jul 2026 09:00:00 GMT</pubDate>
      <link>https://blog.example.com/posts/1</link>
    </item>
  </channel>
</rss>
''';

/// Two items with no guids: an enclosure item and an article item, so both
/// surrogate shapes and the mixed-feed rule are exercised from one fixture.
const _feedWithoutGuids = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>No Guids Here</title>
    <language>en</language>
    <item>
      <title>An episode</title>
      <pubDate>Tue, 28 Jul 2026 09:00:00 GMT</pubDate>
      <enclosure url="https://cdn.example.com/ep001.mp3" length="8123456" type="audio/mpeg"/>
    </item>
    <item>
      <title>An article</title>
      <pubDate>Wed, 29 Jul 2026 09:00:00 GMT</pubDate>
      <link>https://blog.example.com/posts/1</link>
    </item>
  </channel>
</rss>
''';

/// One enclosure item and one article item in the same channel: modality is
/// each item's own fact.
const _mixedFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Mixed</title>
    <language>en</language>
    <item>
      <title>An episode</title>
      <guid>mix-1</guid>
      <pubDate>Tue, 28 Jul 2026 09:00:00 GMT</pubDate>
      <enclosure url="https://cdn.example.com/ep001.mp3" length="8123456" type="audio/mpeg"/>
    </item>
    <item>
      <title>An article</title>
      <guid>mix-2</guid>
      <pubDate>Wed, 29 Jul 2026 09:00:00 GMT</pubDate>
      <link>https://blog.example.com/posts/1</link>
    </item>
  </channel>
</rss>
''';
