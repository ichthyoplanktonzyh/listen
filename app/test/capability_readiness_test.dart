import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/capability_readiness.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/widgets/subtitle/rhythm_frame_ribbon.dart';

void main() {
  test('marks every learning layer unavailable without subtitles', () {
    final snapshot = CapabilityReadinessSnapshot.fromResources(
      activeTrack: null,
      document: null,
      wordTimelineSummaries: const [],
      prosodyAnalyses: const [],
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
      prosodyAnalyses: const [],
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
      prosodyAnalyses: const [],
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
      prosodyAnalyses: const [_prosodyAnalysis],
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
      prosodyAnalyses: const [],
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
      prosodyAnalyses: const [_prosodyAnalysis],
      phoneTimelineSummaries: const [_phoneSummary],
    );

    expect(snapshot.learningItems.map((value) => value.capability), [
      UserCapability.wordSync,
      UserCapability.chunkReplay,
      UserCapability.listeningStructure,
      UserCapability.phoneEvidence,
    ]);
  });

  test(
    'rhythmFrameHasAudioSupport separates audio-backed from text-predicted',
    () {
      expect(rhythmFrameHasAudioSupport(_audioRhythmFrame.rhythmFrame), isTrue);
      expect(
        rhythmFrameHasAudioSupport(_predictedRhythmFrame.rhythmFrame),
        isFalse,
      );
    },
  );

  test('C requires loaded phones and phone evidence inside the frame', () {
    expect(
      canDisplayActualRhythmFrame(
        _predictedRhythmFrame.rhythmFrame,
        hasPhoneEvidence: false,
      ),
      isFalse,
    );
    expect(
      canDisplayActualRhythmFrame(
        _audioRhythmFrame.rhythmFrame,
        hasPhoneEvidence: false,
      ),
      isFalse,
    );
    expect(
      canDisplayActualRhythmFrame(
        _predictedRhythmFrame.rhythmFrame,
        hasPhoneEvidence: true,
      ),
      isFalse,
    );
    expect(
      canDisplayActualRhythmFrame(
        _audioRhythmFrame.rhythmFrame,
        hasPhoneEvidence: true,
      ),
      isTrue,
    );
  });

  testWidgets('rhythm ribbon shows a predicted badge for text-prior frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 500,
              child: RhythmFrameRibbon(
                frame: _predictedRhythmFrame.rhythmFrame,
                position: Duration.zero,
                title: 'Listening structure',
                anchorLabel: 'Anchors',
                weakGroupLabel: 'Weak',
                compressionLabel: 'Compressed',
                hotspotLabel: 'Hotspots',
                predicted: true,
                predictedLabel: 'predicted',
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('predicted'), findsOneWidget);
  });

  testWidgets(
    'rhythm ribbon hides the predicted badge for audio-backed frames',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                child: RhythmFrameRibbon(
                  frame: _audioRhythmFrame.rhythmFrame,
                  position: Duration.zero,
                  title: 'Listening structure',
                  anchorLabel: 'Anchors',
                  weakGroupLabel: 'Weak',
                  compressionLabel: 'Compressed',
                  hotspotLabel: 'Hotspots',
                  predicted: false,
                  predictedLabel: 'predicted',
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('predicted'), findsNothing);
    },
  );
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

const _prosodyAnalysis = ProsodyAnalysis(
  id: 'prosody-active',
  trackId: 'track-1',
  mediaId: 'media-1',
  providerId: 'listen-gen',
  providerVersion: '0.4.0',
  algorithm: 'prosody-v1',
  status: 'active',
  chunks: [
    ProsodicChunk(
      sentenceId: 'sentence-1',
      chunkIndex: 0,
      startTokenIndex: 0,
      endTokenIndex: 1,
    ),
    ProsodicChunk(
      sentenceId: 'sentence-1',
      chunkIndex: 1,
      startTokenIndex: 2,
      endTokenIndex: 3,
    ),
    ProsodicChunk(
      sentenceId: 'sentence-1',
      chunkIndex: 2,
      startTokenIndex: 4,
      endTokenIndex: 5,
    ),
    ProsodicChunk(
      sentenceId: 'sentence-1',
      chunkIndex: 3,
      startTokenIndex: 6,
      endTokenIndex: 7,
    ),
  ],
  anchorCount: 8,
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
      prosodyAnalyses: const [_prosodyAnalysis],
      activeProsodyAnalysisId: 'prosody-active',
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
      phoneEvidenceCoverage: 0.75,
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
