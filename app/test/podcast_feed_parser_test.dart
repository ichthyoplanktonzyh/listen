import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/podcast_feed_parser.dart';

/// The podcast feed is the first remote source whose acquisition path is
/// lawful by design, so the parser is the front of that whole journey. These
/// tests pin the two things the rest of the journey depends on: that unknown
/// facts stay unknown, and that a malformed feed fails loudly instead of
/// looking like a podcast with no episodes.
void main() {
  group('parsePodcastFeed', () {
    test('reads channel metadata and episodes', () {
      final feed = parsePodcastFeed(_feed);

      expect(feed.title, 'Daily Listening');
      expect(feed.description, 'Short conversations for learners.');
      expect(feed.language, 'en-us');
      expect(feed.imageUrl, 'https://cdn.example.com/cover.jpg');
      expect(feed.episodes, hasLength(4));
    });

    test('carries the enclosure through as the acquisition URL', () {
      final episode = parsePodcastFeed(_feed).episodes.first;

      expect(episode.guid, 'ep-001');
      expect(episode.title, 'Why do we forget?');
      expect(episode.enclosureUrl, 'https://cdn.example.com/ep001.mp3');
      expect(episode.enclosureBytes, 8123456);
      expect(episode.enclosureType, 'audio/mpeg');
      expect(episode.durationMs, 6 * 60 * 1000);
      expect(episode.publishedOn, '2026-07-28');
    });

    test('flattens CDATA show-note markup into readable text', () {
      final episode = parsePodcastFeed(_feed).episodes[1];

      expect(episode.description, 'Guests & hosts talk shop.\nRead more here.');
    });

    test('leaves a missing duration unknown rather than guessing', () {
      final episode = parsePodcastFeed(_feed).episodes[2];

      expect(episode.durationMs, isNull);
    });

    test('falls back to the enclosure URL when an item has no guid', () {
      final episode = parsePodcastFeed(_feed).episodes[2];

      expect(episode.guid, 'https://cdn.example.com/ep003.mp3');
    });

    test(
      'keeps an item that carries no enclosure but marks it unacquirable',
      () {
        final episode = parsePodcastFeed(_feed).episodes[3];

        expect(episode.enclosureUrl, isNull);
        expect(episode.enclosureBytes, isNull);
      },
    );

    test('does not read channel elements as item elements', () {
      // The third item omits <title>; a segment-scanning parser would report
      // the channel title for it.
      final episode = parsePodcastFeed(_feed).episodes[2];

      expect(episode.title, isEmpty);
    });

    test('rejects a document that is not a feed', () {
      expect(
        () => parsePodcastFeed('<html><body>Not a feed</body></html>'),
        throwsA(isA<PodcastFeedFormatException>()),
      );
    });

    test('rejects malformed XML', () {
      expect(
        () => parsePodcastFeed('<rss><channel><title>Broken'),
        throwsA(isA<PodcastFeedFormatException>()),
      );
    });

    test('reports a real feed with no items as empty, not as a failure', () {
      final feed = parsePodcastFeed(
        '<rss><channel><title>Quiet</title></channel></rss>',
      );

      expect(feed.title, 'Quiet');
      expect(feed.episodes, isEmpty);
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
        final body = await readPodcastFeedBody(
          _inChunks(_feedWith(500), 997),
          maxItems: 20,
        );

        final feed = parsePodcastFeed(body);
        expect(feed.episodes, hasLength(20));
        // The newest are kept, and the channel metadata preceding them survives
        // the cut.
        expect(feed.episodes.first.title, 'Episode 0');
        expect(feed.episodes.last.title, 'Episode 19');
        expect(feed.title, 'Cap');
        expect(feed.language, 'en');
        expect(body.length, lessThan(_feedWith(500).length));
      },
    );

    test('a close tag split across chunks is counted exactly once', () async {
      // 1-byte chunks put a boundary inside every `</item>`; a rescan window
      // that double-counted would stop early and silently lose episodes.
      final body = await readPodcastFeedBody(
        _inChunks(_feedWith(30), 1),
        maxItems: 12,
      );

      expect(parsePodcastFeed(body).episodes, hasLength(12));
    });

    test('a feed shorter than the cap is read whole and left intact', () async {
      final source = _feedWith(3);
      final body = await readPodcastFeedBody(
        _inChunks(source, 64),
        maxItems: 50,
      );

      expect(body, source);
      expect(parsePodcastFeed(body).episodes, hasLength(3));
    });

    test('the parser caps episodes even when handed a whole feed', () {
      // Belt and braces: a body that never went through the reader should not
      // build 2937 episode objects either.
      expect(
        parsePodcastFeed(_feedWith(400), maxEpisodes: 25).episodes,
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
    </item>
  </channel>
</rss>
''';

String _feedWith(int items) => [
  '<rss><channel><title>Cap</title><language>en</language>',
  for (var index = 0; index < items; index++)
    '<item><title>Episode $index</title><guid>g$index</guid>'
        '<enclosure url="https://h/$index.mp3" type="audio/mpeg"/></item>',
  '</channel></rss>',
].join();

Stream<String> _inChunks(String body, int size) async* {
  for (var start = 0; start < body.length; start += size) {
    yield body.substring(
      start,
      start + size > body.length ? body.length : start + size,
    );
  }
}
