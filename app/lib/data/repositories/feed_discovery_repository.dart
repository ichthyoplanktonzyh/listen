import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/discovery.dart';
import '../../services/feed_parser.dart';
import '../../services/subscription_store.dart';
import 'discovery_repository.dart';
import 'media_import_repository.dart';

/// Discovery over RSS and Atom podcast and article feeds.
///
/// Feeds may offer media enclosures, article links, or both. Each item keeps
/// its own acquisition mode, so a permalink is fetched only when it is the
/// item's only usable content source.
///
/// A source id is the feed URL. For a feed the address is the stable thing to
/// point at; there is no separate channel identifier to prefer. The source
/// source id and the item id remain the canonical identities regardless of
/// whether the item points to media or an article page.
final class FeedDiscoveryRepository implements DiscoveryRepository {
  FeedDiscoveryRepository({
    HttpClient? client,
    String? starterAssetPath,
    SubscriptionStore? subscriptions,
  }) : _client = client ?? HttpClient(),
       _starterAssetPath = starterAssetPath ?? _defaultStarterAsset,
       _subscriptions = subscriptions ?? SubscriptionStore.inMemory();

  static const _defaultStarterAsset = 'assets/starter_feeds.json';

  final HttpClient _client;
  final String _starterAssetPath;

  /// Parsed feeds for this session.
  ///
  /// `entriesFor` used to refetch on every selection, so clicking away from a
  /// channel and back paid the whole download again. A feed's item list is
  /// the same for the minutes a person spends browsing it; refreshing it is a
  /// deliberate act, not a side effect of navigation.
  final Map<String, ParsedFeed> _feeds = {};

  List<ContentSource>? _starters;

  /// Subscribed feeds, durable when the composition root supplied a backed
  /// store. Held here only through the store so a restart cannot disagree with
  /// what is on screen.
  final SubscriptionStore _subscriptions;

  List<ContentSource> get _customSources =>
      _subscriptions.of(ContentSourceKind.podcast) +
      _subscriptions.of(ContentSourceKind.document);

  /// A feed source id is its feed URL, and YouTube channel ids are never
  /// URLs — so the shape answers this even before [sources] has been awaited
  /// and the starter list exists to search.
  bool owns(String sourceId) {
    final uri = Uri.tryParse(sourceId);
    if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
      return true;
    }
    return _starters?.any((source) => source.id == sourceId) == true ||
        _customSources.any((source) => source.id == sourceId);
  }

  @override
  Future<List<ContentSource>> sources() async {
    if (!_subscriptions.isLoaded) await _subscriptions.load();
    final starters = _starters ??= await _loadStarters();
    return List.unmodifiable([...starters, ..._customSources]);
  }

  Future<List<ContentSource>> _loadStarters() async {
    final raw = await rootBundle.loadString(_starterAssetPath);
    final decoded = jsonDecode(raw) as Map<dynamic, dynamic>;
    return [
      for (final entry in decoded['feeds'] as List<dynamic>)
        _sourceFromMap(entry as Map<dynamic, dynamic>),
    ];
  }

  /// Throws on transport, status or format failure rather than returning an
  /// empty list: "this feed has published nothing" and "we could not read the
  /// feed" must not render as the same screen.
  @override
  Future<List<DiscoveryItem>> entriesFor(String sourceId) async {
    final feed = await _fetchFeed(sourceId);
    return [
      for (final item in feed.items)
        if (item.enclosureUrl != null || item.entryUrl != null)
          _itemFrom(item, sourceId, feed.language),
    ];
  }

  /// A feed has no per-item subscribe action; an item is reached through its
  /// feed.
  @override
  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => throw const FeedFormatException(
    'A feed item is added by subscribing to its feed, not on its own.',
  );

  /// Subscribes to a feed pasted by the user. The feed is fetched and parsed
  /// before the source is added, so a bad URL fails here rather than becoming
  /// a channel that is permanently empty.
  @override
  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) async {
    final trimmed = url.trim();
    final feed = await _fetchFeed(trimmed);
    if (!feed.items.any(
      (item) => item.enclosureUrl != null || item.entryUrl != null,
    )) {
      throw const FeedFormatException(
        'This feed has no media enclosures or article links.',
      );
    }

    final source = ContentSource(
      id: trimmed,
      name: feed.title.isEmpty ? trimmed : feed.title,
      language: feed.language.isEmpty ? '' : feed.language,
      description: feed.description,
      cover: ChannelCoverTone.slate,
      kind: _kindOf(trimmed, feed),
      avatarUrl: feed.imageUrl,
    );

    await _subscriptions.add(source);
    return source;
  }

  /// Drops the cached feed for [sourceId] so the next read goes to the
  /// network. The refresh affordance is the caller's to offer.
  void forget(String sourceId) => _feeds.remove(sourceId);

  @override
  Future<void> refreshSource(String sourceId) async => forget(sourceId);

  /// The channel-level kind, for subscription and shelf presentation.
  ///
  /// The source kind describes its dominant shape; each item still decides
  /// independently whether it carries an enclosure or an article link.
  ContentSourceKind _kindOf(String sourceId, ParsedFeed feed) {
    if (_customSources.any((source) => source.id == sourceId)) {
      final subscribed = _customSources.firstWhere(
        (source) => source.id == sourceId,
      );
      return subscribed.kind;
    }
    return _kindForFeed(feed);
  }

  ContentSourceKind _kindForFeed(ParsedFeed feed) =>
      feed.items.any((item) => item.enclosureUrl != null)
      ? ContentSourceKind.podcast
      : ContentSourceKind.document;

  Future<ParsedFeed> _fetchFeed(String feedUrl) async {
    final cached = _feeds[feedUrl];
    if (cached != null) return cached;
    final feed = await _downloadFeed(feedUrl);
    _feeds[feedUrl] = feed;
    return feed;
  }

  Future<ParsedFeed> _downloadFeed(String feedUrl) async {
    final uri = Uri.parse(feedUrl);
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw const FeedFormatException(
        'A feed address must be an http or https URL.',
      );
    }

    final request = await _client
        .getUrl(uri)
        .timeout(const Duration(seconds: 15));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'The feed host answered ${response.statusCode}.',
        uri: uri,
      );
    }
    final body = await readFeedBody(response.transform(utf8.decoder));
    // Even a capped feed is hundreds of kilobytes of XML, and parsing it on
    // the UI isolate showed up as a dropped frame rather than as work.
    return Isolate.run(() => parseFeed(body, maxItems: feedItemLimit));
  }

  DiscoveryItem _itemFrom(
    ParsedFeedItem item,
    String sourceId,
    String feedLanguage,
  ) {
    // The canonical item identity is the feed-declared GUID/Atom id when the
    // feed published one; an item without one gets an explicitly marked
    // source-scoped surrogate key — never the entry or enclosure URL dressed
    // up as a feed item id.
    final itemId =
        item.id ?? sourceScopedSurrogateId(sourceId: sourceId, item: item);
    final hasEnclosure = item.enclosureUrl != null;
    return DiscoveryItem(
      id: itemId,
      sourceId: sourceId,
      title: item.title,
      description: item.description,
      durationMs: item.durationMs,
      language: feedLanguage,
      publishedOn: item.publishedOn,
      thumbnailUrl: item.imageUrl,
      viewCount: item.viewCount,
      acquisition: hasEnclosure
          ? AcquisitionMode.enclosure
          : item.entryUrl == null
          ? AcquisitionMode.none
          : AcquisitionMode.article,
      contentKind: hasEnclosure
          ? _kindFor(item.enclosureType)
          : ItemContentKind.article,
      mediaUrl: hasEnclosure ? item.enclosureUrl : null,
      entryUrl: item.entryUrl,
      publisherId: item.publisherId,
      mediaByteLength: item.enclosureBytes,
    );
  }

  ItemContentKind _kindFor(String? enclosureType) =>
      enclosureType != null && enclosureType.toLowerCase().startsWith('video/')
      ? ItemContentKind.video
      : ItemContentKind.audio;
}

ContentSource _sourceFromMap(Map<dynamic, dynamic> map) => ContentSource(
  id: map['url'] as String,
  name: map['name'] as String,
  language: map['language'] as String? ?? '',
  description: map['description'] as String? ?? '',
  cover: _coverFromName(map['cover'] as String? ?? ''),
  kind: ContentSourceKind.podcast,
  avatarUrl: null,
);

ChannelCoverTone _coverFromName(String name) => switch (name) {
  'green' => ChannelCoverTone.green,
  'amber' => ChannelCoverTone.amber,
  'blue' => ChannelCoverTone.blue,
  'rose' => ChannelCoverTone.rose,
  _ => ChannelCoverTone.slate,
};
