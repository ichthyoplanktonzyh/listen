import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/hunting_session_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/widgets/panels/hunting_prompt_card.dart';

import 'hunting_session_controller_test.dart' show huntingOccurrence;

void main() {
  testWidgets('hunting prompt moves from priming to three-way check', (
    tester,
  ) async {
    String? answered;
    final api = LocalApi.withTransport(
      baseUrl: 'http://test',
      token: 'tok',
      transport: (method, path, body) async => (
        statusCode: 200,
        body: jsonEncode({
          'indexed': true,
          'occurrences': [huntingOccurrence('o1', 't1', 2000)],
        }),
      ),
    );
    final controller = HuntingSessionController();
    addTearDown(controller.dispose);
    await controller.start(
      api: api,
      sessionId: 'session-1',
      mediaId: 'media-1',
      trackId: 'track-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: HuntingPromptCard(
            controller: controller,
            onAnswer: (value) => answered = value,
            onReindex: () {},
          ),
        ),
      ),
    );

    controller.updatePosition(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(find.text('Listen for “target t1”'), findsOneWidget);

    // S2 token provenance: the prompt is one instruction and up to three
    // answers, so its shell takes `formColumnMax` from the shared column
    // vocabulary. The 560 it used to hard-code happened to be the same number,
    // which is exactly why nobody noticed it was a private decision.
    expect(
      tester
          .widget<ConstrainedBox>(
            find
                .ancestor(
                  of: find.text('Listen for “target t1”'),
                  matching: find.byType(ConstrainedBox),
                )
                .last,
          )
          .constraints
          .maxWidth,
      ListenBreakpoints.formColumnMax,
    );

    controller.updatePosition(const Duration(milliseconds: 3000));
    await tester.pump();
    expect(find.text('Did you hear “target t1”?'), findsOneWidget);
    expect(find.text('Did not notice'), findsOneWidget);
    await tester.tap(find.text('Did not notice'));
    expect(answered, 'not_noticed');
  });
}
