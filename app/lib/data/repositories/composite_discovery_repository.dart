import '../../models/discovery.dart';
import 'discovery_repository.dart';
import 'feed_discovery_repository.dart';
import 'media_import_repository.dart';

/// Presents several source families as one catalog.
///
/// Each family answers for its own sources: a feed (podcast or article/blog)
/// is fetched and parsed here in the app, a YouTube channel goes through its
/// own Atom feed and, for acquisition, an external tool. Keeping them behind
/// separate repositories is what makes it possible to change one family's
/// policy — or switch it off — without touching the journey above.
///
/// Feed sources are listed first. The first channel a new learner lands on
/// should be one whose whole path, listing through acquisition, is something
/// the publisher offered.
final class CompositeDiscoveryRepository implements DiscoveryRepository {
  CompositeDiscoveryRepository(this._feeds, this._youtube);

  /// Concrete rather than the interface: the composite routes on
  /// [FeedDiscoveryRepository.owns], which is not part of the shared
  /// interface because ownership is this family's own business.
  final FeedDiscoveryRepository _feeds;

  final DiscoveryRepository _youtube;

  @override
  Future<List<ContentSource>> sources() async {
    final feedSources = await _feeds.sources();
    final youtubeSources = await _youtube.sources();
    return List.unmodifiable([...feedSources, ...youtubeSources]);
  }

  @override
  Future<List<DiscoveryItem>> entriesFor(String sourceId) =>
      _ownerOf(sourceId).entriesFor(sourceId);

  @override
  Future<DiscoveryItem> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => _youtube.resolveCustomVideo(url, importRepo);

  /// One paste box for both families: a YouTube address goes to the channel
  /// resolver, anything else is tried as a feed. Guessing wrong is visible
  /// immediately — the feed either parses or the subscribe fails.
  @override
  Future<ContentSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) => _looksLikeYoutube(url)
      ? _youtube.resolveCustomChannel(url, importRepo)
      : _feeds.resolveCustomChannel(url, importRepo);

  /// A source id the feed side does not claim belongs to YouTube, whose
  /// ids are opaque channel identifiers rather than URLs.
  DiscoveryRepository _ownerOf(String sourceId) =>
      _feeds.owns(sourceId) ? _feeds : _youtube;
}

bool _looksLikeYoutube(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  return host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com');
}
