import 'practice.dart';

class CaptureListeningInboxItemInput {
  const CaptureListeningInboxItemInput({
    required this.sessionId,
    required this.target,
    required this.anchors,
    required this.subtitleSnapshot,
    this.label,
    this.contextBefore,
    this.contextAfter,
    this.expiresInDays,
  });

  final String sessionId;
  final PracticeTarget target;
  final List<PracticeAnchor> anchors;
  final String subtitleSnapshot;
  final String? label;
  final String? contextBefore;
  final String? contextAfter;
  final int? expiresInDays;

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'target': target.toJson(),
    'anchors': anchors.map((value) => value.toJson()).toList(growable: false),
    'label': label,
    'subtitle_snapshot': subtitleSnapshot,
    'context_before': contextBefore,
    'context_after': contextAfter,
    'expires_in_days': expiresInDays,
  };
}

class ProcessListeningInboxItemInput {
  const ProcessListeningInboxItemInput({required this.resolution});

  final String resolution;

  Map<String, dynamic> toJson() => {'resolution': resolution};
}

class ListeningInboxItem {
  const ListeningInboxItem({
    required this.id,
    this.sessionId,
    this.mediaId,
    this.trackId,
    required this.target,
    required this.anchors,
    this.label,
    required this.subtitleSnapshot,
    this.contextBefore,
    this.contextAfter,
    required this.capturedAtMs,
    this.expiresAtMs,
    required this.status,
    this.resolution,
    required this.reviewItemIds,
    this.practiceItemId,
    required this.updatedAtMs,
  });

  factory ListeningInboxItem.fromJson(Map<String, dynamic> json) =>
      ListeningInboxItem(
        id: json['id'] as String,
        sessionId: json['session_id'] as String?,
        mediaId: json['media_id'] as String?,
        trackId: json['track_id'] as String?,
        target: PracticeTarget.fromJson(json['target'] as Map<String, dynamic>),
        anchors: ((json['anchors'] as List<dynamic>?) ?? const [])
            .map(
              (value) => PracticeAnchor.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        label: json['label'] as String?,
        subtitleSnapshot: json['subtitle_snapshot'] as String,
        contextBefore: json['context_before'] as String?,
        contextAfter: json['context_after'] as String?,
        capturedAtMs: json['captured_at_ms'] as int,
        expiresAtMs: json['expires_at_ms'] as int?,
        status: json['status'] as String,
        resolution: json['resolution'] as String?,
        reviewItemIds: ((json['review_item_ids'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
        practiceItemId: json['practice_item_id'] as String?,
        updatedAtMs: json['updated_at_ms'] as int,
      );

  final String id;
  final String? sessionId;
  final String? mediaId;
  final String? trackId;
  final PracticeTarget target;
  final List<PracticeAnchor> anchors;
  final String? label;
  final String subtitleSnapshot;
  final String? contextBefore;
  final String? contextAfter;
  final int capturedAtMs;
  final int? expiresAtMs;
  final String status;
  final String? resolution;
  final List<String> reviewItemIds;
  final String? practiceItemId;
  final int updatedAtMs;

  int? get playbackStartMs => target.startMs ?? _anchorStartMs;
  int? get playbackEndMs => target.endMs ?? _anchorEndMs;

  int? get _anchorStartMs {
    final values = anchors
        .map((value) => value.startMs)
        .whereType<int>()
        .toList(growable: false);
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left < right ? left : right);
  }

  int? get _anchorEndMs {
    final values = anchors
        .map((value) => value.endMs)
        .whereType<int>()
        .toList(growable: false);
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left > right ? left : right);
  }
}
