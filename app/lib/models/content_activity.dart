/// A locally selected, bounded piece of the current content.
///
/// The selection belongs to the content session. Speaking and Realtime adapt
/// it into their own launch types; neither feature owns the other's prompt.
class ContentSegmentSelection {
  const ContentSegmentSelection({
    required this.anchorCueId,
    required this.mediaId,
    required this.trackId,
    required this.startMs,
    required this.endMs,
    required this.language,
    required this.transcriptSnapshot,
  });

  final String anchorCueId;
  final String? mediaId;
  final String trackId;
  final int startMs;
  final int endMs;
  final String language;
  final String transcriptSnapshot;
}

enum ContentSpeakingActivity { retelling, shadowing, conversation }
