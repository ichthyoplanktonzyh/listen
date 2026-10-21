import '../data/repositories/capability_repository.dart';
import '../data/repositories/resource_repository.dart';
import '../models/adopted_composition.dart';
import '../models/composition.dart';
import '../models/timeline.dart';
import 'composition_core_projection.dart';
import 'composition_resolution.dart';

/// Resolves what the adopted-composition surface needs to render: the adopted
/// composition (through Core's single composition interface) and its learner
/// content — the structured transcript, alignment, and audio-linked resources.
///
/// The App never re-parses a `.listenpkg` to read adopted content; every
/// payload and blob comes back through Core, re-verified by it. Package
/// identity, manifest, and provider raw output stay out of this surface.
class CompositionSessionService {
  CompositionSessionService({
    required this.repository,
    required this.resources,
  });

  final CapabilityRepository repository;
  final ResourceRepository resources;

  /// The resolved learner content of the currently adopted composition, or
  /// null when nothing is adopted (a typed not-found) or when the required
  /// content cannot be resolved honestly.
  Future<ResolvedComposition?> resolveComposition(String materialId) async {
    final AdoptedComposition adopted;
    try {
      adopted = await repository.readAdoptedComposition(materialId);
    } on Object catch (error) {
      // No adopted composition is a normal state, not a failure of the
      // material; everything else propagates to the caller's failure surface.
      final failure = repository.failureDetail(error);
      if (failure.code == 'not_found') return null;
      rethrow;
    }

    final structuredReading = adopted.resourceOfKind('structured_reading');
    if (structuredReading == null) return null;
    List<int>? alignmentPayload;
    final alignment = adopted.resourceOfKind('anchor_time_alignment');
    if (alignment != null) {
      alignmentPayload = await repository.readCompositionResourcePayload(
        materialId,
        alignment.resourceId,
      );
    }
    final structuredReadingPayload = await repository
        .readCompositionResourcePayload(
          materialId,
          structuredReading.resourceId,
        );

    final projected = await _readWorkbenchResources(adopted);

    return resolveCompositionContent(
      composition: adopted,
      structuredReadingPayload: structuredReadingPayload,
      alignmentPayload: alignmentPayload,
      transcript: projected.transcript,
      enhancements: projected.enhancements,
      llTimelineDocument: projected.timeline,
    );
  }

  /// Reads the composition's workbench resources from Core, never from the
  /// package payload.
  ///
  /// The adopted `subtitle_text_track` is a real subtitle track under the
  /// composition's workbench media; its sentence ids are global
  /// `SubtitleSentenceId`s. Its five analysis resource families are read back
  /// through the track's LLTimeline export, already re-keyed by Core. A
  /// composition without a formal Core media binding/track has no legal
  /// transcript projection.
  ///
  /// The optional analysis export may be unavailable while the formal Core
  /// transcript remains usable. The transcript itself is never replaced by a
  /// detached payload or an App-generated timed-text fallback.
  ///
  /// The same export is also kept whole as an [LLTimelineDocument]. Core
  /// derives one rhythm frame per sentence from the package's word timeline
  /// and acoustic cues, and those frames only exist in the document — the
  /// projection above deliberately covers word-level families only.
  Future<
    ({
      CompositionResourceProjection enhancements,
      SubtitleTrack? transcript,
      LLTimelineDocument? timeline,
    })
  >
  _readWorkbenchResources(AdoptedComposition adopted) async {
    final workbenchMediaId = adopted.workbenchMediaId;
    if (workbenchMediaId == null) {
      return (
        enhancements: const CompositionResourceProjection(),
        transcript: null,
        timeline: null,
      );
    }
    try {
      final tracks = await resources.mediaSubtitles(workbenchMediaId);
      final track = _packageSubtitleTrack(adopted, tracks);
      if (track == null) {
        return (
          enhancements: const CompositionResourceProjection(),
          transcript: null,
          timeline: null,
        );
      }
      CompositionResourceProjection enhancements =
          const CompositionResourceProjection();
      LLTimelineDocument? timeline;
      try {
        final document = await resources.exportTimelineJson(track.id);
        enhancements = projectCompositionResourcesFromCore(
          track: track,
          documentJson: document.json,
        );
        timeline = _timelineDocument(document.json);
      } on Object {
        // The formal Core transcript remains usable when an optional export
        // family is unavailable.
      }
      return (
        enhancements: enhancements,
        transcript: track,
        timeline: timeline,
      );
    } on Object {
      return (
        enhancements: const CompositionResourceProjection(),
        transcript: null,
        timeline: null,
      );
    }
  }

  /// Core's export parsed as a whole document, or null when this build cannot
  /// read that shape. A document the model rejects costs the rhythm frames
  /// alone — the word-level projection is parsed independently and survives.
  static LLTimelineDocument? _timelineDocument(Map<String, dynamic> json) {
    try {
      return LLTimelineDocument.fromJson(json);
    } on Object {
      return null;
    }
  }

  /// The package subtitle track Core landed for this composition, when it is
  /// still available and still carries sentences.
  SubtitleTrack? _packageSubtitleTrack(
    AdoptedComposition adopted,
    List<SubtitleTrack> tracks,
  ) {
    final resource = adopted.resourceOfKind('subtitle_text_track');
    if (resource == null) return null;
    final expectedFingerprint =
        '${adopted.materialId}:${adopted.materialRevisionId}:${resource.resourceId}';
    for (final track in tracks) {
      if (track.source == 'package:subtitle_text_track' &&
          track.usableForLearning &&
          track.fingerprint == expectedFingerprint) {
        return track;
      }
    }
    return null;
  }
}
