part of '../timeline.dart';

// Rhythm frame model (anchors, references, structure)
// Split out of timeline.dart (mechanical decomposition).

class RhythmFrame {
  const RhythmFrame({
    required this.generatedFrom,
    required this.references,
    this.informationAnchors = const [],
    required this.stressAnchors,
    required this.nuclei,
    required this.weakGroups,
    required this.compressionSpans,
    required this.phraseBoundaries,
    required this.connectedSpeechRefs,
    required this.listeningHotspots,
    required this.quality,
  });

  factory RhythmFrame.fromJson(Map<String, dynamic> json) => RhythmFrame(
    generatedFrom: json['generated_from'] as String? ?? '',
    references: RhythmFrameReferences.fromJson(
      (json['references'] as Map<String, dynamic>?) ?? const {},
    ),
    informationAnchors:
        ((json['information_anchors'] as List<dynamic>?) ?? const [])
            .map(
              (value) => RhythmInformationAnchor.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(growable: false),
    stressAnchors: ((json['stress_anchors'] as List<dynamic>?) ?? const [])
        .map(
          (value) => RhythmStressAnchor.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false),
    nuclei: ((json['nuclei'] as List<dynamic>?) ?? const [])
        .map((value) => RhythmNucleus.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    weakGroups: ((json['weak_groups'] as List<dynamic>?) ?? const [])
        .map((value) => RhythmWeakGroup.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    compressionSpans:
        ((json['compression_spans'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  RhythmCompressionSpan.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
    phraseBoundaries:
        ((json['phrase_boundaries'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  RhythmPhraseBoundary.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
    connectedSpeechRefs:
        ((json['connected_speech_refs'] as List<dynamic>?) ?? const [])
            .map(
              (value) => RhythmConnectedSpeechRef.fromJson(
                value as Map<String, dynamic>,
              ),
            )
            .toList(growable: false),
    listeningHotspots:
        ((json['listening_hotspots'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  ListeningHotspot.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
    quality: RhythmFrameQuality.fromJson(
      (json['quality'] as Map<String, dynamic>?) ?? const {},
    ),
  );

  final String generatedFrom;
  final RhythmFrameReferences references;
  final List<RhythmInformationAnchor> informationAnchors;
  final List<RhythmStressAnchor> stressAnchors;
  final List<RhythmNucleus> nuclei;
  final List<RhythmWeakGroup> weakGroups;
  final List<RhythmCompressionSpan> compressionSpans;
  final List<RhythmPhraseBoundary> phraseBoundaries;
  final List<RhythmConnectedSpeechRef> connectedSpeechRefs;
  final List<ListeningHotspot> listeningHotspots;
  final RhythmFrameQuality quality;

  Map<String, dynamic> toJson() => {
    'generated_from': generatedFrom,
    'references': references.toJson(),
    'information_anchors': informationAnchors
        .map((value) => value.toJson())
        .toList(),
    'stress_anchors': stressAnchors.map((value) => value.toJson()).toList(),
    'nuclei': nuclei.map((value) => value.toJson()).toList(),
    'weak_groups': weakGroups.map((value) => value.toJson()).toList(),
    'compression_spans': compressionSpans
        .map((value) => value.toJson())
        .toList(),
    'phrase_boundaries': phraseBoundaries
        .map((value) => value.toJson())
        .toList(),
    'connected_speech_refs': connectedSpeechRefs
        .map((value) => value.toJson())
        .toList(),
    'listening_hotspots': listeningHotspots
        .map((value) => value.toJson())
        .toList(),
    'quality': quality.toJson(),
  };
}

class RhythmInformationAnchor {
  const RhythmInformationAnchor({
    required this.id,
    required this.start,
    required this.end,
    required this.label,
    required this.sound,
    required this.kind,
    required this.isNucleus,
    required this.prominence,
    required this.cues,
    required this.signalSources,
    required this.evidenceClass,
    required this.claimStatus,
    required this.confidence,
    required this.reason,
    this.tokenIndex,
    this.phoneStart,
    this.phoneEnd,
  });

  factory RhythmInformationAnchor.fromJson(Map<String, dynamic> json) =>
      RhythmInformationAnchor(
        id: json['id'] as String? ?? '',
        tokenIndex: json['token_index'] as int?,
        phoneStart: json['phone_start'] as int?,
        phoneEnd: json['phone_end'] as int?,
        start: Duration(milliseconds: json['start_ms'] as int? ?? 0),
        end: Duration(milliseconds: json['end_ms'] as int? ?? 0),
        label: json['label'] as String? ?? '',
        sound: json['sound'] as String? ?? '',
        kind: json['kind'] as String? ?? 'segment',
        isNucleus: json['is_nucleus'] as bool? ?? false,
        prominence:
            (json['prominence'] as num?)?.toDouble() ??
            (json['confidence'] as num?)?.toDouble() ??
            0.0,
        cues: _stringList(json['cues']),
        signalSources: _stringList(json['signal_sources']),
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
        claimStatus: json['claim_status'] as String? ?? 'predicted',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
        reason: json['reason'] as String? ?? '',
      );

  final String id;
  final int? tokenIndex;
  final int? phoneStart;
  final int? phoneEnd;
  final Duration start;
  final Duration end;
  final String label;
  final String sound;
  final String kind;
  final bool isNucleus;
  final double prominence;
  final List<String> cues;
  final List<String> signalSources;
  final String evidenceClass;
  final String claimStatus;
  final double confidence;
  final String reason;

  bool get isAudioSupported => _hasAudioSource(signalSources);

  Map<String, dynamic> toJson() => {
    'id': id,
    'token_index': tokenIndex,
    'phone_start': phoneStart,
    'phone_end': phoneEnd,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'label': label,
    'sound': sound,
    'kind': kind,
    'is_nucleus': isNucleus,
    'prominence': prominence,
    'cues': cues,
    'signal_sources': signalSources,
    'evidence_class': evidenceClass,
    'claim_status': claimStatus,
    'confidence': confidence,
    'reason': reason,
  };
}

class RhythmReference {
  const RhythmReference({
    required this.label,
    required this.source,
    required this.evidenceClass,
  });

  factory RhythmReference.fromJson(Map<String, dynamic> json) =>
      RhythmReference(
        label: json['label'] as String? ?? '',
        source: json['source'] as String? ?? '',
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
      );

  final String label;
  final String source;
  final String evidenceClass;

  Map<String, dynamic> toJson() => {
    'label': label,
    'source': source,
    'evidence_class': evidenceClass,
  };
}

class RhythmFrameReferences {
  const RhythmFrameReferences({
    required this.citation,
    this.defaultConnected,
    required this.actual,
  });

  factory RhythmFrameReferences.fromJson(Map<String, dynamic> json) =>
      RhythmFrameReferences(
        citation: RhythmReference.fromJson(
          (json['citation'] as Map<String, dynamic>?) ??
              const {
                'label': 'citation_form',
                'source': 'dictionary_lexical_stress',
                'evidence_class': 'heuristic_proxy',
              },
        ),
        defaultConnected: json['default_connected'] is Map
            ? RhythmReference.fromJson(
                Map<String, dynamic>.from(json['default_connected'] as Map),
              )
            : null,
        actual: RhythmReference.fromJson(
          (json['actual'] as Map<String, dynamic>?) ??
              const {
                'label': 'actual_delivery',
                'source': 'audio',
                'evidence_class': 'heuristic_proxy',
              },
        ),
      );

  final RhythmReference citation;
  final RhythmReference? defaultConnected;
  final RhythmReference actual;

  Map<String, dynamic> toJson() => {
    'citation': citation.toJson(),
    if (defaultConnected != null)
      'default_connected': defaultConnected!.toJson(),
    'actual': actual.toJson(),
  };
}

class RhythmStressAnchor {
  const RhythmStressAnchor({
    required this.start,
    required this.end,
    required this.label,
    required this.reason,
    required this.importance,
    required this.isNucleus,
    required this.prominence,
    required this.prominenceCues,
    required this.signalSources,
    required this.evidenceClass,
    required this.claimStatus,
    required this.confidence,
    this.tokenIndex,
    this.syllableIndex,
    this.phoneStart,
    this.phoneEnd,
  });

  factory RhythmStressAnchor.fromJson(Map<String, dynamic> json) =>
      RhythmStressAnchor(
        tokenIndex: json['token_index'] as int?,
        syllableIndex: json['syllable_index'] as int?,
        phoneStart: json['phone_start'] as int?,
        phoneEnd: json['phone_end'] as int?,
        start: Duration(milliseconds: json['start_ms'] as int? ?? 0),
        end: Duration(milliseconds: json['end_ms'] as int? ?? 0),
        label: json['label'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        importance: json['importance'] as String? ?? 'secondary',
        isNucleus: json['is_nucleus'] as bool? ?? false,
        prominence:
            (json['prominence'] as num?)?.toDouble() ??
            (json['confidence'] as num?)?.toDouble() ??
            0.0,
        prominenceCues: _stringList(json['prominence_cues']),
        signalSources: _stringList(json['signal_sources']),
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
        claimStatus: json['claim_status'] as String? ?? 'predicted',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final int? tokenIndex;
  final int? syllableIndex;
  final int? phoneStart;
  final int? phoneEnd;
  final Duration start;
  final Duration end;
  final String label;
  final String reason;
  final String importance;
  final bool isNucleus;
  final double prominence;
  final List<String> prominenceCues;
  final List<String> signalSources;
  final String evidenceClass;
  final String claimStatus;
  final double confidence;

  bool get isAudioSupported => _hasAudioSource(signalSources);

  Map<String, dynamic> toJson() => {
    'token_index': tokenIndex,
    'syllable_index': syllableIndex,
    'phone_start': phoneStart,
    'phone_end': phoneEnd,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'label': label,
    'reason': reason,
    'importance': importance,
    'is_nucleus': isNucleus,
    'prominence': prominence,
    'prominence_cues': prominenceCues,
    'signal_sources': signalSources,
    'evidence_class': evidenceClass,
    'claim_status': claimStatus,
    'confidence': confidence,
  };
}

class RhythmNucleus {
  const RhythmNucleus({
    required this.phraseIndex,
    required this.start,
    required this.end,
    required this.label,
    required this.reason,
    required this.cues,
    required this.evidenceClass,
    required this.claimStatus,
    required this.confidence,
    this.tokenIndex,
    this.syllableIndex,
  });

  factory RhythmNucleus.fromJson(Map<String, dynamic> json) => RhythmNucleus(
    phraseIndex: json['phrase_index'] as int? ?? 0,
    tokenIndex: json['token_index'] as int?,
    syllableIndex: json['syllable_index'] as int?,
    start: Duration(milliseconds: json['start_ms'] as int? ?? 0),
    end: Duration(milliseconds: json['end_ms'] as int? ?? 0),
    label: json['label'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    cues: _stringList(json['cues']),
    evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
    claimStatus: json['claim_status'] as String? ?? 'predicted',
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
  );

  final int phraseIndex;
  final int? tokenIndex;
  final int? syllableIndex;
  final Duration start;
  final Duration end;
  final String label;
  final String reason;
  final List<String> cues;
  final String evidenceClass;
  final String claimStatus;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'phrase_index': phraseIndex,
    'token_index': tokenIndex,
    'syllable_index': syllableIndex,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'label': label,
    'reason': reason,
    'cues': cues,
    'evidence_class': evidenceClass,
    'claim_status': claimStatus,
    'confidence': confidence,
  };
}

class RhythmWeakGroup {
  const RhythmWeakGroup({
    required this.start,
    required this.end,
    required this.label,
    required this.reason,
    required this.reductionRefs,
    required this.signalSources,
    required this.evidenceClass,
    required this.claimStatus,
    required this.confidence,
    this.tokenStart,
    this.tokenEnd,
    this.phoneStart,
    this.phoneEnd,
    this.anchorTokenIndex,
  });

  factory RhythmWeakGroup.fromJson(Map<String, dynamic> json) =>
      RhythmWeakGroup(
        tokenStart: json['token_start'] as int?,
        tokenEnd: json['token_end'] as int?,
        phoneStart: json['phone_start'] as int?,
        phoneEnd: json['phone_end'] as int?,
        anchorTokenIndex: json['anchor_token_index'] as int?,
        start: Duration(milliseconds: json['start_ms'] as int? ?? 0),
        end: Duration(milliseconds: json['end_ms'] as int? ?? 0),
        label: json['label'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        reductionRefs: _stringList(json['reduction_refs']),
        signalSources: _stringList(json['signal_sources']),
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
        claimStatus: json['claim_status'] as String? ?? 'predicted',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final int? tokenStart;
  final int? tokenEnd;
  final int? phoneStart;
  final int? phoneEnd;
  final int? anchorTokenIndex;
  final Duration start;
  final Duration end;
  final String label;
  final String reason;
  final List<String> reductionRefs;
  final List<String> signalSources;
  final String evidenceClass;
  final String claimStatus;
  final double confidence;

  bool get isAudioSupported => _hasAudioSource(signalSources);

  Map<String, dynamic> toJson() => {
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'phone_start': phoneStart,
    'phone_end': phoneEnd,
    'anchor_token_index': anchorTokenIndex,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'label': label,
    'reason': reason,
    'reduction_refs': reductionRefs,
    'signal_sources': signalSources,
    'evidence_class': evidenceClass,
    'claim_status': claimStatus,
    'confidence': confidence,
  };
}

class RhythmCompressionSpan {
  const RhythmCompressionSpan({
    required this.start,
    required this.end,
    required this.expectedUnits,
    required this.duration,
    required this.unitRatePerSecond,
    required this.label,
    required this.reason,
    required this.signalSources,
    required this.evidenceClass,
    required this.claimStatus,
    required this.confidence,
    this.tokenStart,
    this.tokenEnd,
    this.phoneStart,
    this.phoneEnd,
  });

  factory RhythmCompressionSpan.fromJson(Map<String, dynamic> json) =>
      RhythmCompressionSpan(
        tokenStart: json['token_start'] as int?,
        tokenEnd: json['token_end'] as int?,
        phoneStart: json['phone_start'] as int?,
        phoneEnd: json['phone_end'] as int?,
        start: Duration(milliseconds: json['start_ms'] as int? ?? 0),
        end: Duration(milliseconds: json['end_ms'] as int? ?? 0),
        expectedUnits: json['expected_units'] as int? ?? 0,
        duration: Duration(milliseconds: json['duration_ms'] as int? ?? 0),
        unitRatePerSecond:
            (json['unit_rate_per_second'] as num?)?.toDouble() ?? 0.0,
        label: json['label'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        signalSources: _stringList(json['signal_sources']),
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
        claimStatus: json['claim_status'] as String? ?? 'predicted',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final int? tokenStart;
  final int? tokenEnd;
  final int? phoneStart;
  final int? phoneEnd;
  final Duration start;
  final Duration end;
  final int expectedUnits;
  final Duration duration;
  final double unitRatePerSecond;
  final String label;
  final String reason;
  final List<String> signalSources;
  final String evidenceClass;
  final String claimStatus;
  final double confidence;

  bool get isAudioSupported => _hasAudioSource(signalSources);

  Map<String, dynamic> toJson() => {
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'phone_start': phoneStart,
    'phone_end': phoneEnd,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'expected_units': expectedUnits,
    'duration_ms': duration.inMilliseconds,
    'unit_rate_per_second': unitRatePerSecond,
    'label': label,
    'reason': reason,
    'signal_sources': signalSources,
    'evidence_class': evidenceClass,
    'claim_status': claimStatus,
    'confidence': confidence,
  };
}

class RhythmPhraseBoundary {
  const RhythmPhraseBoundary({
    required this.at,
    required this.reason,
    required this.cues,
    required this.signalSources,
    required this.evidenceClass,
    required this.claimStatus,
    required this.isFinal,
    required this.confidence,
    this.afterTokenIndex,
    this.beforeTokenIndex,
  });

  factory RhythmPhraseBoundary.fromJson(Map<String, dynamic> json) =>
      RhythmPhraseBoundary(
        afterTokenIndex: json['after_token_index'] as int?,
        beforeTokenIndex: json['before_token_index'] as int?,
        at: Duration(milliseconds: json['at_ms'] as int? ?? 0),
        reason: json['reason'] as String? ?? json['evidence'] as String? ?? '',
        cues: _stringList(json['cues']),
        signalSources: _stringList(json['signal_sources']),
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
        claimStatus: json['claim_status'] as String? ?? 'predicted',
        isFinal: json['is_final'] as bool? ?? false,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final int? afterTokenIndex;
  final int? beforeTokenIndex;
  final Duration at;
  final String reason;
  final List<String> cues;
  final List<String> signalSources;
  final String evidenceClass;
  final String claimStatus;
  final bool isFinal;
  final double confidence;

  bool get isAudioSupported => _hasAudioSource(signalSources);

  Map<String, dynamic> toJson() => {
    'after_token_index': afterTokenIndex,
    'before_token_index': beforeTokenIndex,
    'at_ms': at.inMilliseconds,
    'reason': reason,
    'cues': cues,
    'signal_sources': signalSources,
    'evidence_class': evidenceClass,
    'claim_status': claimStatus,
    'is_final': isFinal,
    'confidence': confidence,
  };
}

class ListeningHotspot {
  const ListeningHotspot({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.label,
    required this.hint,
    required this.signalSources,
    required this.evidenceClass,
    required this.claimStatus,
    required this.confidence,
    this.tokenStart,
    this.tokenEnd,
    this.phoneStart,
    this.phoneEnd,
  });

  factory ListeningHotspot.fromJson(Map<String, dynamic> json) =>
      ListeningHotspot(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        tokenStart: json['token_start'] as int?,
        tokenEnd: json['token_end'] as int?,
        phoneStart: json['phone_start'] as int?,
        phoneEnd: json['phone_end'] as int?,
        start: Duration(milliseconds: json['start_ms'] as int? ?? 0),
        end: Duration(milliseconds: json['end_ms'] as int? ?? 0),
        label: json['label'] as String? ?? '',
        hint: json['hint'] as String? ?? '',
        signalSources: _stringList(json['signal_sources']),
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
        claimStatus: json['claim_status'] as String? ?? 'predicted',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final String id;
  final String kind;
  final int? tokenStart;
  final int? tokenEnd;
  final int? phoneStart;
  final int? phoneEnd;
  final Duration start;
  final Duration end;
  final String label;
  final String hint;
  final List<String> signalSources;
  final String evidenceClass;
  final String claimStatus;
  final double confidence;

  bool get isAudioSupported => _hasAudioSource(signalSources);

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'phone_start': phoneStart,
    'phone_end': phoneEnd,
    'start_ms': start.inMilliseconds,
    'end_ms': end.inMilliseconds,
    'label': label,
    'hint': hint,
    'signal_sources': signalSources,
    'evidence_class': evidenceClass,
    'claim_status': claimStatus,
    'confidence': confidence,
  };
}

class RhythmAudibleGroup {
  const RhythmAudibleGroup({
    required this.symbols,
    required this.displayIpa,
    required this.sourceTokenIndices,
  });

  factory RhythmAudibleGroup.fromJson(Map<String, dynamic> json) =>
      RhythmAudibleGroup(
        symbols: _stringList(json['symbols']),
        displayIpa: json['display_ipa'] as String? ?? '',
        sourceTokenIndices:
            ((json['source_token_indices'] as List<dynamic>?) ?? const [])
                .cast<int>(),
      );

  final List<String> symbols;
  final String displayIpa;
  final List<int> sourceTokenIndices;

  Map<String, dynamic> toJson() => {
    'symbols': symbols,
    'display_ipa': displayIpa,
    'source_token_indices': sourceTokenIndices,
  };
}

class RhythmAudibleStructure {
  const RhythmAudibleStructure({
    required this.groups,
    required this.displayIpa,
    required this.learnerCue,
  });

  factory RhythmAudibleStructure.fromJson(Map<String, dynamic> json) =>
      RhythmAudibleStructure(
        groups: ((json['groups'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  RhythmAudibleGroup.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        displayIpa: json['display_ipa'] as String? ?? '',
        learnerCue: json['learner_cue'] as String? ?? '',
      );

  final List<RhythmAudibleGroup> groups;
  final String displayIpa;
  final String learnerCue;

  Map<String, dynamic> toJson() => {
    'groups': groups.map((value) => value.toJson()).toList(),
    'display_ipa': displayIpa,
    'learner_cue': learnerCue,
  };
}

class RhythmConnectedSpeechRef {
  const RhythmConnectedSpeechRef({
    required this.id,
    required this.label,
    required this.divergence,
    required this.signalSources,
    required this.evidenceClass,
    required this.confidence,
    this.family,
    this.surfaceText = '',
    this.hint = '',
    this.expectedSymbols = const [],
    this.defaultSymbols = const [],
    this.expectedDisplayIpa = '',
    this.defaultDisplayIpa = '',
    this.citationStructure,
    this.predictedStructure,
    this.actualStructure,
    this.connectedSpeechIndex,
    this.tokenStart,
    this.tokenEnd,
    this.phoneStart,
    this.phoneEnd,
  });

  factory RhythmConnectedSpeechRef.fromJson(Map<String, dynamic> json) =>
      RhythmConnectedSpeechRef(
        id: json['id'] as String? ?? '',
        connectedSpeechIndex: json['connected_speech_index'] as int?,
        tokenStart: json['token_start'] as int?,
        tokenEnd: json['token_end'] as int?,
        phoneStart: json['phone_start'] as int?,
        phoneEnd: json['phone_end'] as int?,
        family: json['family'] as String?,
        surfaceText: json['surface_text'] as String? ?? '',
        label: json['label'] as String? ?? '',
        hint: json['hint'] as String? ?? '',
        expectedSymbols: _stringList(json['expected_symbols']),
        defaultSymbols: _stringList(json['default_symbols']),
        expectedDisplayIpa: json['expected_display_ipa'] as String? ?? '',
        defaultDisplayIpa: json['default_display_ipa'] as String? ?? '',
        citationStructure: json['citation_structure'] is Map
            ? RhythmAudibleStructure.fromJson(
                Map<String, dynamic>.from(json['citation_structure'] as Map),
              )
            : null,
        predictedStructure: json['predicted_structure'] is Map
            ? RhythmAudibleStructure.fromJson(
                Map<String, dynamic>.from(json['predicted_structure'] as Map),
              )
            : null,
        actualStructure: json['actual_structure'] is Map
            ? RhythmAudibleStructure.fromJson(
                Map<String, dynamic>.from(json['actual_structure'] as Map),
              )
            : null,
        divergence: json['divergence'] as String? ?? 'clip_specific',
        signalSources: _stringList(json['signal_sources']),
        evidenceClass: json['evidence_class'] as String? ?? 'heuristic_proxy',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final String id;
  final int? connectedSpeechIndex;
  final int? tokenStart;
  final int? tokenEnd;
  final int? phoneStart;
  final int? phoneEnd;
  final String? family;
  final String surfaceText;
  final String label;
  final String hint;
  final List<String> expectedSymbols;
  final List<String> defaultSymbols;
  final String expectedDisplayIpa;
  final String defaultDisplayIpa;
  final RhythmAudibleStructure? citationStructure;
  final RhythmAudibleStructure? predictedStructure;
  final RhythmAudibleStructure? actualStructure;
  final String divergence;
  final List<String> signalSources;
  final String evidenceClass;
  final double confidence;

  Map<String, dynamic> toJson() => {
    'id': id,
    'connected_speech_index': connectedSpeechIndex,
    'token_start': tokenStart,
    'token_end': tokenEnd,
    'phone_start': phoneStart,
    'phone_end': phoneEnd,
    if (family != null) 'family': family,
    'surface_text': surfaceText,
    'label': label,
    'hint': hint,
    'expected_symbols': expectedSymbols,
    'default_symbols': defaultSymbols,
    'expected_display_ipa': expectedDisplayIpa,
    'default_display_ipa': defaultDisplayIpa,
    if (citationStructure != null)
      'citation_structure': citationStructure!.toJson(),
    if (predictedStructure != null)
      'predicted_structure': predictedStructure!.toJson(),
    if (actualStructure != null) 'actual_structure': actualStructure!.toJson(),
    'divergence': divergence,
    'signal_sources': signalSources,
    'evidence_class': evidenceClass,
    'confidence': confidence,
  };
}

class RhythmFrameQuality {
  const RhythmFrameQuality({
    required this.timingSource,
    required this.prominenceSources,
    required this.boundarySources,
    required this.connectedSpeechSource,
    required this.phoneEvidenceCoverage,
    required this.rhythmConfidence,
  });

  factory RhythmFrameQuality.fromJson(Map<String, dynamic> json) =>
      RhythmFrameQuality(
        timingSource: json['timing_source'] as String? ?? 'mixed',
        prominenceSources: _stringList(json['prominence_sources']),
        boundarySources: _stringList(json['boundary_sources']),
        connectedSpeechSource:
            json['connected_speech_source'] as String? ?? 'phone_segmental',
        phoneEvidenceCoverage:
            (json['phone_evidence_coverage'] as num?)?.toDouble() ?? 0.0,
        rhythmConfidence:
            (json['rhythm_confidence'] as num?)?.toDouble() ?? 0.0,
      );

  final String timingSource;
  final List<String> prominenceSources;
  final List<String> boundarySources;
  final String connectedSpeechSource;
  final double phoneEvidenceCoverage;
  final double rhythmConfidence;

  Map<String, dynamic> toJson() => {
    'timing_source': timingSource,
    'prominence_sources': prominenceSources,
    'boundary_sources': boundarySources,
    'connected_speech_source': connectedSpeechSource,
    'phone_evidence_coverage': phoneEvidenceCoverage,
    'rhythm_confidence': rhythmConfidence,
  };
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

bool _hasAudioSource(List<String> values) => values.any(
  (value) =>
      value == 'timing' ||
      value == 'energy' ||
      value == 'pitch' ||
      value == 'phone_segmental',
);

class PhonemeRibbonFinding {
  const PhonemeRibbonFinding({
    required this.phoneStart,
    required this.phoneEnd,
    required this.findingType,
    required this.status,
    required this.confidence,
    required this.evidence,
    this.learnerLabelOverride,
    this.learnerHint,
  });

  final int phoneStart;
  final int phoneEnd;
  final String findingType;
  final String status;
  final double confidence;
  final String evidence;
  final String? learnerLabelOverride;
  final String? learnerHint;

  bool get detectedInAudio => status == 'detected_in_audio';

  String get learnerLabel {
    if (learnerLabelOverride != null && learnerLabelOverride!.isNotEmpty) {
      return learnerLabelOverride!;
    }
    final normalizedType = findingType.toLowerCase();
    if (normalizedType.contains('linking') ||
        normalizedType.contains('insertion')) {
      return 'possible linking';
    }
    if (normalizedType.contains('reduction') ||
        normalizedType.contains('weak')) {
      return 'possible reduction';
    }
    if (normalizedType.contains('deletion') ||
        normalizedType.contains('elision') ||
        normalizedType.contains('omission')) {
      return 'possible deletion';
    }
    if (normalizedType.contains('assimilation')) {
      return 'possible assimilation';
    }
    if (normalizedType.contains('contraction')) {
      return 'possible contraction';
    }
    if (normalizedType.contains('flapping') ||
        normalizedType.contains('flap')) {
      return 'possible flap';
    }
    return 'supported by audio';
  }

  String get learnerTooltip {
    final confidencePercent = (confidence * 100).round();
    final hint = learnerHint;
    if (hint == null || hint.isEmpty) {
      return '$learnerLabel · $confidencePercent%';
    }
    return '$learnerLabel · $confidencePercent%\n$hint';
  }
}
