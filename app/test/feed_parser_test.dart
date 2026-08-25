import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/feed_parser.dart';

/// The feed parser is the front of the whole RSS/Atom discovery journey, so
/// these tests pin the two things the rest of the journey depends on: that
/// unknown facts stay unknown, and that a malformed feed fails loudly instead
/// of looking like a feed with no items. RSS and Atom are parsed by one
/// parser so the identity rules — GUIDs, entry URLs, enclosures — are one
/// set, never two copies that drift.
void main() {
  group('parseFeed (RSS)', () {
    test('reads channel metadata and items', () {
      final feed = parseFeed(_feed);

      expect(feed.format, FeedFormat.rss);
      expect(feed.title, 'Daily Listening');
      expect(feed.description, 'Short conversations for learners.');
      expect(feed.language, 'en-us');
      expect(feed.imageUrl, 'https://cdn.example.com/cover.jpg');
      expect(feed.items, hasLength(4));
    });

    test('carries the enclosure through as the acquisition URL', () {
      final item = parseFeed(_feed).items.first;

      expect(item.id, 'ep-001');
      expect(item.title, 'Why do we forget?');
      expect(item.enclosureUrl, 'https://cdn.example.com/ep001.mp3');
      expect(item.enclosureBytes, 8123456);
      expect(item.enclosureType, 'audio/mpeg');
      expect(item.durationMs, 6 * 60 * 1000);
      expect(item.publishedOn, '2026-07-28');
    });

    test('flattens CDATA show-note markup into readable text', () {
      final item = parseFeed(_feed).items[1];

      expect(item.description, 'Guests & hosts talk shop.\nRead more here.');
    });

    test('leaves a missing duration unknown rather than guessing', () {
      final item = parseFeed(_feed).items[2];

      expect(item.durationMs, isNull);
    });

    test('an item without a guid declares no identity at all', () {
      final item = parseFeed(_feed).items[2];

      // A feed that omits its guid leaves the item with no stable identity;
      // the parser must not invent one from the enclosure URL. The discovery
      // layer synthesizes an explicitly marked surrogate key instead.
      expect(item.id, isNull);
      expect(item.enclosureUrl, 'https://cdn.example.com/ep003.mp3');
    });

    test(
      'keeps an item that carries no enclosure but marks it unacquirable',
      () {
        final item = parseFeed(_feed).items[3];

        expect(item.enclosureUrl, isNull);
        expect(item.enclosureBytes, isNull);
      },
    );

    test('carries the item link and publisher as typed fields', () {
      final item = parseFeed(_feed).items[3];

      expect(item.entryUrl, 'https://example.com/notes/ep-004');
      expect(item.publisherId, 'daily-listening@example.com');
    });

    test('does not read channel elements as item elements', () {
      // The third item omits <title>; a segment-scanning parser would report
      // the channel title for it.
      final item = parseFeed(_feed).items[2];

      expect(item.title, isEmpty);
    });

    test('rejects a document that is not a feed', () {
      expect(
        () => parseFeed('<html><body>Not a feed</body></html>'),
        throwsA(isA<FeedFormatException>()),
      );
    });

    test('rejects malformed XML', () {
      expect(
        () => parseFeed('<rss><channel><title>Broken'),
        throwsA(isA<FeedFormatException>()),
      );
    });

    test('reports a real feed with no items as empty, not as a failure', () {
      final feed = parseFeed(
        '<rss><channel><title>Quiet</title></channel></rss>',
      );

      expect(feed.title, 'Quiet');
      expect(feed.items, isEmpty);
    });
  });

  group('parseFeed (Atom)', () {
    test('reads Atom channel metadata and entries across the namespace', () {
      final feed = parseFeed(_atomFeed);

      expect(feed.format, FeedFormat.atom);
      expect(feed.title, 'The Weekly Article');
      expect(feed.description, 'Long reads for learners.');
      expect(feed.language, 'en');
      expect(feed.items, hasLength(2));
    });

    test('reads the Atom id, alternate link and published date', () {
      final item = parseFeed(_atomFeed).items.first;

      expect(item.id, 'tag:example.com,2026:post-001');
      expect(item.title, 'The first article');
      expect(item.entryUrl, 'https://example.com/posts/first-article');
      expect(item.publishedOn, '2026-07-28');
    });

    test('reads the publisher from the author element', () {
      final item = parseFeed(_atomFeed).items.first;

      expect(item.publisherId, 'Ada Example');
    });

    test('leaves an entry without a link unacquirable as a document', () {
      final item = parseFeed(_atomFeed).items[1];

      expect(item.entryUrl, isNull);
    });

    test('a YouTube-style Atom entry exposes the video id and thumbnail', () {
      final feed = parseFeed(_youtubeAtom);
      final item = feed.items.first;

      expect(item.id, 'AbC123');
      expect(item.title, 'Why do we forget?');
      expect(item.entryUrl, 'https://www.youtube.com/watch?v=AbC123');
      expect(item.imageUrl, 'https://i.ytimg.com/vi/AbC123/hqdefault.jpg');
      expect(item.viewCount, 142000);
      expect(item.publishedOn, '2026-08-01');
    });

    test('a bare <feed> without the Atom namespace still parses', () {
      final feed = parseFeed(
        '<feed><title>Quiet</title><entry><id>e-1</id></entry></feed>',
      );

      expect(feed.format, FeedFormat.atom);
      expect(feed.items.single.id, 'e-1');
    });
  });

  group('sourceScopedSurrogateId', () {
    final itemWithoutId = ParsedFeedItem(
      id: null,
      title: 'No id here',
      description: '',
      publishedOn: '2026-08-01',
      entryUrl: 'https://blog.example.com/posts/9',
    );

    test('marks the key and binds it to the source and the entry reference', () {
      final key = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/blog.xml',
        item: itemWithoutId,
      );

      expect(key, startsWith('source_scoped_surrogate:'));
      expect(key.length, 'source_scoped_surrogate:'.length + 64);
    });

    test('the same item re-read yields the same key', () {
      final first = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/blog.xml',
        item: itemWithoutId,
      );
      final second = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/blog.xml',
        item: itemWithoutId,
      );

      expect(second, first);
    });

    test('is scoped to the source: the same entry in two feeds never collides',
        () {
      final a = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/a.xml',
        item: itemWithoutId,
      );
      final b = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/b.xml',
        item: itemWithoutId,
      );

      expect(b, isNot(a));
    });

    test('a changed entry reference yields a new key, never a silent merge', () {
      final original = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/blog.xml',
        item: itemWithoutId,
      );
      final changed = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/blog.xml',
        item: ParsedFeedItem(
          id: null,
          title: 'No id here',
          description: '',
          publishedOn: '2026-08-01',
          entryUrl: 'https://blog.example.com/posts/10',
        ),
      );

      expect(changed, isNot(original));
    });

    test('falls back to title and date when the item has no URL at all', () {
      final key = sourceScopedSurrogateId(
        sourceId: 'https://feeds.example.com/blog.xml',
        item: ParsedFeedItem(
          id: null,
          title: 'Notes only',
          description: '',
          publishedOn: '2026-08-02',
        ),
      );

      expect(key, startsWith('source_scoped_surrogate:'));
    });
  });

  group('parseItunesDurationMs', () {
    test('reads the three published shapes', () {
      expect(parseItunesDurationMs('360'), 360000);
      expect(parseItunesDurationMs('06:00'), 360000);
      expect(parseItunesDurationMs('1:02:03'), 3723000);
    });

    test('tolerates fractional seconds and padding', () {
      expect(parseItunesDurationMs(' 00:00:01.500 '), 1500);
    });

    test('returns null for values it cannot read', () {
      for (final raw in ['', 'unknown', '0', '-5', '1:2:3:4', 'aa:bb']) {
        expect(parseItunesDurationMs(raw), isNull, reason: 'for "$raw"');
      }
    });
  });

  /// Reading only as much of a feed as a shelf can show.
  ///
  /// The real incident: The Daily publishes its whole back catalogue — 2937
  /// episodes, 18.4 MB — and selecting the channel took 25 seconds, of which
  /// the visible shelf used the first few kilobytes. Items are newest-first,
  /// so everything past the cap is history nobody asked for.
  group('reading only what the shelf shows', () {
    test(
      'reading stops at the cap and still yields a parseable document',
      () async {
        final body = await readFeedBody(
          _inChunks(_feedWith(500), 997),
          maxItems: 20,
        );

        final feed = parseFeed(body);
        expect(feed.items, hasLength(20));
        // The newest are kept, and the channel metadata preceding them survives
        // the cut.
        expect(feed.items.first.title, 'Episode 0');
        expect(feed.items.last.title, 'Episode 19');
        expect(feed.title, 'Cap');
        expect(feed.language, 'en');
        expect(body.length, lessThan(_feedWith(500).length));
      },
    );

    test('an Atom feed is cut on </entry> closes', () async {
      final body = await readFeedBody(
        _inChunks(_atomFeedWith(400), 997),
        maxItems: 20,
      );

      final feed = parseFeed(body);
      expect(feed.format, FeedFormat.atom);
      expect(feed.items, hasLength(20));
    });

    test('a close tag split across chunks is counted exactly once', () async {
      // 1-byte chunks put a boundary inside every `</item>`; a rescan window
      // that double-counted would stop early and silently lose episodes.
      final body = await readFeedBody(
        _inChunks(_feedWith(30), 1),
        maxItems: 12,
      );

      expect(parseFeed(body).items, hasLength(12));
    });

    test('a feed shorter than the cap is read whole and left intact', () async {
      final source = _feedWith(3);
      final body = await readFeedBody(
        _inChunks(source, 64),
        maxItems: 50,
      );

      expect(body, source);
      expect(parseFeed(body).items, hasLength(3));
    });

    test('the parser caps items even when handed a whole feed', () {
      // Belt and braces: a body that never went through the reader should not
      // build 2937 item objects either.
      expect(
        parseFeed(_feedWith(400), maxItems: 25).items,
        hasLength(25),
      );
    });
  });
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
      <guid isPermaLink="false">ep-001</guid>
      <pubDate>Tue, 28 Jul 2026 09:00:00 GMT</pubDate>
      <enclosure url="https://cdn.example.com/ep001.mp3" length="8123456" type="audio/mpeg"/>
      <itunes:duration>06:00</itunes:duration>
    </item>
    <item>
      <title>Shop talk</title>
      <description><![CDATA[<p>Guests &amp; hosts talk shop.</p><p><a href="https://example.com">Read more here.</a></p>]]></description>
      <guid>ep-002</guid>
      <pubDate>Wed, 29 Jul 2026 09:00:00 GMT</pubDate>
      <enclosure url="https://cdn.example.com/ep002.mp3" length="9000000" type="audio/mpeg"/>
      <itunes:duration>1:02:03</itunes:duration>
    </item>
    <item>
      <pubDate>Thu, 30 Jul 2026 09:00:00 GMT</pubDate>
      <enclosure url="https://cdn.example.com/ep003.mp3" type="audio/mpeg"/>
    </item>
    <item>
      <title>Show notes only</title>
      <guid>ep-004</guid>
      <pubDate>Fri, 31 Jul 2026 09:00:00 GMT</pubDate>
      <link>https://example.com/notes/ep-004</link>
      <author>daily-listening@example.com</author>
    </item>
  </channel>
</rss>
''';

const _atomFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xml:lang="en">
  <title>The Weekly Article</title>
  <subtitle>Long reads for learners.</subtitle>
  <entry>
    <id>tag:example.com,2026:post-001</id>
    <title>The first article</title>
    <summary>A long-form look at the first topic.</summary>
    <link rel="alternate" href="https://example.com/posts/first-article"/>
    <published>2026-07-28T09:00:00Z</published>
    <author><name>Ada Example</name></author>
  </entry>
  <entry>
    <id>tag:example.com,2026:post-002</id>
    <title>The second article</title>
    <published>2026-07-29T09:00:00Z</published>
  </entry>
</feed>
''';

/// A YouTube channel feed: the shape `youtube.com/feeds/videos.xml` serves,
/// with a video id, an alternate link, a thumbnail, and a view count.
const _youtubeAtom = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/">
  <title>BBC Learning English</title>
  <entry>
    <id>yt:video:AbC123</id>
    <yt:videoId>AbC123</yt:videoId>
    <title>Why do we forget?</title>
    <link rel="alternate" href="https://www.youtube.com/watch?v=AbC123"/>
    <published>2026-08-01T07:00:00Z</published>
    <media:thumbnail url="https://i.ytimg.com/vi/AbC123/hqdefault.jpg"/>
    <media:statistics views="142000"/>
  </entry>
</feed>
''';

String _feedWith(int items) => [
  '<rss><channel><title>Cap</title><language>en</language>',
  for (var index = 0; index < items; index++)
    '<item><title>Episode $index</title><guid>g$index</guid>'
        '<enclosure url="https://h/$index.mp3" type="audio/mpeg"/></item>',
  '</channel></rss>',
].join();

String _atomFeedWith(int items) => [
  '<feed xmlns="http://www.w3.org/2005/Atom"><title>Cap</title>',
  for (var index = 0; index < items; index++)
    '<entry><id>g$index</id><title>Entry $index</title></entry>',
  '</feed>',
].join();

Stream<String> _inChunks(String body, int size) async* {
  for (var start = 0; start < body.length; start += size) {
    yield body.substring(
      start,
      start + size > body.length ? body.length : start + size,
    );
  }
}
