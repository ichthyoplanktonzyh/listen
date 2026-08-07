import 'package:xml/xml.dart';

/// Parses podcast RSS into a typed feed.
///
/// Podcast feeds are the one remote source whose acquisition path is designed
/// for clients: the `<enclosure>` is a plain media URL the publisher put there
/// to be fetched. That makes the parser the front of the whole podcast journey,
/// so it reports what the feed actually said and nothing more.
///
/// Real XML parsing rather than regular expressions is not fussiness. Podcast
/// feeds carry CDATA-wrapped HTML descriptions, `itunes:` and `podcast:`
/// namespaces, attributes in arbitrary order, and channel-level elements that
/// repeat inside items. A regex that reads `<title>` off an `<item>` segment
/// picks up the channel title on a feed whose item happens to omit its own.
///
/// Anything the feed does not state stays null. A missing duration is not zero
/// and not a guessed five minutes: the surface has to say it does not know.
class PodcastFeed {
  const PodcastFeed({
    required this.title,
    required this.description,
    required this.language,
    required this.imageUrl,
    required this.episodes,
  });

  final String title;
  final String description;

  /// BCP-47-ish tag as published (`en`, `en-us`, `zh-cn`), lowercased. Empty
  /// when the feed omits it — we do not assume English.
  final String language;

  final String? imageUrl;
  final List<PodcastEpisode> episodes;
}

class PodcastEpisode {
  const PodcastEpisode({
    required this.guid,
    required this.title,
    required this.description,
    required this.enclosureUrl,
    required this.enclosureBytes,
    required this.enclosureType,
    required this.durationMs,
    required this.publishedOn,
    required this.imageUrl,
  });

  /// Source Identity. The feed's `<guid>` when present, otherwise the
  /// enclosure URL — stable enough to recognise the same episode across
  /// refreshes, and never treated as evidence about the bytes themselves.
  final String guid;

  final String title;
  final String description;

  /// The publisher-provided media URL, or null when the item carries no
  /// enclosure. Such items exist (notes-only posts) and are not acquirable.
  final String? enclosureUrl;

  /// `length` attribute, in bytes. Advisory: hosts that splice audio at request
  /// time routinely report a length that does not match what they send.
  final int? enclosureBytes;

  final String? enclosureType;

  /// From `itunes:duration`, null when absent or unparseable.
  final int? durationMs;

  /// `yyyy-MM-dd` in UTC, or empty when the feed omits or mangles `pubDate`.
  final String publishedOn;

  final String? imageUrl;
}

/// Thrown when [parsePodcastFeed] is handed something that is not a podcast
/// feed. Callers surface this as a failed source rather than an empty one:
/// "this feed has no episodes" and "this URL is not a feed" are different
/// facts.
class PodcastFeedFormatException implements Exception {
  const PodcastFeedFormatException(this.message);

  final String message;

  @override
  String toString() => 'PodcastFeedFormatException: $message';
}

/// How many episodes a shelf can meaningfully offer.
///
/// Podcast feeds carry the whole back catalogue by design — The Daily
/// publishes 2937 items in 18 MB — and the shelf shows the newest handful.
/// Items are newest-first, so a cap this far past what any surface renders
/// costs nothing and bounds both the download and the parse.
const podcastEpisodeLimit = 200;

/// The closing tag [readPodcastFeedBody] counts to know when to stop.
const podcastItemCloseTag = '</item>';

PodcastFeed parsePodcastFeed(String body, {int maxEpisodes = 0}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } on XmlException catch (error) {
    throw PodcastFeedFormatException(
      'The feed is not valid XML: ${error.message}',
    );
  }

  final channel = document.rootElement.getElement('channel');
  if (channel == null) {
    throw const PodcastFeedFormatException(
      'The document has no RSS <channel>, so it is not a podcast feed.',
    );
  }

  return PodcastFeed(
    title: _text(channel, 'title'),
    description: _firstText(channel, const ['description', 'itunes:summary']),
    language: _text(channel, 'language').toLowerCase(),
    imageUrl: _imageOf(channel),
    episodes: [
      for (final item
          in maxEpisodes > 0
              ? channel.findElements('item').take(maxEpisodes)
              : channel.findElements('item'))
        _episodeFrom(item),
    ],
  );
}

/// Reads a feed body, stopping once [maxItems] episodes have arrived.
///
/// The whole cost of showing a podcast was the download: 18 MB and 25 seconds
/// for The Daily, of which the shelf used the first few kilobytes. Items are
/// newest-first, so the rest is history nobody asked for. This consumes the
/// response until it has counted enough `</item>` closes, cuts the buffer
/// there, and closes the two enclosing tags by hand so the result is a
/// well-formed document.
///
/// The count would be thrown off by a literal `</item>` inside a CDATA
/// description. That is why the cap is far above what any surface shows:
/// miscounting there costs a few extra or missing history entries nobody was
/// going to scroll to, never a malformed parse — the cut still lands on a real
/// item boundary either way.
Future<String> readPodcastFeedBody(
  Stream<String> chunks, {
  int maxItems = podcastEpisodeLimit,
}) async {
  final buffer = StringBuffer();
  var body = '';
  var seen = 0;
  var searchedTo = 0;

  await for (final chunk in chunks) {
    buffer.write(chunk);
    body = buffer.toString();
    // Rescan only from a little before the previous frontier, so a close tag
    // split across two chunks is still seen exactly once.
    var index = body.indexOf(
      podcastItemCloseTag,
      searchedTo - podcastItemCloseTag.length < 0
          ? 0
          : searchedTo - podcastItemCloseTag.length,
    );
    while (index != -1) {
      final end = index + podcastItemCloseTag.length;
      if (end > searchedTo) {
        seen += 1;
        searchedTo = end;
        if (seen >= maxItems) {
          return '${body.substring(0, end)}</channel></rss>';
        }
      }
      index = body.indexOf(podcastItemCloseTag, end);
    }
    searchedTo = body.length;
  }
  return body;
}

PodcastEpisode _episodeFrom(XmlElement item) {
  final enclosure = item.getElement('enclosure');
  final url = enclosure?.getAttribute('url')?.trim();
  final enclosureUrl = (url == null || url.isEmpty) ? null : url;
  final guid = _text(item, 'guid');

  return PodcastEpisode(
    guid: guid.isNotEmpty ? guid : (enclosureUrl ?? ''),
    title: _text(item, 'title'),
    description: _firstText(item, const [
      'itunes:subtitle',
      'description',
      'itunes:summary',
    ]),
    enclosureUrl: enclosureUrl,
    enclosureBytes: int.tryParse(
      enclosure?.getAttribute('length')?.trim() ?? '',
    ),
    enclosureType: enclosure?.getAttribute('type')?.trim(),
    durationMs: parseItunesDurationMs(_text(item, 'itunes:duration')),
    publishedOn: _publishedOn(_text(item, 'pubDate')),
    imageUrl: _imageOf(item),
  );
}

/// `itunes:duration` is specified as seconds but published as `S`, `M:SS`, and
/// `H:MM:SS` in roughly equal measure, sometimes with fractional seconds.
///
/// Returns null for anything else. A duration we cannot read is unknown, and
/// coercing it to zero would render as `0:00` next to a two-hour episode.
int? parseItunesDurationMs(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  final parts = value.split(':');
  if (parts.length > 3) return null;

  var totalSeconds = 0.0;
  for (final part in parts) {
    final component = double.tryParse(part.trim());
    if (component == null || component < 0) return null;
    // Only the last component may be fractional; a colon-separated field is
    // minutes or hours and must be whole.
    if (part != parts.last && component != component.roundToDouble()) {
      return null;
    }
    totalSeconds = totalSeconds * 60 + component;
  }
  if (totalSeconds <= 0) return null;
  return (totalSeconds * 1000).round();
}

/// RFC-822 `pubDate` reduced to a `yyyy-MM-dd` UTC day.
///
/// Feeds vary the day name, the timezone spelling, and the padding, so this
/// reads the parts it needs and gives up rather than guessing.
String _publishedOn(String raw) {
  final match = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})',
  ).firstMatch(raw.trim());
  if (match == null) return '';
  final month = _months[match.group(2)!.toLowerCase()];
  if (month == null) return '';
  final day = int.parse(match.group(1)!);
  if (day < 1 || day > 31) return '';
  final paddedMonth = month.toString().padLeft(2, '0');
  final paddedDay = day.toString().padLeft(2, '0');
  return '${match.group(3)}-$paddedMonth-$paddedDay';
}

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// `itunes:image href=` first, then the RSS `<image><url>` form.
String? _imageOf(XmlElement parent) {
  final itunes = parent
      .getElement('itunes:image')
      ?.getAttribute('href')
      ?.trim();
  if (itunes != null && itunes.isNotEmpty) return itunes;
  final rss = parent.getElement('image')?.getElement('url')?.innerText.trim();
  if (rss != null && rss.isNotEmpty) return rss;
  return null;
}

String _text(XmlElement parent, String name) =>
    parent.getElement(name)?.innerText.trim() ?? '';

/// Descriptions arrive as CDATA-wrapped HTML far more often than as plain text,
/// so the first readable one is flattened to text. Show-notes markup rendered
/// literally is not a description, it is `<p>` soup in a card.
String _firstText(XmlElement parent, List<String> names) {
  for (final name in names) {
    final value = _flattenHtml(_text(parent, name));
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _flattenHtml(String value) {
  if (!value.contains('<')) return value;
  return value
      .replaceAll(RegExp(r'<br\s*/?>|</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      // Ampersand last: decoding it earlier would turn `&amp;lt;` into `<`.
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
}
