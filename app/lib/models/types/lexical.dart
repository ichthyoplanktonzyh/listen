part of '../types.dart';

// Lexical entries, capability profile, sense folders, phrase candidates.
// Split out of types.dart (mechanical decomposition).

/// A user's lexical learning asset.
class LexicalEntry {
  const LexicalEntry({
    required this.id,
    required this.normalizedForm,
    required this.displayForm,
    required this.kind,
    this.status,
    this.userDefinition,
    this.personalNote,
    required this.language,
  });

  factory LexicalEntry.fromJson(Map<String, dynamic> json) => LexicalEntry(
    id: json['id'] as String,
    normalizedForm: json['normalized_form'] as String,
    displayForm: json['display_form'] as String,
    kind: json['kind'] as String,
    status: json['status'] as String?,
    userDefinition: json['user_definition'] as String?,
    personalNote: json['personal_note'] as String?,
    language: json['language'] as String,
  );

  final String id;
  final String normalizedForm;
  final String displayForm;
  final String kind;

  /// Learning status: null | 'unknown_meaning' | 'known_not_recognized' | 'known_recognized'
  final String? status;
  final String? userDefinition;
  final String? personalNote;
  final String language;

  Map<String, dynamic> toJson() => {
    'id': id,
    'normalized_form': normalizedForm,
    'display_form': displayForm,
    'kind': kind,
    'status': status,
    'user_definition': userDefinition,
    'personal_note': personalNote,
    'language': language,
  };

  LexicalEntry copyWith({
    String? status,
    String? userDefinition,
    String? personalNote,
  }) => LexicalEntry(
    id: id,
    normalizedForm: normalizedForm,
    displayForm: displayForm,
    kind: kind,
    status: status ?? this.status,
    userDefinition: userDefinition ?? this.userDefinition,
    personalNote: personalNote ?? this.personalNote,
    language: language,
  );
}

/// History entry for a lexical asset status change.
class LexicalStatusHistory {
  const LexicalStatusHistory({
    this.previousStatus,
    this.newStatus,
    required this.changeSource,
    required this.changedAtMs,
  });

  factory LexicalStatusHistory.fromJson(Map<String, dynamic> json) =>
      LexicalStatusHistory(
        previousStatus: json['previous_status'] as String?,
        newStatus: json['new_status'] as String?,
        changeSource: json['change_source'] as String,
        changedAtMs: json['changed_at_ms'] as int,
      );

  final String? previousStatus;
  final String? newStatus;
  final String changeSource;
  final int changedAtMs;

  Map<String, dynamic> toJson() => {
    'previous_status': previousStatus,
    'new_status': newStatus,
    'change_source': changeSource,
    'changed_at_ms': changedAtMs,
  };
}

/// An occurrence/source-snapshot of a lexical asset in context.
class LexicalOccurrence {
  const LexicalOccurrence({
    this.id = '',
    required this.mediaTitleSnapshot,
    required this.mediaFingerprintSnapshot,
    required this.sentenceTextSnapshot,
    required this.startMsSnapshot,
    required this.endMsSnapshot,
    required this.encounterCount,
    this.originalForm,
    this.mediaId,
    this.sentenceId,
  });

  factory LexicalOccurrence.fromJson(Map<String, dynamic> json) =>
      LexicalOccurrence(
        id: json['id'] as String? ?? '',
        mediaTitleSnapshot: json['media_title_snapshot'] as String,
        mediaFingerprintSnapshot: json['media_fingerprint_snapshot'] as String,
        sentenceTextSnapshot: json['sentence_text_snapshot'] as String,
        startMsSnapshot: json['start_ms_snapshot'] as int,
        endMsSnapshot: json['end_ms_snapshot'] as int,
        encounterCount: json['encounter_count'] as int,
        originalForm: json['original_form'] as String?,
        mediaId: json['media_id'] as String?,
        sentenceId: json['sentence_id'] as String?,
      );

  final String mediaTitleSnapshot;
  final String id;
  final String mediaFingerprintSnapshot;
  final String sentenceTextSnapshot;
  final int startMsSnapshot;
  final int endMsSnapshot;
  final int encounterCount;
  final String? originalForm;
  final String? mediaId;
  final String? sentenceId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'media_title_snapshot': mediaTitleSnapshot,
    'media_fingerprint_snapshot': mediaFingerprintSnapshot,
    'sentence_text_snapshot': sentenceTextSnapshot,
    'start_ms_snapshot': startMsSnapshot,
    'end_ms_snapshot': endMsSnapshot,
    'encounter_count': encounterCount,
    'original_form': originalForm,
    'media_id': mediaId,
    'sentence_id': sentenceId,
  };
}

/// Full lexical asset details returned by the API.
class LexicalEntryDetails {
  const LexicalEntryDetails({
    required this.entry,
    this.history = const [],
    this.occurrences = const [],
    this.senseFolders = const [],
    this.capabilityProfile,
  });

  factory LexicalEntryDetails.fromJson(Map<String, dynamic> json) =>
      LexicalEntryDetails(
        entry: LexicalEntry.fromJson(json['entry'] as Map<String, dynamic>),
        history: ((json['history'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  LexicalStatusHistory.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        occurrences: ((json['occurrences'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  LexicalOccurrence.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        senseFolders:
            ((json['sense_folders'] as List<dynamic>?) ?? const [])
                .map(
                  (value) => LexicalSenseFolderDetails.fromJson(
                    value as Map<String, dynamic>,
                  ),
                )
                .toList(growable: false),
        capabilityProfile: json['capability_profile'] is Map
            ? LexicalCapabilityProfile.fromJson(
                Map<String, dynamic>.from(json['capability_profile'] as Map),
              )
            : null,
      );

  final LexicalEntry entry;
  final List<LexicalStatusHistory> history;
  final List<LexicalOccurrence> occurrences;
  final List<LexicalSenseFolderDetails> senseFolders;
  final LexicalCapabilityProfile? capabilityProfile;

  Map<String, dynamic> toJson() => {
    'entry': entry.toJson(),
    'history': history.map((value) => value.toJson()).toList(growable: false),
    'occurrences': occurrences
        .map((value) => value.toJson())
        .toList(growable: false),
    'sense_folders': senseFolders
        .map((value) => value.toJson())
        .toList(growable: false),
    if (capabilityProfile != null)
      'capability_profile': capabilityProfile!.toJson(),
  };
}

class LexicalSenseFolder {
  const LexicalSenseFolder({
    required this.id,
    required this.lexicalEntryId,
    required this.label,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.definition,
    this.gloss,
    this.externalRef,
  });

  factory LexicalSenseFolder.fromJson(Map<String, dynamic> json) =>
      LexicalSenseFolder(
        id: json['id'] as String,
        lexicalEntryId: json['lexical_entry_id'] as String,
        label: json['label'] as String,
        definition: json['definition'] as String?,
        gloss: json['gloss'] as String?,
        externalRef: json['external_ref'] as String?,
        createdAtMs: json['created_at_ms'] as int,
        updatedAtMs: json['updated_at_ms'] as int,
      );

  final String id;
  final String lexicalEntryId;
  final String label;
  final String? definition;
  final String? gloss;
  final String? externalRef;
  final int createdAtMs;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'lexical_entry_id': lexicalEntryId,
    'label': label,
    'definition': definition,
    'gloss': gloss,
    'external_ref': externalRef,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
  };
}

class LexicalSenseFolderDetails {
  const LexicalSenseFolderDetails({required this.folder, this.occurrences = const []});

  factory LexicalSenseFolderDetails.fromJson(Map<String, dynamic> json) =>
      LexicalSenseFolderDetails(
        folder: LexicalSenseFolder.fromJson(json['folder'] as Map<String, dynamic>),
        occurrences: ((json['occurrences'] as List<dynamic>?) ?? const [])
            .map((value) => LexicalOccurrence.fromJson(value as Map<String, dynamic>))
            .toList(growable: false),
      );

  final LexicalSenseFolder folder;
  final List<LexicalOccurrence> occurrences;

  Map<String, dynamic> toJson() => {
    'folder': folder.toJson(),
    'occurrences': occurrences.map((value) => value.toJson()).toList(growable: false),
  };
}

/// One row of the rebuildable local corpus projection (Phase 3.6 Slice 3).
/// Unlike [LexicalOccurrence] it is not a durable learning asset: rows are
/// regenerated from imported subtitles/chunk timelines and may lose their
/// media link when the media record is deleted.
class CorpusOccurrence {
  const CorpusOccurrence({
    required this.id,
    required this.language,
    required this.kind,
    required this.displayText,
    required this.startMs,
    required this.endMs,
    required this.sourceSnapshot,
    this.normalizedKey,
    this.mediaId,
    this.trackId,
    this.sentenceId,
  });

  factory CorpusOccurrence.fromJson(Map<String, dynamic> json) =>
      CorpusOccurrence(
        id: json['id'] as String,
        language: json['language'] as String,
        kind: json['kind'] as String,
        displayText: json['display_text'] as String,
        startMs: json['start_ms'] as int,
        endMs: json['end_ms'] as int,
        sourceSnapshot: json['source_snapshot'] as String,
        normalizedKey: json['normalized_key'] as String?,
        mediaId: json['media_id'] as String?,
        trackId: json['track_id'] as String?,
        sentenceId: json['sentence_id'] as String?,
      );

  final String id;
  final String language;

  /// 'lexical' | 'phrase' | 'chunk' | 'sound_pattern' | 'connected_speech'
  final String kind;
  final String displayText;
  final int startMs;
  final int endMs;
  final String sourceSnapshot;
  final String? normalizedKey;
  final String? mediaId;
  final String? trackId;
  final String? sentenceId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'language': language,
    'kind': kind,
    'display_text': displayText,
    'start_ms': startMs,
    'end_ms': endMs,
    'source_snapshot': sourceSnapshot,
    'normalized_key': normalizedKey,
    'media_id': mediaId,
    'track_id': trackId,
    'sentence_id': sentenceId,
  };
}

// ──────────────────────────────────────────────
// Capability Profile (Phase 3.4.1)
// ──────────────────────────────────────────────

class CapabilityProjection {
  const CapabilityProjection({
    required this.conclusion,
    required this.source,
    required this.algorithmVersion,
    required this.updatedAtMs,
  });

  factory CapabilityProjection.fromJson(Map<String, dynamic> json) =>
      CapabilityProjection(
        conclusion: json['conclusion'] as String,
        source: json['source'] as String,
        algorithmVersion: json['algorithm_version'] as String,
        updatedAtMs: json['updated_at_ms'] as int,
      );

  final String conclusion;
  final String source;
  final String algorithmVersion;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'conclusion': conclusion,
    'source': source,
    'algorithm_version': algorithmVersion,
    'updated_at_ms': updatedAtMs,
  };
}

class CapabilityOverride {
  const CapabilityOverride({
    required this.conclusion,
    required this.source,
    required this.updatedAtMs,
  });

  factory CapabilityOverride.fromJson(Map<String, dynamic> json) =>
      CapabilityOverride(
        conclusion: json['conclusion'] as String,
        source: json['source'] as String,
        updatedAtMs: json['updated_at_ms'] as int,
      );

  final String conclusion;
  final String source;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
    'conclusion': conclusion,
    'source': source,
    'updated_at_ms': updatedAtMs,
  };
}

class CapabilityDimensionState {
  const CapabilityDimensionState({this.projection, this.userOverride});

  factory CapabilityDimensionState.fromJson(Map<String, dynamic> json) =>
      CapabilityDimensionState(
        projection: json['projection'] is Map
            ? CapabilityProjection.fromJson(
                Map<String, dynamic>.from(json['projection'] as Map),
              )
            : null,
        userOverride: json['user_override'] is Map
            ? CapabilityOverride.fromJson(
                Map<String, dynamic>.from(json['user_override'] as Map),
              )
            : null,
      );

  final CapabilityProjection? projection;
  final CapabilityOverride? userOverride;

  String get effectiveAssessment {
    if (userOverride != null) return userOverride!.conclusion;
    if (projection != null) return projection!.conclusion;
    return 'unassessed';
  }

  Map<String, dynamic> toJson() => {
    'projection': projection?.toJson(),
    'user_override': userOverride?.toJson(),
  };
}

class LexicalCapabilityProfile {
  const LexicalCapabilityProfile({
    required this.lexicalEntryId,
    this.senseId,
    required this.reading,
    required this.listening,
    required this.speaking,
    required this.writing,
  });

  factory LexicalCapabilityProfile.fromJson(Map<String, dynamic> json) =>
      LexicalCapabilityProfile(
        lexicalEntryId: json['lexical_entry_id'] as String,
        senseId: json['sense_id'] as String?,
        reading: CapabilityDimensionState.fromJson(_asMap(json['reading'])),
        listening: CapabilityDimensionState.fromJson(_asMap(json['listening'])),
        speaking: CapabilityDimensionState.fromJson(_asMap(json['speaking'])),
        writing: CapabilityDimensionState.fromJson(_asMap(json['writing'])),
      );

  final String lexicalEntryId;
  final String? senseId;
  final CapabilityDimensionState reading;
  final CapabilityDimensionState listening;
  final CapabilityDimensionState speaking;
  final CapabilityDimensionState writing;

  Map<String, dynamic> toJson() => {
    'lexical_entry_id': lexicalEntryId,
    'sense_id': senseId,
    'reading': reading.toJson(),
    'listening': listening.toJson(),
    'speaking': speaking.toJson(),
    'writing': writing.toJson(),
  };
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

class PhraseCandidate {
  const PhraseCandidate({
    required this.canonicalForm,
    required this.displayForm,
    required this.tokenStart,
    required this.tokenEnd,
    this.confidence,
    this.reason,
  });

  factory PhraseCandidate.fromJson(Map<String, dynamic> json) =>
      PhraseCandidate(
        canonicalForm: json['canonical_form'] as String,
        displayForm: json['display_form'] as String,
        tokenStart: json['token_start'] as int,
        tokenEnd: json['token_end'] as int,
        confidence: (json['confidence'] as num?)?.toDouble(),
        reason: json['reason'] as String?,
      );

  final String canonicalForm;
  final String displayForm;
  final int tokenStart;
  final int tokenEnd;
  final double? confidence;
  final String? reason;

  Map<String, dynamic> toJson() => {
    'canonical_form': canonicalForm,
    'display_form': displayForm,
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'confidence': confidence,
    'reason': reason,
  };
}

// ──────────────────────────────────────────────
// Dictionary Lookup
// ──────────────────────────────────────────────
