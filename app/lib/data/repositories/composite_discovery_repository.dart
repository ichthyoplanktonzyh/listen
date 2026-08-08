import '../../models/discovery.dart';
import 'discovery_repository.dart';
import 'media_import_repository.dart';
import 'podcast_discovery_repository.dart';

/// Presents several source families as one catalog.
///
/// Each family answers for its own sources: a podcast feed is fetched and
/// parsed here in the app, a YouTube channel goes through its own Atom feed
/// and, for acquisition, an external tool. Keeping them behind separate
/// repositories is what makes it possible to change one family's policy — or
/// switch it off — without touching the journey above.
///
/// Podcast sources are listed first. The first channel a new learner lands on
/// should be one whose whole path, listing through acquisition, is something
/// the publisher offered.
final class CompositeDiscoveryRepository implements DiscoveryRepository {
  CompositeDiscoveryRepository(this._podcasts, this._youtube);

  /// Concrete rather than the interface: the composite routes on
  /// [PodcastDiscoveryRepository.owns], which is not part of the shared
  /// interface because ownership is this family's own business.
  final PodcastDiscoveryRepository _podcasts;

  final DiscoveryRepository _youtube;

  @override
  Future<List<MediaSource>> sources() async {
    final podcastSources = await _podcasts.sources();
    final youtubeSources = await _youtube.sources();
    return List.unmodifiable([...podcastSources, ...youtubeSources]);
  }

  @override
  Future<List<MediaEntry>> entriesFor(String sourceId) =>
      _ownerOf(sourceId).entriesFor(sourceId);

  @override
  Future<MediaEntry> resolveCustomVideo(
    String url,
    MediaImportRepository importRepo,
  ) => _youtube.resolveCustomVideo(url, importRepo);

  /// One paste box for both families: a YouTube address goes to the channel
  /// resolver, anything else is tried as a podcast feed. Guessing wrong is
  /// visible immediately — the feed either parses or the subscribe fails.
  @override
  Future<MediaSource> resolveCustomChannel(
    String url,
    MediaImportRepository importRepo,
  ) => _looksLikeYoutube(url)
      ? _youtube.resolveCustomChannel(url, importRepo)
      : _podcasts.resolveCustomChannel(url, importRepo);

  /// A source id the podcast side does not claim belongs to YouTube, whose
  /// ids are opaque channel identifiers rather than URLs.
  DiscoveryRepository _ownerOf(String sourceId) =>
      _podcasts.owns(sourceId) ? _podcasts : _youtube;
}

bool _looksLikeYoutube(String url) {
  final host = Uri.tryParse(url.trim())?.host.toLowerCase() ?? '';
  return host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com');
}
