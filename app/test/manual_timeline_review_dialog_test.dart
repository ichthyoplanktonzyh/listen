import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/manual_review_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/panels/manual_timeline_review_dialog.dart';

/// The manual timing dialog's two S6 (#7) claims.
///
/// It was one of the three surfaces welded to a single language: ~10 English
/// literals and **zero** `l.text`, so a learner with a Chinese interface opened
/// it to a screen of English and switching the interface language did nothing.
/// It also interpolated a caught exception into its own message box.
void main() {
  const cue = Cue(
    id: 'sentence-1',
    index: 0,
    start: Duration(milliseconds: 1000),
    end: Duration(milliseconds: 3000),
    text: 'Hello world',
    tokens: [
      SubtitleToken(index: 0, kind: 'word', text: 'Hello', normalized: 'hello'),
      SubtitleToken(index: 1, kind: 'word', text: 'world', normalized: 'world'),
    ],
  );
  const track = SubtitleTrack(id: 'track-1', mediaId: 'media-1', cues: [cue]);
  const sourceTimeline = WordTimeline(
    id: 'timeline-source',
    trackId: 'track-1',
    mediaId: 'media-1',
    algorithmId: 'mfa',
    algorithmVersion: '2.0',
    configHash: 'hash',
    createdBy: 'algorithm',
    status: 'active',
    metricsJson: TimelineMetrics.empty(),
    words: [
      WordTiming(
        sentenceId: 'sentence-1',
        tokenIndex: 0,
        text: 'Hello',
        start: Duration(milliseconds: 1100),
        end: Duration(milliseconds: 1600),
        source: 'forced_aligned',
        provider: 'mfa',
        providerVersion: '2.0',
        confidence: 0.9,
      ),
      WordTiming(
        sentenceId: 'sentence-1',
        tokenIndex: 1,
        text: 'world',
        start: Duration(milliseconds: 1700),
        end: Duration(milliseconds: 2400),
        source: 'forced_aligned',
        provider: 'mfa',
        providerVersion: '2.0',
        confidence: 0.8,
      ),
    ],
    createdAt: Duration.zero,
    updatedAt: Duration.zero,
  );

  ManualReviewDraft newDraft() => ManualReviewDraft(
    track: track,
    sourceTimeline: sourceTimeline,
    words: sourceTimeline.words,
    initialCue: cue,
  );

  Future<ManualReviewDraft> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Future<void> Function(ManualReviewDraft draft)? onSave,
  }) async {
    final draft = newDraft();
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ManualTimelineReviewDialog(
          draft: draft,
          onPlayRange: (start, end) async {},
          onSave: onSave ?? (draft) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    return draft;
  }

  testWidgets('the dialog speaks the interface language, in both directions', (
    tester,
  ) async {
    for (final locale in const [Locale('en'), Locale('zh')]) {
      await pump(tester, locale: locale);
      final l = AppLocalizations(locale);

      // The chrome the surface owns: title, the two playback actions, the
      // boundary column headings and the three dialog buttons.
      for (final key in const [
        'manualTimingTitle',
        'manualTimingPlaySentence',
        'manualTimingPlayWord',
        'manualTimingBoundariesValid',
        'manualTimingResetSentence',
        'manualTimingSaveRevision',
        'cancel',
      ]) {
        expect(
          find.text(l.text(key)),
          findsOneWidget,
          reason: '$key is missing under $locale',
        );
      }
      // Start/End label one column each.
      expect(find.text(l.text('manualTimingStart')), findsNWidgets(2));
      expect(find.text(l.text('manualTimingEnd')), findsNWidgets(2));
      // Interpolated, so it is the one shape a `replaceAll` typo would break.
      expect(
        find.text(l.text('manualTimingSentence').replaceAll('{index}', '1')),
        findsOneWidget,
      );
      expect(
        find.byTooltip(l.text('manualTimingPreviousSentence')),
        findsOneWidget,
      );
    }
  });

  testWidgets('under a Chinese interface nothing English is left on screen', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('zh'));

    // The literals this surface used to be made of, none of which may survive
    // a locale the learner actually chose.
    for (final english in const [
      'Manual word timing review',
      'Play sentence',
      'Play word',
      'Current sentence boundaries are valid.',
      'Reset sentence',
      'Save revision',
      'Cancel',
      'Previous sentence',
    ]) {
      expect(find.text(english), findsNothing, reason: '$english survived');
    }
  });

  testWidgets('an edited row says you adjusted it, in the reader language', (
    tester,
  ) async {
    final draft = await pump(tester, locale: const Locale('zh'));
    final l = AppLocalizations(const Locale('zh'));

    // Before the edit the row carries the algorithm's provenance verbatim —
    // that is a wire value about where the timing came from, not copy.
    expect(find.text('forced_aligned'), findsNWidgets(2));
    expect(find.text(l.text('manualTimingUserAdjusted')), findsNothing);

    draft.updateWordBoundary(
      sentenceId: 'sentence-1',
      tokenIndex: 0,
      start: const Duration(milliseconds: 1123),
    );
    await tester.tap(find.text('Hello').first);
    await tester.pumpAndSettle();

    expect(find.text(l.text('manualTimingUserAdjusted')), findsOneWidget);
    expect(find.text('user adjusted'), findsNothing);

    // S2 token provenance: a word row is the repeating unit a user scans down,
    // so its inset is the `row` role rather than the 10/8 it composed by hand.
    expect(
      tester
          .widget<Padding>(
            find
                .ancestor(
                  of: find.text('Hello').first,
                  matching: find.byType(Padding),
                )
                .first,
          )
          .padding,
      ListenPadding.row,
    );
    expect(
      find.text(l.text('manualTimingEditedCount').replaceAll('{count}', '1')),
      findsOneWidget,
    );
  });

  testWidgets('a failed save names the state and leaks no transport detail', (
    tester,
  ) async {
    // The exact envelope from the field report that opened #62: it carries an
    // internal error code, a correlation id, a loopback port and an internal
    // route, and the dialog used to render all four.
    const body =
        '{"code":"validation_error","message":"recording metadata must not be '
        'empty","correlation_id":"api-853","retryable":false}';
    final draft = await pump(
      tester,
      onSave: (draft) async => throw const HttpException(body, uri: null),
    );
    final l = AppLocalizations(const Locale('en'));

    draft.updateWordBoundary(
      sentenceId: 'sentence-1',
      tokenIndex: 0,
      start: const Duration(milliseconds: 1123),
    );
    await tester.tap(find.text('Hello').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.text('manualTimingSaveRevision')));
    await tester.pumpAndSettle();

    // A `validation_error` is the one case a learner can act on, so it gets
    // its own sentence rather than the generic one. `_MessageBox` joins its
    // lines into a single `Text`, hence `textContaining`.
    expect(
      find.textContaining(l.text('manualTimingSaveRejected')),
      findsOneWidget,
    );
    // The reference id survives — it is what makes a bug report actionable —
    // and nothing else from the envelope does.
    expect(
      find.textContaining(
        l.text('failureReference').replaceAll('{id}', 'api-853'),
      ),
      findsOneWidget,
    );
    for (final leak in const [
      'validation_error',
      'recording metadata must not be empty',
      'HttpException',
      '127.0.0.1',
    ]) {
      expect(
        find.textContaining(leak),
        findsNothing,
        reason: '$leak reached the screen',
      );
    }
  });

  testWidgets('editing again clears a stale failure message', (tester) async {
    final draft = await pump(
      tester,
      onSave: (draft) async => throw const HttpException('boom', uri: null),
    );
    final l = AppLocalizations(const Locale('en'));

    draft.updateWordBoundary(
      sentenceId: 'sentence-1',
      tokenIndex: 0,
      start: const Duration(milliseconds: 1123),
    );
    await tester.tap(find.text('Hello').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.text('manualTimingSaveRevision')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining(l.text('manualTimingSaveFailed')),
      findsOneWidget,
    );

    // The message named a state of the last attempt, against boundaries that
    // no longer exist.
    await tester.tap(find.text('+10').first);
    await tester.pumpAndSettle();
    expect(find.textContaining(l.text('manualTimingSaveFailed')), findsNothing);
  });
}
