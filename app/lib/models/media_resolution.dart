/// Typed metadata for media resolved from an online source.
///
/// These are the yt-dlp fields the discovery flow needs, named instead of a
/// raw `Map` so controllers and repositories never handle transport text.
class ResolvedVideoDetails {
  const ResolvedVideoDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.durationMs,
    required this.viewCount,
    required this.thumbnail,
    required this.channelId,
    required this.uploadDate,
  });

  final String id;
  final String title;
  final String description;
  final int durationMs;
  final int viewCount;
  final String? thumbnail;
  final String channelId;
  final String uploadDate;
}

/// Typed identity of a YouTube channel resolved from a channel URL.
class ResolvedChannelDetails {
  const ResolvedChannelDetails({required this.id, required this.name});

  final String id;
  final String name;
}
