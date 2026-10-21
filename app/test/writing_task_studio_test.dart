import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/writing_task_controller.dart';
import 'package:llplayer_next/data/repositories/writing_task_repository.dart';
import 'package:llplayer_next/models/semantic_task.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/writing_task_studio.dart';

const _source = WritingTaskSource(
  anchorCueId: 'cue-1',
  mediaId: 'media-1',
  trackId: 'track-1',
  startMs: 100,
  endMs: 500,
  sourceLanguage: 'en',
  responseLanguage: 'en',
  transcriptSnapshot: 'The source passage.',
);

Map<String, dynamic> _rubric() => {
  'id': 'rubric-1',
  'purpose': 'summary',
  'source': {
    'media_id': 'media-1',
    'track_id': 'track-1',
    'start_ms': 100,
    'end_ms': 500,
    'language': 'en',
    'transcript_snapshot': 'The source passage.',
  },
  'response_language': 'en',
  'points': [
    {
      'point_id': 'task',
      'importance': 'required',
      'statement': 'Complete the task.',
      'accepted_paraphrase_notes': null,
    },
  ],
  'version': 1,
  'provenance': {'kind': 'manual'},
  'created_at_ms': 1,
};

Map<String, dynamic> _attempt() => {
  'id': 'attempt-1',
  'kind': 'summary',
  'rubric_id': 'rubric-1',
  'rubric_version': 1,
  'conditions': {
    'source_text_visible': true,
    'audio_play_count': null,
    'notes_allowed': true,
    'prompt_snapshot': 'Summarize.',
  },
  'responses': [
    {
      'revision': 1,
      'raw_transcript': null,
      'transcript': 'My summary.',
      'source': 'typed',
      'language': 'en',
      'recorded_at_ms': 2,
    },
  ],
  'status': 'completed',
  'started_at_ms': 1,
  'ended_at_ms': 2,
};

LocalApi _api() => LocalApi.withTransport(
  baseUrl: 'http://test',
  token: 'tok',
  transport: (method, path, body) async {
    final response = switch ((method, path)) {
      ('GET', final value)
          when value.startsWith('/v1/semantic/rubrics/lookup') =>
        _rubric(),
      ('GET', '/v1/semantic/rubrics/rubric-1/attempts') => <dynamic>[],
      ('GET', '/v1/semantic/writing-drafts/rubric-1') => null,
      ('POST', '/v1/semantic/attempts') => _attempt(),
      ('DELETE', '/v1/semantic/writing-drafts/rubric-1') => null,
      ('POST', '/v1/semantic/attempts/attempt-1/writing-findings/local') =>
        <dynamic>[],
      _ => throw StateError(
        'Unexpected request: $method $path ${jsonEncode(body)}',
      ),
    };
    return (statusCode: 200, body: jsonEncode(response));
  },
);

void main() {
  testWidgets('editor is primary and feedback appears only after request', (
    tester,
  ) async {
    final api = _api();
    final controller = WritingTaskController(
      repository: LocalWritingTaskRepository(() => api),
    );
    await controller.openTask(
      source: _source,
      kind: WritingTaskController.summaryKind,
      promptSnapshot: 'Summarize.',
      fixedRubricPoints: const [
        RubricPointView(
          pointId: 'task',
          importance: 'required',
          statement: 'Complete the task.',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 1200,
          height: 800,
          child: WritingTaskStudio(
            controller: controller,
            audioPlayCount: () => 0,
            onKindChanged: (_) {},
            onPlaySource: () {},
            onClose: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('writing-editor')), findsOneWidget);
    expect(find.text('Requested feedback'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('writing-editor')),
      'My summary.',
    );
    await tester.pump();
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('writing-request-feedback')), findsOneWidget);
    expect(find.text('Requested feedback'), findsNothing);

    // The saved-draft phase is where S2's column and icon steps land. The
    // confirmation glyph is an illustration — it states the outcome on its own
    // rather than labelling a control — and the column is a studio card, not
    // the 620 it had picked.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.check_circle_outline)).size,
      ListenIconSize.illustration,
    );
    final caps = tester
        .widgetList<ConstrainedBox>(
          find.ancestor(
            of: find.byKey(const Key('writing-request-feedback')),
            matching: find.byType(ConstrainedBox),
          ),
        )
        .map((box) => box.constraints.maxWidth);
    expect(caps, contains(ListenBreakpoints.cardColumnMax));
    expect(caps, isNot(contains(620.0)));
    // The studio surface insets as a page, not at the 20 it had. Identified by
    // shape rather than position, since `SafeArea` contributes a zero-inset
    // `Padding` of its own above it.
    final surface = tester
        .widgetList<Padding>(
          find.descendant(
            of: find.byType(WritingTaskStudio),
            matching: find.byType(Padding),
          ),
        )
        .firstWhere((padding) => padding.child is Column);
    expect(surface.padding, ListenPadding.pageCompact);

    await tester.tap(find.byKey(const Key('writing-request-feedback')));
    await tester.pumpAndSettle();
    expect(find.text('Requested feedback'), findsOneWidget);
    expect(find.textContaining('No local rule findings'), findsOneWidget);
  });
}
