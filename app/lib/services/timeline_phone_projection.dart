/// Projects the phone timelines of Core's LLTimeline export into the
/// per-sentence phones the sound layer's `actual` reference renders.
///
/// This lives at the service boundary, not on `LLTimelineDocument`: the wire
/// map is parsed here so the display model does not grow a field — and a
/// typed field could not be parsed safely anyway. Core's export omits keys on
/// some phone timeline shapes (a committed contract fixture carries entries
/// with no `track_id`), so a strict typed parse of the family would throw and
/// take the whole document — rhythm frames included — down with it.
///
/// The rules mirror what the sentence actually needs:
///
/// * an active timeline for a sentence wins; otherwise its candidates are
///   read, because Core's package import contract lands every package
///   resource as a candidate and such a track has no active timeline at all;
/// * archived timelines are never read;
/// * a phone with no token index is dropped — it cannot be tied to a word;
/// * a malformed timeline or phone drops that item alone.
library;

import '../models/timeline.dart';

const _archived = 'archived';
const _active = 'active';

/// Phones by sentence id, ordered by time within each sentence.
Map<String, List<DetectedPhone>> phonesBySentenceFromTimelineJson(
  Map<String, dynamic> documentJson,
) {
  final timelines = documentJson['phone_timelines'];
  if (timelines is! List) return const {};

  final activeBySentence = <String, List<DetectedPhone>>{};
  final candidateBySentence = <String, List<DetectedPhone>>{};
  for (final value in timelines) {
    if (value is! Map) continue;
    final timeline = Map<String, dynamic>.from(value);
    final sentenceId = timeline['sentence_id'];
    final status = timeline['status'];
    if (sentenceId is! String || sentenceId.isEmpty) continue;
    if (status is! String || status == _archived) continue;
    final phones = _phones(timeline['phones']);
    if (phones.isEmpty) continue;
    final target = status == _active ? activeBySentence : candidateBySentence;
    target.putIfAbsent(sentenceId, () => <DetectedPhone>[]).addAll(phones);
  }

  final result = <String, List<DetectedPhone>>{
    ...candidateBySentence,
    ...activeBySentence,
  };
  return Map.unmodifiable({
    for (final entry in result.entries)
      entry.key: List<DetectedPhone>.unmodifiable(
        entry.value..sort((a, b) => a.start.compareTo(b.start)),
      ),
  });
}

List<DetectedPhone> _phones(Object? values) {
  if (values is! List) return const [];
  final phones = <DetectedPhone>[];
  for (final value in values) {
    if (value is! Map) continue;
    try {
      final phone = DetectedPhone.fromJson(Map<String, dynamic>.from(value));
      if (phone.tokenIndex == null) continue;
      phones.add(phone);
    } on Object {
      continue;
    }
  }
  return phones;
}
