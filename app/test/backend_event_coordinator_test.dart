import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/backend_event_coordinator.dart';
import 'package:llplayer_next/models/types.dart';

/// Records every callback the coordinator fires so each SSE dispatch branch can
/// be asserted in isolation. The coordinator is the single seam between raw
/// backend events and the controllers, so this is where event routing bugs
/// would otherwise slip through silently.
class _Recorder {
  String? mediaId;
  String? primaryTrackId;

  int loadWordEntriesCalls = 0;
  final List<String> loadedTimelineResources = [];
  final List<String> readSubtitleCalls = [];
  final List<Map<String, dynamic>> generatedTracks = [];
  final List<bool> generatedSecondary = [];
  final List<String> loadedSpeechEnhancements = [];
  final List<String> statuses = [];
  final List<String> updatedForms = [];
  final List<LexicalEntry> updatedEntries = [];

  Map<String, dynamic> subtitleToReturn = const {'id': 'gen-track'};

  BackendEventCoordinator build() => BackendEventCoordinator(
    currentMediaId: () => mediaId,
    currentPrimaryTrackId: () => primaryTrackId,
    loadWordEntries: () async {
      loadWordEntriesCalls++;
    },
    loadTimelineResource: (trackId) async {
      loadedTimelineResources.add(trackId);
    },
    readSubtitle: (trackId) async {
      readSubtitleCalls.add(trackId);
      return subtitleToReturn;
    },
    loadGeneratedTrack: (track, secondary) async {
      generatedTracks.add(track);
      generatedSecondary.add(secondary);
    },
    loadSpeechEnhancements: (trackId) async {
      loadedSpeechEnhancements.add(trackId);
    },
    setStatus: statuses.add,
    updateWordEntry: (form, entry) {
      updatedForms.add(form);
      updatedEntries.add(entry);
    },
  );
}

Map<String, dynamic> _lexicalEntryPayload({
  String normalized = 'going',
  String display = 'going',
}) => {
  'event': 'lexical-entry-changed',
  'payload': {
    'entry': {
      'id': 'le-1',
      'normalized_form': normalized,
      'display_form': display,
      'kind': 'word',
      'status': 'known_recognized',
      'language': 'en',
    },
  },
};

void main() {
  group('BackendEventCoordinator', () {
    test('service-started loads word entries and the active timeline', () async {
      final recorder = _Recorder()..primaryTrackId = 'track-1';
      recorder.build().handle({'event': 'service-started'});
      await pumpEventQueue();

      expect(recorder.loadWordEntriesCalls, 1);
      expect(recorder.loadedTimelineResources, ['track-1']);
    });

    test('service-started skips timeline load when no primary track', () async {
      final recorder = _Recorder();
      recorder.build().handle({'event': 'service-started'});
      await pumpEventQueue();

      expect(recorder.loadWordEntriesCalls, 1);
      expect(recorder.loadedTimelineResources, isEmpty);
    });

    test('completed transcription for current media loads the generated track', () async {
      final recorder = _Recorder()
        ..mediaId = 'media-1'
        ..subtitleToReturn = {'id': 'gen-1'};
      recorder.build().handle({
        'event': 'transcription-job-changed',
        'payload': {
          'status': 'completed',
          'phase_progress': 100,
          'media_id': 'media-1',
          'generated_track_id': 'gen-1',
          'destination': 'secondary',
        },
      });
      await pumpEventQueue();

      expect(recorder.readSubtitleCalls, ['gen-1']);
      expect(recorder.generatedTracks, [
        {'id': 'gen-1'},
      ]);
      expect(recorder.generatedSecondary, [true]);
      // The completed-with-track branch returns early, so no status is pushed.
      expect(recorder.statuses, isEmpty);
    });

    test('in-progress transcription for current media reports status', () async {
      final recorder = _Recorder()..mediaId = 'media-1';
      recorder.build().handle({
        'event': 'transcription-job-changed',
        'payload': {
          'status': 'running',
          'phase_progress': 42,
          'media_id': 'media-1',
        },
      });
      await pumpEventQueue();

      expect(recorder.statuses, ['ASR running · 42%']);
      expect(recorder.readSubtitleCalls, isEmpty);
    });

    test('transcription for a different media is ignored', () async {
      final recorder = _Recorder()..mediaId = 'media-1';
      recorder.build().handle({
        'event': 'transcription-job-changed',
        'payload': {
          'status': 'running',
          'phase_progress': 10,
          'media_id': 'other-media',
        },
      });
      await pumpEventQueue();

      expect(recorder.statuses, isEmpty);
      expect(recorder.readSubtitleCalls, isEmpty);
    });

    test('completed phonetic analysis for primary track loads enhancements', () async {
      final recorder = _Recorder()..primaryTrackId = 'track-1';
      recorder.build().handle({
        'event': 'phonetic-analysis-job-changed',
        'payload': {
          'status': 'completed',
          'phase_progress': 100,
          'track_id': 'track-1',
        },
      });
      await pumpEventQueue();

      expect(recorder.loadedSpeechEnhancements, ['track-1']);
      expect(recorder.statuses, ['Audio analysis completed · 100%']);
    });

    test('phonetic analysis for a non-primary track is ignored entirely', () async {
      final recorder = _Recorder()..primaryTrackId = 'track-1';
      recorder.build().handle({
        'event': 'phonetic-analysis-job-changed',
        'payload': {
          'status': 'completed',
          'phase_progress': 100,
          'track_id': 'track-2',
        },
      });
      await pumpEventQueue();

      expect(recorder.loadedSpeechEnhancements, isEmpty);
      expect(recorder.statuses, isEmpty);
    });

    test('lexical-entry-changed forwards the normalized form and entry', () async {
      final recorder = _Recorder();
      recorder.build().handle(_lexicalEntryPayload(normalized: 'going', display: 'Going'));
      await pumpEventQueue();

      expect(recorder.updatedForms, ['going']);
      expect(recorder.updatedEntries.single.displayForm, 'Going');
      expect(recorder.updatedEntries.single.normalizedForm, 'going');
    });

    test('unknown events are a no-op and do not throw', () async {
      final recorder = _Recorder()..mediaId = 'media-1';
      recorder.build().handle({'event': 'mystery-event', 'payload': {}});
      await pumpEventQueue();

      expect(recorder.loadWordEntriesCalls, 0);
      expect(recorder.statuses, isEmpty);
      expect(recorder.updatedForms, isEmpty);
    });
  });
}
