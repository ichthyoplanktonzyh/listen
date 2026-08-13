import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// R1 whole-media ASR cutover gate.
///
/// Whole-media transcription no longer reaches Core's `/v1/transcription/jobs`
/// surface: the job API methods, the wire model, the SSE event and the
/// transcription center are gone. The retained surface is the provider/model
/// operations the learner recording and realtime paths need, and every
/// missing-transcript action opens the adopted listen-gen capability journey.
///
/// These are source-level checks, the same style as
/// `window_min_size_test.dart` pinning the Swift declaration: the app's own
/// composition root and menu surface are the place the dead path could
/// silently come back, so the gate reads the wiring itself.
void main() {
  test('the transcription API exposes no whole-media job path', () {
    final source = File(
      'lib/services/api/transcription.dart',
    ).readAsStringSync();

    // Retained: provider/model operations (learner recording and realtime
    // model selection) and the recording-transcription job surface.
    expect(source, contains('/v1/transcription/providers'));
    expect(source, contains('/v1/transcription/models'));
    expect(source, contains('/v1/recording-transcriptions'));

    // Removed: the whole-media job surface. A stray `/v1/transcription/jobs`
    // literal or a job method here means the old path was reintroduced.
    expect(source, isNot(contains('/v1/transcription/jobs')));
    expect(source, isNot(contains('transcriptionJobs')));
    expect(source, isNot(contains('createTranscriptionJob')));
    expect(source, isNot(contains('cancelTranscriptionJob')));
    expect(source, isNot(contains('retryTranscriptionJob')));
    expect(source, isNot(contains('archiveTranscriptionJob')));
  });

  test('no whole-media TranscriptionJob wire model or SSE event remains', () {
    final runtime = File(
      'lib/models/runtime_resources.dart',
    ).readAsStringSync();
    expect(runtime, isNot(contains('class TranscriptionJobView')));

    final events = File('lib/models/backend_event.dart').readAsStringSync();
    expect(events, isNot(contains('TranscriptionJobChangedEvent')));
    expect(events, isNot(contains('transcription-job-changed')));

    final fixture = File(
      'test/fixtures/events/examples.json',
    ).readAsStringSync();
    expect(fixture, isNot(contains('transcription-job-changed')));
  });

  test('the transcription center is unreachable from any shell chrome', () {
    // The panel file itself is gone; `TranscriptionCenter` could not render
    // even if a stale import pointed at it.
    expect(File('lib/transcription_ui.dart').existsSync(), isFalse);

    // The rail's tools menu, the native macOS menu bar and the composition
    // root no longer wire an action into the center.
    for (final path in [
      'lib/widgets/navigation/shell_tools_menu.dart',
      'lib/widgets/app_bar/macos_menu_bar.dart',
      'lib/main.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('onOpenTranscriptionCenter')));
      expect(source, isNot(contains('openTranscriptionCenterFlow')));
      expect(source, isNot(contains('TranscriptionCenterViewModel')));
    }
  });

  test('missing-transcript actions open the transcript readiness surface', () {
    final main = File('lib/main.dart').readAsStringSync();
    // The workbench's generate action opens the readiness surface (which
    // drives the capability coordinator through resolution/production) and
    // its selection always activates the primary track, so the menu has no
    // secondary whole-media generate entry.
    expect(main, contains('_generateSubtitles'));
    expect(main, contains('prepareLearningTranscript'));

    // No whole-media generate/regenerate flow remains to route to a Core job.
    expect(main, isNot(contains('generateSubtitlesFlow')));
    expect(
      File('lib/widgets/flows/subtitle_resource_flows.dart').readAsStringSync(),
      isNot(contains('generateSubtitlesFlow')),
    );
  });

  test('learner recording and realtime transcription remain', () {
    final api = File('lib/services/api/transcription.dart').readAsStringSync();
    // Recording-transcription jobs (speaking-task transcription) stay wired.
    expect(api, contains('createRecordingTranscription'));
    expect(api, contains('recordingTranscriptionJob'));
    expect(api, contains('cancelRecordingTranscription'));

    // Realtime learner transcription keeps its model selection controller.
    expect(
      File(
        'lib/controllers/realtime_transcription_model_controller.dart',
      ).readAsStringSync(),
      contains('class RealtimeTranscriptionModelController'),
    );
    // The model repository surface it selects from stays available.
    final repository = File(
      'lib/data/repositories/transcription_repository.dart',
    ).readAsStringSync();
    expect(
      repository,
      contains('Future<List<TranscriptionModelView>> models()'),
    );
    expect(repository, isNot(contains('createJob')));
    expect(repository, isNot(contains('readSubtitle')));
  });

  test('whisper-cli, ffmpeg and ffprobe are shared, not Gen-owned at R1', () {
    // backend.lock verifies the Core runtime artifact, and the release
    // assembly ships and smoke-checks the same bundled tools beside api-http.
    final build = File('tool/build-macos-release.sh').readAsStringSync();
    expect(build, contains('.backend/runtime'));
    final smoke = File('tool/verify-macos-release.sh').readAsStringSync();
    for (final tool in ['whisper-cli', 'ffmpeg', 'ffprobe']) {
      expect(
        smoke,
        contains('Resources/runtime/$tool'),
        reason:
            '$tool must ship in the Core runtime artifact the release '
            'verifies, so it cannot be Gen-only',
      );
    }

    // The app resolves the shared tools itself and only hands their paths to
    // the pinned generator.
    final setup = File(
      'lib/services/content_generator_setup.dart',
    ).readAsStringSync();
    for (final tool in ['whisper-cli', 'ffprobe', 'ffmpeg']) {
      expect(setup, contains(tool));
    }

    // Gen declares the tool roles its providers require instead of owning any
    // of them exclusively.
    final release = File(
      'lib/services/listen_gen_release_service.dart',
    ).readAsStringSync();
    expect(release, contains('provider_requirements'));
    expect(release, contains("'whisper-cpp'"));
  });
}
