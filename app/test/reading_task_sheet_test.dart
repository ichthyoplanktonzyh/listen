import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/reading_task_controller.dart';
import 'package:llplayer_next/data/repositories/reading_task_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/reading_task_sheet.dart';
import 'package:llplayer_next/widgets/panels/reading_task_studio.dart';

const _source = ReadingTaskSource(
  anchorCueId: 'cue-1',
  mediaId: 'media-1',
  trackId: 'track-1',
  startMs: 1000,
  endMs: 9000,
  sourceLanguage: 'en',
  responseLanguage: 'zh',
  transcriptSnapshot: 'A quake struck Mindanao.',
);

const _template = [
  RubricPointView(
    pointId: 'main-idea',
    importance: 'required',
    statement: 'Main idea point',
  ),
];

Map<String, dynamic> _rubricJson() => {
  'id': 'rubric-x',
  'purpose': 'reading_comprehension',
  'source': {
    'media_id': 'media-1',
    'track_id': 'track-1',
    'start_ms': 1000,
    'end_ms': 9000,
    'language': 'en',
    'transcript_snapshot': _source.transcriptSnapshot,
  },
  'response_language': 'zh',
  'points': [
    {
      'point_id': 'main-idea',
      'importance': 'required',
      'statement': 'Main idea point',
      'accepted_paraphrase_notes': null,
    },
  ],
  'version': 1,
  'provenance': {'kind': 'manual'},
  'revision': null,
  'created_at_ms': 5,
};

LocalApi _fakeApi() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async {
    if (method == 'GET' && path.startsWith('/v1/semantic/rubrics/lookup')) {
      return (statusCode: 200, body: 'null');
    }
    if (method == 'POST' && path == '/v1/semantic/rubrics') {
      return (statusCode: 200, body: jsonEncode(_rubricJson()));
    }
    if (method == 'POST' && path == '/v1/semantic/attempts') {
      return (
        statusCode: 200,
        body: jsonEncode({
          'id': 'attempt-x',
          'kind': 'reading_comprehension',
          'rubric_id': 'rubric-x',
          'rubric_version': 1,
          'conditions': {
            'source_text_visible': true,
            'audio_play_count': 0,
            'notes_allowed': false,
          },
          'responses': [
            {
              'revision': 1,
              'transcript': 'My answer',
              'source': 'typed',
              'language': 'zh',
              'recorded_at_ms': 10,
            },
          ],
          'status': 'completed',
          'started_at_ms': 5,
          'ended_at_ms': 10,
        }),
      );
    }
    if (method == 'POST' && path == '/v1/semantic/judgments') {
      return (
        statusCode: 200,
        body: jsonEncode({
          'id': 'judgment-x',
          'attempt_id': 'attempt-x',
          'response_revision': 1,
          'rubric_id': 'rubric-x',
          'rubric_version': 1,
          'rubric_source_sha256': 'h1',
          'response_transcript_sha256': 'h2',
          'points': [
            {'point_id': 'main-idea', 'verdict': 'covered'},
          ],
          'abstain': null,
          'provenance': {'kind': 'manual'},
          'evidence_class': 'self_assessment',
          'created_at_ms': 20,
        }),
      );
    }
    return (statusCode: 404, body: '{"code":"not_found"}');
  },
);

Widget _host(ReadingTaskController controller) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ReadingTaskSheet(controller: controller, audioPlayCount: () => 0),
  ),
);

void main() {
  test(
    'draft answer and rubric edits restore after leaving the scene',
    () async {
      final api = _fakeApi();
      final controller = ReadingTaskController(
        repository: LocalReadingTaskRepository(() => api),
      );
      await controller.openTask(source: _source, templatePoints: _template);
      controller.updateDraftPoint(
        0,
        const RubricPointView(
          pointId: 'main-idea',
          importance: 'required',
          statement: 'Edited checkpoint',
        ),
      );
      controller.updateAnswerDraft('Unsubmitted answer');
      controller.closeTask();

      await controller.openTask(source: _source, templatePoints: _template);
      expect(
        controller.state.draftPoints.single.statement,
        'Edited checkpoint',
      );
      expect(controller.state.draftAnswer, 'Unsubmitted answer');
    },
  );

  testWidgets('studio preserves rubric creation as the first stage', (
    tester,
  ) async {
    final api = _fakeApi();
    final controller = ReadingTaskController(
      repository: LocalReadingTaskRepository(() => api),
    );
    await controller.openTask(source: _source, templatePoints: _template);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ReadingTaskStudio(
            controller: controller,
            source: _source,
            audioPlayCount: () => 0,
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.text('Set checkpoints'), findsOneWidget);
    expect(find.text(_source.transcriptSnapshot), findsOneWidget);
    expect(find.text('Main idea point'), findsOneWidget);
    expect(controller.state.phase, 'editing');

    // The studio header is the same object as the reading-diff header, so it
    // takes the same role; it had been insetting 18/10 against that one's 14/8.
    final header = tester.widget<Padding>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('reading-task-back')),
            matching: find.byType(Padding),
          )
          .last,
    );
    expect(header.padding, ListenPadding.row);

    // The source pane is a page of prose, so its wide arrangement takes the
    // page role rather than the 28 it had picked.
    final snapshot = tester.widget<SingleChildScrollView>(
      find.ancestor(
        of: find.text(_source.transcriptSnapshot),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(snapshot.padding, ListenPadding.pageCompact);
  });

  testWidgets('the sheet body insets like a dialog body', (tester) async {
    final api = _fakeApi();
    final controller = ReadingTaskController(
      repository: LocalReadingTaskRepository(() => api),
    );
    await controller.openTask(source: _source, templatePoints: _template);
    await tester.pumpWidget(_host(controller));

    // 20/14 was neither a card nor a page; a sheet body is a dialog body. The
    // keyboard inset is added on top of the role rather than folded into it,
    // so with no keyboard up the inset is exactly the role — asserted as the
    // gap the reader actually sees between the sheet edge and its first glyph.
    final sheet = tester.getRect(find.byType(ReadingTaskSheet));
    final title = tester.getRect(find.byIcon(Icons.checklist_outlined));
    expect(title.left - sheet.left, ListenPadding.card.left);
    expect(title.top - sheet.top, ListenPadding.card.top);

    // The rubric row's star toggle is tappable, so `control`, not `inline`.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.star)).size,
      ListenIconSize.control,
    );
  });

  testWidgets('walks editing → answering → assessing → done', (tester) async {
    final api = _fakeApi();
    final controller = ReadingTaskController(
      repository: LocalReadingTaskRepository(() => api),
    );
    await controller.openTask(source: _source, templatePoints: _template);
    await tester.pumpWidget(_host(controller));

    // Editing: template point visible, save creates rubric v1.
    expect(find.text('Main idea point'), findsOneWidget);
    await tester.tap(find.text('Save rubric'));
    await tester.pumpAndSettle();
    expect(controller.state.phase, 'answering');

    // Answering: type and submit.
    await tester.enterText(
      find.byKey(const ValueKey('reading-task-answer')),
      'My answer',
    );
    await tester.tap(find.text('Submit answer'));
    await tester.pumpAndSettle();
    expect(controller.state.phase, 'assessing');

    // Assessing: submit disabled until every point is judged.
    final submit = find.text('Save self-assessment');
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(of: submit, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('verdict-main-idea-covered')));
    await tester.pump();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(controller.state.phase, 'done');
    expect(find.text('Covered'), findsOneWidget);
  });
}
