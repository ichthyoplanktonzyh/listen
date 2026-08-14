import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

String _sha256Hex(String value) => sha256.convert(utf8.encode(value)).toString();

/// Parses RSS and Atom feeds into a typed, format-agnostic feed.
///
/// Podcast feeds, blog feeds, and YouTube's channel feeds are all XML
/// documents that list items; only the shape and the namespace differ. One
/// parser means one set of rules for "what did the feed actually say" and no
/// second copy of the item-extraction logic to drift.
///
/// Real XML parsing rather than regular expressions is not fussiness. Podcast
/// feeds carry CDATA-wrapped HTML descriptions, `itunes:` and `podcast:`
/// namespaces, attributes in arbitrary order, and channel-level elements that
/// repeat inside items. A regex that reads `<title>` off an `<item>` segment
/// picks up the channel title on a feed whose item happens to omit its own —
/// which is exactly what the old YouTube path did, and why its entries were
/// forever missing titles and thumbnails.
///
/// Anything the feed does not state stays null. A missing duration is not zero
/// and not a guessed five minutes: the surface has to say it does not know.
enum FeedFormat { rss, atom }

/// A parsed feed: channel-level facts plus the items, newest-first as
/// published.
class ParsedFeed {
  const ParsedFeed({
    required this.format,
    required this.title,
    required this.description,
    required this.language,
    required this.imageUrl,
    required this.items,
  });

  final FeedFormat format;
  final String title;
  final String description;

  /// BCP-47-ish tag as published (`en`, `en-us`, `zh-cn`), lowercased. Empty
  /// when the feed omits it — we do not assume English.
  final String language;

  final String? imageUrl;
  final List<ParsedFeedItem> items;
}

/// One item of a parsed feed.
///
/// [id] is the publisher-declared item identity — the feed's `<guid>` or Atom
/// `<id>` — when the feed offered one, and null when it did not. A null id is
/// not an identity the parser may invent: the discovery layer turns it into an
/// explicitly marked `source_scoped_surrogate` scoped to the feed it came
/// from, never into the entry URL masquerading as a feed item id.
class ParsedFeedItem {
  const ParsedFeedItem({
    required this.id,
    required this.title,
    required this.description,
    required this.publishedOn,
    this.enclosureUrl,
    this.enclosureBytes,
    this.enclosureType,
    this.entryUrl,
    this.publisherId,
    this.durationMs,
    this.imageUrl,
    this.viewCount = 0,
  });

  /// The feed-declared GUID or Atom id, or null when the feed published none.
  /// Null means the publisher gave this item no stable identity; the caller
  /// must synthesize a source-scoped surrogate key (never reuse this field
  /// for a URL).
  final String? id;
  final String title;
  final String description;

  /// The publisher-provided media URL, or null when the item carries no
  /// enclosure. Such items exist (notes-only posts) and are not acquirable as
  /// media.
  final String? enclosureUrl;

  /// `length` attribute, in bytes. Advisory: hosts that splice audio at request
  /// time routinely report a length that does not match what they send.
  final int? enclosureBytes;

  final String? enclosureType;

  /// The article link the feed offered for this item (RSS `<link>`, Atom
  /// `link rel="alternate"`). Distinct from [enclosureUrl]: a document entry
  /// is acquired through its page, not through a media URL.
  final String? entryUrl;

  /// The publisher the feed named (RSS `<author>`/`dc:creator`, Atom
  /// `<author><name>`). Evidence about the item, not its identity.
  final String? publisherId;

  /// From `itunes:duration` or an Atom `media:content` duration, null when
  /// absent or unparseable.
  final int? durationMs;

  /// `yyyy-MM-dd` in UTC, or empty when the feed omits or mangles the date.
  final String publishedOn;

  final String? imageUrl;

  /// A play/view count the feed reported (YouTube's `media:statistics`). Zero
  /// when the source does not report one — never a fabricated figure.
  final int viewCount;
}

/// Thrown when [parseFeed] is handed something that is not an RSS or Atom
/// feed. Callers surface this as a failed source rather than an empty one:
/// "this feed has no items" and "this URL is not a feed" are different facts.
class FeedFormatException implements Exception {
  const FeedFormatException(this.message);

  final String message;

  @override
  String toString() => 'FeedFormatException: $message';
}

/// How many items a shelf can meaningfully offer.
///
/// Podcast feeds carry the whole back catalogue by design — The Daily
/// publishes 2937 items in 18 MB — and the shelf shows the newest handful.
/// Items are newest-first, so a cap this far past what any surface renders
/// costs nothing and bounds both the download and the parse.
const feedItemLimit = 200;

/// The closing tag [readFeedBody] counts to know when to stop, per format.
String feedItemCloseTag(FeedFormat format) => switch (format) {
  FeedFormat.rss => '</item>',
  FeedFormat.atom => '</entry>',
};

/// The stable surrogate item key for a feed item that declared no GUID or
/// Atom id.
///
/// A feed that omits its item ids leaves the app no honest identity to reuse,
/// so the key is explicit about what it is — `source_scoped_surrogate:` — and
/// about where it came from: it hashes the source plus the publisher's stable
/// reference to the item (the entry URL, or the enclosure URL, or the
/// title-and-date when neither URL exists). Scoping by source means the same
/// URL in two feeds never collides; hashing the reference means a re-read of
/// the same item produces the same key, while a publisher who changes the
/// reference changes the key — the app then treats it as a different item,
/// never as metadata drift on the same one.
String sourceScopedSurrogateId({
  required String sourceId,
  required ParsedFeedItem item,
}) {
  final material = item.entryUrl ?? item.enclosureUrl;
  final basis = material ?? '${item.title}\u0000${item.publishedOn}';
  return 'source_scoped_surrogate:${_sha256Hex('$sourceId\u0000$basis')}';
}ParsedFeed parseFeed(
  String body, {
  int maxItems = 0,
  FeedFormat? assumeFormat,
}) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } on XmlException catch (error) {
    throw FeedFormatException('The feed is not valid XML: ${error.message}');
  }

  final format = assumeFormat ?? detectFeedFormat(document);
  return switch (format) {
    FeedFormat.rss => _parseRss(document, maxItems),
    FeedFormat.atom => _parseAtom(document, maxItems),
  };
}

/// Reads a feed body, stopping once [maxItems] items have arrived.
///
/// The whole cost of showing a podcast was the download: 18 MB and 25 seconds
/// for The Daily, of which the shelf used the first few kilobytes. Items are
/// newest-first, so the rest is history nobody asked for. This consumes the
/// response until it has counted enough item close tags, cuts the buffer
/// there, and closes the two enclosing tags by hand so the result is a
/// well-formed document.
///
/// The close tag to count is not known before the body arrives — the format
/// is decided by the parser afterwards — so both are counted and the one that
/// reaches the cap first wins. A feed is practically never a mix of both, and
/// when it is, the dominant shape is the one a person is browsing anyway.
///
/// The count would be thrown off by a literal `</item>` or `</entry>` inside a
/// CDATA description. That is why the cap is far above what any surface shows:
/// miscounting there costs a few extra or missing history entries nobody was
/// going to scroll to, never a malformed parse — the cut still lands on a real
/// item boundary either way.
Future<String> readFeedBody(
  Stream<String> chunks, {
  int maxItems = feedItemLimit,
}) async {
  const rssClose = '</item>';
  const atomClose = '</entry>';
  final buffer = StringBuffer();
  var body = '';
  var rssSeen = 0;
  var atomSeen = 0;
  var searchedTo = 0;

  await for (final chunk in chunks) {
    buffer.write(chunk);
    body = buffer.toString();
    // Rescan only from a little before the previous frontier, so a close tag
    // split across two chunks is still seen exactly once.
    var rssIndex = body.indexOf(
      rssClose,
      searchedTo - rssClose.length < 0 ? 0 : searchedTo - rssClose.length,
    );
    while (rssIndex != -1) {
      final end = rssIndex + rssClose.length;
      if (end > searchedTo) {
        rssSeen += 1;
        searchedTo = end;
        if (rssSeen >= maxItems) {
          return '${body.substring(0, end)}</channel></rss>';
        }
      }
      rssIndex = body.indexOf(rssClose, end);
    }
    var atomIndex = body.indexOf(
      atomClose,
      searchedTo - atomClose.length < 0 ? 0 : searchedTo - atomClose.length,
    );
    while (atomIndex != -1) {
      final end = atomIndex + atomClose.length;
      if (end > searchedTo) {
        atomSeen += 1;
        searchedTo = end;
        if (atomSeen >= maxItems) {
          return '${body.substring(0, end)}</feed>';
        }
      }
      atomIndex = body.indexOf(atomClose, end);
    }
    searchedTo = body.length;
  }
  return body;
}

/// Which feed shape [document] holds, from its root element.
///
/// RSS is `<rss>`; Atom is `<feed xmlns="http://www.w3.org/2005/Atom">`. The
/// Atom namespace is checked by local name so a feed that writes its
/// namespace on every element still lands here.
FeedFormat detectFeedFormat(XmlDocument document) {
  final root = document.rootElement;
  final local = root.name.local;
  if (local == 'rss' || local == 'rdf') return FeedFormat.rss;
  if (local == 'feed') return FeedFormat.atom;
  throw FeedFormatException(
    'The document root is <$local>, so it is not an RSS or Atom feed.',
  );
}

ParsedFeed _parseRss(XmlDocument document, int maxItems) {
  final channel = document.rootElement.getElement('channel');
  if (channel == null) {
    throw const FeedFormatException(
      'The document has no RSS <channel>, so it is not a feed.',
    );
  }
  final items = maxItems > 0
      ? channel.findElements('item').take(maxItems)
      : channel.findElements('item');
  return ParsedFeed(
    format: FeedFormat.rss,
    title: _text(channel, 'title'),
    description: _firstText(channel, const ['description', 'itunes:summary']),
    language: _text(channel, 'language').toLowerCase(),
    imageUrl: _rssImageOf(channel),
    items: [for (final item in items) _rssItemFrom(item)],
  );
}

ParsedFeedItem _rssItemFrom(XmlElement item) {
  final enclosure = item.getElement('enclosure');
  final url = enclosure?.getAttribute('url')?.trim();
  final enclosureUrl = (url == null || url.isEmpty) ? null : url;
  final guid = _text(item, 'guid');
  final link = _text(item, 'link');

  return ParsedFeedItem(
    id: guid.isNotEmpty ? guid : null,
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
    entryUrl: link.isEmpty ? null : link,
    publisherId: _firstText(item, const ['author', 'dc:creator']),
    durationMs: parseItunesDurationMs(_text(item, 'itunes:duration')),
    publishedOn: _publishedOnRfc822(_text(item, 'pubDate')),
    imageUrl: _rssImageOf(item),
  );
}

ParsedFeed _parseAtom(XmlDocument document, int maxItems) {
  final feed = document.rootElement;
  final items = maxItems > 0
      ? _elementsByLocal(feed, 'entry').take(maxItems)
      : _elementsByLocal(feed, 'entry');
  return ParsedFeed(
    format: FeedFormat.atom,
    title: _atomText(feed, 'title'),
    description: _atomText(feed, 'subtitle'),
    language: _atomXmlLanguage(document).toLowerCase(),
    imageUrl: _atomImageOf(feed),
    items: [for (final entry in items) _atomItemFrom(entry)],
  );
}

ParsedFeedItem _atomItemFrom(XmlElement entry) {
  final id = _atomText(entry, 'id');
  final videoId = _text(entry, 'yt:videoId');
  final link = _atomLinkOf(entry, 'alternate');
  final media = _atomMediaOf(entry);

  return ParsedFeedItem(
    // YouTube's Atom ids are `yt:video:ABC123`; the `<yt:videoId>` is the
    // canonical identity the rest of the app already speaks. Without either
    // the entry declares no identity and the caller synthesizes a surrogate.
    id: videoId.isNotEmpty ? videoId : (id.isNotEmpty ? id : null),
    title: _atomText(entry, 'title'),
    description: _atomText(entry, 'summary'),
    enclosureUrl: media?.url,
    enclosureBytes: media?.bytes,
    enclosureType: media?.type,
    entryUrl: link.isEmpty ? null : link,
    publisherId: _atomText(entry, 'author', child: 'name'),
    durationMs: null,
    publishedOn: _publishedOnAtom(_atomText(entry, 'published')),
    imageUrl: _atomImageOf(entry),
    viewCount: _atomViewCount(entry),
  );
}

/// Atom's media:content is a self-describing element: a URL with a `type`
/// and a `length`, exactly the enclosure facts RSS puts in an attribute.
({String url, int? bytes, String? type})? _atomMediaOf(XmlElement entry) {
  final content = _elementsByLocal(entry, 'content').firstOrNull;
  final media = _elementsByName(entry, 'media:content').firstOrNull;
  final node = media ?? content;
  if (node == null) return null;
  final url = node.getAttribute('url')?.trim();
  if (url == null || url.isEmpty) return null;
  final type = node.getAttribute('type')?.trim();
  final length = int.tryParse(node.getAttribute('length')?.trim() ?? '');
  final urlType = (type == null || type.isEmpty)
      ? null
      : type;
  return (url: url, bytes: length, type: urlType);
}

String _atomLinkOf(XmlElement entry, String rel) {
  for (final link in _elementsByLocal(entry, 'link')) {
    final linkRel = link.getAttribute('rel')?.trim();
    if (linkRel == rel || (rel == 'alternate' && linkRel == null)) {
      final href = link.getAttribute('href')?.trim();
      if (href != null && href.isNotEmpty) return href;
    }
  }
  return '';
}

int _atomViewCount(XmlElement entry) {
  final stats = _elementsByName(entry, 'media:statistics').firstOrNull;
  final views = stats?.getAttribute('views')?.trim();
  return views == null ? 0 : int.tryParse(views) ?? 0;
}

String _atomImageOf(XmlElement parent) {
  final thumbnail = _elementsByName(parent, 'media:thumbnail').firstOrNull;
  final url = thumbnail?.getAttribute('url')?.trim();
  if (url != null && url.isNotEmpty) return url;
  final image = _elementsByLocal(parent, 'icon').firstOrNull;
  final icon = image?.innerText.trim();
  return (icon == null || icon.isEmpty) ? '' : icon;
}

/// The feed's `xml:lang`, which Atom carries on the root element.
String _atomXmlLanguage(XmlDocument document) =>
    document.rootElement.getAttribute('lang') ??
    document.rootElement.getAttribute('xml:lang') ??
    '';

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
String _publishedOnRfc822(String raw) {
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

/// Atom's ISO-8601 `published` reduced to a `yyyy-MM-dd` UTC day.
String _publishedOnAtom(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(raw.trim());
  if (match == null) return '';
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return '';
  return '$year-${match.group(2)}-${match.group(3)}';
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
String? _rssImageOf(XmlElement parent) {
  final itunes = parent
      .getElement('itunes:image')
      ?.getAttribute('href')
      ?.trim();
  if (itunes != null && itunes.isNotEmpty) return itunes;
  final rss = parent.getElement('image')?.getElement('url')?.innerText.trim();
  if (rss != null && rss.isNotEmpty) return rss;
  return null;
}

/// Atom elements carry a default namespace, so a bare name match would find
/// nothing: `entry` is stored as `{http://www.w3.org/2005/Atom}entry`. Match
/// the local name and ignore the namespace — Atom is the only family a
/// `feed` root can be.
List<XmlElement> _elementsByLocal(XmlElement parent, String local) => [
  for (final child in parent.children.whereType<XmlElement>())
    if (child.name.local == local) child,
];

/// Namespaced extension elements (`media:content`, `yt:videoId`) match by
/// their prefixed qualified name, which is how they are written in the wire.
List<XmlElement> _elementsByName(XmlElement parent, String name) =>
    parent.findElements(name).toList();

String _text(XmlElement parent, String name) =>
    parent.getElement(name)?.innerText.trim() ?? '';

/// Atom text elements may nest (`<title type="html"><![CDATA[…]]></title>`)
/// and carry the default namespace; [child] walks a structured element such
/// as `<author><name>`.
String _atomText(XmlElement parent, String local, {String? child}) {
  for (final element in _elementsByLocal(parent, local)) {
    if (child != null) {
      final named = _elementsByLocal(element, child).firstOrNull;
      final value = named?.innerText.trim() ?? '';
      if (value.isNotEmpty) return value;
      continue;
    }
    final value = element.innerText.trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

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
