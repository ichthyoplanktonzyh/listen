part of '../types.dart';

// Content fit, media items, library/triage.
// Split out of types.dart (mechanical decomposition).

/// Registered media and the user-authored listening triage facts returned by
/// the media-library endpoints.
/// Registered media as served by `GET /v1/media` (nested in
/// [MediaLibraryEntry]).
class MediaItem {
  const MediaItem({
    required this.id,
    required this.path,
    required this.fingerprint,
    required this.title,
    required this.kind,
    required this.durationMs,
    required this.availability,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.retainedAtMs,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
    id: json['id'] as String,
    path: json['path'] as String,
    fingerprint: json['fingerprint'] as String,
    title: json['title'] as String,
    kind: json['kind'] as String,
    durationMs: json['duration'] as int?,
    availability: json['availability'] as String,
    createdAtMs: json['created_at_ms'] as int,
    updatedAtMs: json['updated_at_ms'] as int,
    // Only rows in the Personal Library carry a retention timestamp;
    // Temporary Material has none.
    retainedAtMs: json['retained_at_ms'] as int?,
  );

  final String id;
  final String path;
  final String fingerprint;
  final String title;
  final String kind;
  final int? durationMs;
  final String availability;
  final int createdAtMs;
  final int updatedAtMs;

  /// When this media entered the Personal Library (library
  /// membership). Null means the media is Temporary Material — open or
  /// scanned, but not explicitly kept.
  final int? retainedAtMs;

  /// Whether this media is currently in the Personal Library.
  bool get isRetained => retainedAtMs != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'fingerprint': fingerprint,
    'title': title,
    'kind': kind,
    'duration': durationMs,
    'availability': availability,
    'retained_at_ms': retainedAtMs,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

/// One media-library row with explicit user-authored listening triage facts.
class MediaLibraryEntry {
  const MediaLibraryEntry({
    required this.media,
    required this.primaryTrackId,
    required this.triageIntent,
  });

  factory MediaLibraryEntry.fromJson(Map<String, dynamic> json) =>
      MediaLibraryEntry(
        media: MediaItem.fromJson(
          Map<String, dynamic>.from(json['media'] as Map),
        ),
        primaryTrackId: json['primary_track_id'] as String?,
        triageIntent: json['triage_intent'] as String?,
      );

  final MediaItem media;
  final String? primaryTrackId;

  /// 'pin_extensive' | 'pin_intensive' | 'defer' | 'graduated' | null.
  final String? triageIntent;

  Map<String, dynamic> toJson() => {
    'media': media.toJson(),
    'primary_track_id': primaryTrackId,
    'triage_intent': triageIntent,
  };
}
