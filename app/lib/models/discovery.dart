// Models for the media aggregation discovery flow.

enum DownloadState { none, downloading, done }

enum MediaSourceType { youtube, podcast }

enum PackageStatus { 
  unknown,
  checking,
  available,
  notAvailable,
}

enum TranscriptionStatus {
  idle,
  preparing,
  transcribing,
  completed,
  failed,
}

/// Cover artwork is a tone from the active color scheme.
enum ChannelCoverTone { green, amber, blue, slate, rose }

class MediaSource {
  const MediaSource({
    required this.id,
    required this.name,
    required this.language,
    required this.description,
    required this.cover,
    required this.type,
    required this.avatarUrl,
  });

  final String id;
  final String name;
  final String language;
  final String description;
  final ChannelCoverTone cover;
  final MediaSourceType type;
  final String? avatarUrl;
}

class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.description,
    required this.durationMs,
    required this.language,
    required this.publishedOn,
    required this.thumbnailUrl,
    required this.viewCount,
    required this.hasPackage,
    this.videoUrl,
    this.localPath,
  });

  final String id;
  final String sourceId;
  final String title;
  final String description;
  final int durationMs;
  final String language;
  final String publishedOn;
  final String? thumbnailUrl;
  final int viewCount;
  final bool hasPackage;
  final String? videoUrl;
  final String? localPath;
}
