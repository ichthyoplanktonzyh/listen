import '../models/timeline.dart';

/// How the transcript shows the two subtitle tracks against each other.
///
/// A learner reading a foreign transcript wants all three of these at
/// different moments — the original alone to test themselves, both to check,
/// the translation alone to get the gist quickly — and wants to switch between
/// them constantly. Before this existed the second track only ever appeared
/// over the video, so the transcript, which is where the reading actually
/// happens, had no translation at all.
enum TranscriptTranslation {
  /// The original only.
  source,

  /// The original with its translation underneath.
  bilingual,

  /// The translation only.
  translation;

  /// The persisted value. Stored as a string so an unknown future mode
  /// degrades to the default instead of failing to parse.
  String get storageValue => name;

  static TranscriptTranslation fromStorage(Object? value) =>
      TranscriptTranslation.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => TranscriptTranslation.bilingual,
      );

  bool get showsSource => this != TranscriptTranslation.translation;
  bool get showsTranslation => this != TranscriptTranslation.source;
}

/// The secondary-track text that lines up with [cue], or null when nothing
/// does.
///
/// The two tracks are independent files with independent offsets, so they do
/// not share sentence ids and cannot be zipped by index — a translation track
/// routinely merges or splits sentences relative to the original. Overlap in
/// media time is the only relationship that actually holds, so that is what is
/// matched on, and every secondary line that overlaps is joined rather than
/// just the first: a merged translation line belongs to both originals it
/// covers.
///
/// Returning null is meaningful and callers must not paper over it: it means
/// this sentence has no translation, which is different from having one that
/// is empty.
String? translationForCue({
  required Cue cue,
  required List<Cue> secondaryCues,
  Duration primaryOffset = Duration.zero,
  Duration secondaryOffset = Duration.zero,
}) {
  final start = cue.start + primaryOffset;
  final end = cue.end + primaryOffset;
  final matched = <String>[];
  for (final candidate in secondaryCues) {
    final candidateStart = candidate.start + secondaryOffset;
    final candidateEnd = candidate.end + secondaryOffset;
    // Touching at a boundary is not overlapping: a secondary line that ends
    // exactly where this one starts belongs to the sentence before.
    if (candidateStart >= end || candidateEnd <= start) continue;
    final text = candidate.text.trim();
    if (text.isNotEmpty) matched.add(text);
  }
  return matched.isEmpty ? null : matched.join(' ');
}
