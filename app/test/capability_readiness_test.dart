import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/capability_readiness.dart';
import 'package:llplayer_next/models/timeline.dart';

void main() {
  test('marks every learning layer unavailable without subtitles', () {
    final snapshot = CapabilityReadinessSnapshot.fromResources(
      activeTrack: null,
      document: null,
      wordTimelineSummaries: const [],
      chunkTimelineSummaries: const [],
      phoneTimelineSummaries: const [],
    );

    expect(snapshot.subtitles.state, CapabilityReadinessState.unavailable);
    expect(snapshot.wordSync.state, CapabilityReadinessState.unavailable);
    expect(snapshot.chunkReplay.state, CapabilityReadinessState.unavailable);
    expect(
      snapshot.listeningStructure.state,
      CapabilityReadinessState.unavailable,
    );
    expect(snapshot.phoneEvidence.state, CapabilityReadinessState.unavailable);
  });

  test('plain subtitle path is available but timeline layers are missing', () {
    final snapshot = CapabilityReadinessSnapshot.fromResources(
      activeTrack: _track,
      document: null,
      wordTimelineSummaries: const [],
      chunkTimelineSummaries: const [],
      phoneTimelineSummaries: const [],
    );

    expect(snapshot.subtitles.state, CapabilityReadinessState.available);
    expect(snapshot.subtitles.count, 1);
    expect(snapshot.wordSync.state, CapabilityReadinessState.unavailable);
    expect(snapshot.chunkReplay.detailKey, 'capChunkReplayUnavailableNoWord');
    expect(
      snapshot.listeningStructure.detailKey,
      'capListeningUnavailableNoWord',
    );
    expect(snapshot.phoneEvidence.detailKey, 'capPhoneEvidenceUnavailable');
  });

  test('generated word timings count as available word sync', () {
    final snapshot = CapabilityReadinessSnapshot.fromResources(
      activeTrack: _track,
      document: null,
      wordTimelineSummaries: const [],
      chunkTimelineSummaries: const [],
      phoneTimelineSummaries: const [],
      activeWordTimingCount: 703,
    );

    expect(snapshot.wordSync.state, CapabilityReadinessState.available);
    expect(snapshot.wordSync.detailKey, 'capWordSyncGeneratedTimings');
    expect(snapshot.wordSync.count, 703);
    expect(snapshot.chunkReplay.detailKey, 'capChunkReplayUnavailable');
    expect(snapshot.listeningStructure.detailKey, 'capListeningUnavailable');
  });

  test('active timelines and audio-supported rhythm are available', () {
    final snapshot = CapabilityReadinessSnapshot.fromResources(
      activeTrack: _track,
      document: _document(_audioRhythmFrame),
      wordTimelineSummaries: const [_audioWordSummary],
      chunkTimelineSummaries: const [_chunkSummary],
      phoneTimelineSummaries: const [_phoneSummary],
    );

    expect(snapshot.wordSync.state, CapabilityReadinessState.available);
    expect(snapshot.wordSync.count, 12);
    expect(snapshot.chunkReplay.state, CapabilityReadinessState.available);
    expect(
      snapshot.listeningStructure.state,
      CapabilityReadinessState.available,
    );
    expect(snapshot.listeningStructure.count, 1);
    expect(snapshot.phoneEvidence.state, CapabilityReadinessState.available);
  });

  test('estimated word timing keeps word sync and listening degraded', () {
    final snapshot = CapabilityReadinessSnapshot.fromResources(
      activeTrack: _track,
      document: _document(_predictedRhythmFrame),
      wordTimelineSummaries: const [_estimatedWordSummary],
      chunkTimelineSummaries: const [],
      phoneTimelineSummaries: const [],
    );

    expect(snapshot.wordSync.state, CapabilityReadinessState.degraded);
    expect(snapshot.wordSync.detailKey, 'capWordSyncEstimated');
    expect(
      snapshot.listeningStructure.state,
      CapabilityReadinessState.degraded,
    );
    expect(snapshot.listeningStructure.detailKey, 'capListeningPredictedOnly');
  });

  test('learning summary items exclude subtitles and keep workflow order', () {
    final snapshot = CapabilityReadinessSnapshot.fromResources(
      activeTrack: _track,
      document: _document(_audioRhythmFrame),
      wordTimelineSummaries: const [_audioWordSummary],
      chunkTimelineSummaries: const [_chunkSummary],
      phoneTimelineSummaries: const [_phoneSummary],
    );

    expect(snapshot.learningItems.map((value) => value.capability), [
      UserCapability.wordSync,
      UserCapability.chunkReplay,
      UserCapability.listeningStructure,
      UserCapability.phoneEvidence,
    ]);
  });
}

const _track = SubtitleTrack(
  id: 'track-1',
  mediaId: 'media-1',
  language: 'en',
  source: 'srt',
  cues: [
    Cue(
      id: 'sentence-1',
      index: 0,
      start: Duration.zero,
      end: Duration(seconds: 1),
      text: 'Hello',
      tokens: [],
    ),
  ],
);

const _audioWordSummary = WordTimelineSummary(
  id: 'word-active',
  trackId: 'track-1',
  mediaId: 'media-1',
  algorithmId: 'whisper.cpp',
  algorithmVersion: '1.0',
  createdBy: 'algorithm',
  status: 'active',
  lifecycleStage: 'algorithm_candidate',
  wordCount: 12,
  providerIds: ['whisper.cpp'],
  timingSources: ['asr_reported'],
  canActivate: false,
  canArchive: true,
  canDelete: true,
);

const _estimatedWordSummary = WordTimelineSummary(
  id: 'word-estimated',
  trackId: 'track-1',
  mediaId: 'media-1',
  algorithmId: 'subtitle-estimator',
  algorithmVersion: '1.0',
  createdBy: 'algorithm',
  status: 'active',
  lifecycleStage: 'algorithm_candidate',
  wordCount: 12,
  providerIds: ['subtitle-estimator'],
  timingSources: ['estimated'],
  canActivate: false,
  canArchive: true,
  canDelete: true,
);

const _chunkSummary = ChunkTimelineSummary(
  id: 'chunk-active',
  trackId: 'track-1',
  mediaId: 'media-1',
  providerId: 'partitioner',
  providerVersion: '1.0',
  algorithm: 'acoustic_semantic_v1',
  precision: 'precise',
  createdBy: 'algorithm',
  status: 'active',
  chunkCount: 4,
  canActivate: false,
  canArchive: true,
  canDelete: true,
);

const _phoneSummary = PhoneTimelineSummary(
  id: 'phone-active',
  trackId: 'track-1',
  mediaId: 'media-1',
  providerId: 'phone-provider',
  providerVersion: '1.0',
  phoneSet: 'ipa',
  precision: 'approximate',
  createdBy: 'algorithm',
  status: 'active',
  phoneCount: 8,
  findingCount: 2,
  canActivate: false,
  canArchive: true,
  canDelete: true,
);

LLTimelineDocument _document(LLTimelineRhythmFrame rhythmFrame) =>
    LLTimelineDocument(
      schema: 'llplayer.timeline.v1',
      metadata: const LLTimelineMetadata(
        createdAt: Duration(milliseconds: 1),
        generatorId: 'fixture-generator',
        generatorVersion: '1.0',
        generatorMode: 'production_engine',
        mediaTitle: 'Fixture',
        mediaFingerprint: 'fingerprint',
        humanReviewed: false,
        extra: {'track_source': 'lltimeline-json-v1'},
      ),
      activeWordTimelineId: 'word-active',
      activePhoneTimelineId: null,
      activeChunkTimelineId: null,
      rhythmFrames: [rhythmFrame],
      artifacts: const [],
    );

const _refs = RhythmFrameReferences(
  citation: RhythmReference(
    label: 'citation_form',
    source: 'dictionary_lexical_stress',
    evidenceClass: 'heuristic_proxy',
  ),
  actual: RhythmReference(
    label: 'actual_delivery',
    source: 'word_timeline_duration',
    evidenceClass: 'heuristic_proxy',
  ),
);

const _audioRhythmFrame = LLTimelineRhythmFrame(
  id: 'rhythm-audio',
  trackId: 'track-1',
  mediaId: 'media-1',
  sentenceId: 'sentence-1',
  parentWordTimelineId: 'word-active',
  providerId: 'wordtimeline-rhythm-frame',
  providerVersion: '1.0',
  status: 'active',
  metricsJson: TimelineMetrics.empty(),
  rhythmFrame: RhythmFrame(
    generatedFrom: 'wordtimeline_timing_prominence_v1',
    references: _refs,
    stressAnchors: [
      RhythmStressAnchor(
        start: Duration.zero,
        end: Duration(milliseconds: 300),
        label: 'Hello',
        reason: 'timing-supported anchor',
        importance: 'primary',
        isNucleus: true,
        prominence: 0.8,
        prominenceCues: ['timing'],
        signalSources: ['timing'],
        evidenceClass: 'heuristic_proxy',
        claimStatus: 'audio_supported',
        confidence: 0.8,
      ),
    ],
    nuclei: [],
    weakGroups: [],
    compressionSpans: [],
    phraseBoundaries: [],
    connectedSpeechRefs: [],
    listeningHotspots: [],
    quality: RhythmFrameQuality(
      timingSource: 'word_timeline',
      prominenceSources: ['timing'],
      boundarySources: [],
      connectedSpeechSource: 'text_prior',
      phoneEvidenceCoverage: 0.0,
      rhythmConfidence: 0.8,
    ),
  ),
  createdAt: Duration(milliseconds: 10),
  updatedAt: Duration(milliseconds: 20),
);

const _predictedRhythmFrame = LLTimelineRhythmFrame(
  id: 'rhythm-predicted',
  trackId: 'track-1',
  mediaId: 'media-1',
  sentenceId: 'sentence-1',
  parentWordTimelineId: 'word-estimated',
  providerId: 'wordtimeline-rhythm-frame',
  providerVersion: '1.0',
  status: 'active',
  metricsJson: TimelineMetrics.empty(),
  rhythmFrame: RhythmFrame(
    generatedFrom: 'wordtimeline_text_prior_v1',
    references: _refs,
    stressAnchors: [
      RhythmStressAnchor(
        start: Duration.zero,
        end: Duration(milliseconds: 300),
        label: 'Hello',
        reason: 'text-prior anchor',
        importance: 'primary',
        isNucleus: false,
        prominence: 0.5,
        prominenceCues: ['text_prior'],
        signalSources: ['text_prior'],
        evidenceClass: 'heuristic_proxy',
        claimStatus: 'predicted',
        confidence: 0.5,
      ),
    ],
    nuclei: [],
    weakGroups: [],
    compressionSpans: [],
    phraseBoundaries: [],
    connectedSpeechRefs: [],
    listeningHotspots: [],
    quality: RhythmFrameQuality(
      timingSource: 'estimated',
      prominenceSources: ['text_prior'],
      boundarySources: [],
      connectedSpeechSource: 'text_prior',
      phoneEvidenceCoverage: 0.0,
      rhythmConfidence: 0.5,
    ),
  ),
  createdAt: Duration(milliseconds: 10),
  updatedAt: Duration(milliseconds: 20),
);
