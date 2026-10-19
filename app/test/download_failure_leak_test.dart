import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/download_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/external_tools.dart';
import 'package:llplayer_next/widgets/player/download_status_bar.dart';

/// The download bar, driven by a download that really fails.
///
/// This pair is the one `#66` could not close: `DownloadController` stored
/// `error.toString()`, and `DownloadStatusBar` assembled
/// `'${l.text('downloadFailed')}: ${status.error}'` — the sentence was built
/// *in the widget*, so no controller-side change could fix it.
///
/// Both scenarios drive a real failure through the real plumbing rather than
/// handing the controller a hand-written string:
///
/// - a real `Process` that exits non-zero after writing yt-dlp's own stderr,
///   carried by the real [OnlineMediaDownload], which is what the flow
///   attaches to;
/// - a real `ProcessException` from `Process.start` against a path that is not
///   there, which is what the flow's outer `catch` sees when the tool is
///   missing.
///
/// The real process work runs inside [WidgetTester.runAsync] — a widget test's
/// clock is fake, and a real `exitCode` future never completes under it.
///
/// The assertions run over what the bar *renders*, so they hold against the
/// pre-fix code as well, which is how they were verified red.
void main() {
  /// One line of real yt-dlp stderr. It names the tool, an internal flag and a
  /// site-specific extractor — none of which is a sentence, and all of which
  /// the bar used to print after a colon.
  const stderrLine =
      'ERROR: [youtube] dQw4w9WgXcQ: Sign in to confirm you are not a bot. '
      'Use --cookies-from-browser or --cookies for the authentication.';

  /// Tool output is not copy. Whatever the process said, the bar says one
  /// sentence.
  const leaks = [
    'ERROR:',
    'yt-dlp',
    'youtube',
    'dQw4w9WgXcQ',
    '--cookies',
    'exited with status',
    'Exception',
    'ProcessException',
    '/nonexistent',
  ];

  void expectNoLeak(WidgetTester tester) {
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');
    for (final leak in leaks) {
      expect(
        text,
        isNot(contains(leak)),
        reason:
            '"$leak" is tool diagnostics; the download bar is not a place to '
            'print it. Bar said:\n$text',
      );
    }
  }

  Future<void> pumpBar(WidgetTester tester, DownloadStatusSnapshot snapshot) =>
      tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: DownloadStatusBar(
              status: snapshot,
              onCancel: () {},
              onOpenMediaPath: () {},
              onDismiss: () {},
            ),
          ),
        ),
      );

  testWidgets('a download whose tool exits non-zero says "Download failed" '
      'and not what the tool printed', (tester) async {
    final controller = DownloadController();
    addTearDown(controller.dispose);

    await tester.runAsync(() async {
      // The real OnlineMediaDownload over a real process: exit 1, stderr set.
      final process = await Process.start('/bin/sh', [
        '-c',
        'echo ${_shellQuote(stderrLine)} >&2; exit 1',
      ]);
      final download = OnlineMediaDownload(process);
      controller.attach(
        progress: download.progress,
        completed: download.completed,
        cancel: download.cancel,
      );
      await download.completed.then<void>((_) {}, onError: (Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });

    expect(controller.snapshot?.kind, DownloadStatusKind.failed);
    await pumpBar(tester, controller.snapshot!);

    // Sweep first, so a red run prints what the bar actually said.
    expectNoLeak(tester);
    expect(find.text('Download failed'), findsOneWidget);
  });

  testWidgets('a download that cannot even start says the same sentence', (
    tester,
  ) async {
    // A short auto-dismiss so the failed bar's timer does not outlive the
    // test under the fake clock.
    final controller = DownloadController(
      failedAutoDismiss: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    Object? thrown;
    await tester.runAsync(() async {
      // What the flow's outer catch actually sees when the tool is not there.
      try {
        await Process.start('/nonexistent/yt-dlp', const ['--version']);
      } catch (error) {
        thrown = error;
      }
    });
    expect(thrown, isA<ProcessException>());
    // The pre-fix flow called `downloadController.fail(error.toString())`,
    // which is how "ProcessException" reached the bar.
    expect('$thrown', contains('ProcessException'));

    controller.fail(describeApiFailure(thrown!));

    expect(controller.snapshot?.kind, DownloadStatusKind.failed);
    await pumpBar(tester, controller.snapshot!);

    // Sweep first, so a red run prints what the bar actually said.
    expectNoLeak(tester);
    expect(find.text('Download failed'), findsOneWidget);

    // Let the auto-dismiss timer fire so none is left pending.
    await tester.pump(const Duration(milliseconds: 20));
  });

  test('the snapshot still carries what the process said, off screen', () {
    final controller = DownloadController();
    addTearDown(controller.dispose);

    controller.fail(describeApiFailure(const ExternalToolError(stderrLine)));

    // Nothing is thrown away: the diagnostic channel keeps it, and
    // ApiFailure.raw is documented as never rendered.
    expect(controller.snapshot?.failure?.raw, contains('dQw4w9WgXcQ'));
  });
}

/// A tiny sh quoter so the stderr line survives the shell verbatim.
String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";
