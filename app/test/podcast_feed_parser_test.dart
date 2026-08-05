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

    test('keeps an item that carries no enclosure but marks it unacquirable', () {
      final episode = parsePodcastFeed(_feed).episodes[3];

      expect(episode.enclosureUrl, isNull);
      expect(episode.enclosureBytes, isNull);
    });

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
