import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/practice.dart';
import 'package:llplayer_next/models/projection_review.dart';
import 'package:llplayer_next/widgets/vocabulary/listening_status_suggestions.dart';

void main() {
  testWidgets('only listening suggestions and proposals can be confirmed', (
    tester,
  ) async {
    var confirmedUpgrade = 0;
    var confirmedProposal = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListeningStatusSuggestions(
              suggestions: [
                _upgrade('listening-1', 'listening'),
                _upgrade('writing-1', 'writing'),
              ],
              suggestionsLoading: false,
              suggestionsFailure: null,
              proposals: [
                _proposal('listening-proposal', 'listening'),
                _proposal('speaking-proposal', 'speaking'),
              ],
              proposalsLoading: false,
              proposalsFailure: null,
              onConfirmSuggestion: (_) async {
                confirmedUpgrade++;
                return null;
              },
              onRejectSuggestion: (_) async => null,
              onDecideProposal: (proposal, decision) async {
                expect(proposal.capability, 'listening');
                expect(decision, 'confirm');
                confirmedProposal++;
                return null;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('upgrade-confirm-listening-1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('upgrade-confirm-writing-1')), findsNothing);
    expect(
      find.byKey(const Key('projection-confirm-listening-proposal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('projection-confirm-speaking-proposal')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('upgrade-confirm-listening-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('projection-confirm-listening-proposal')),
    );
    await tester.pumpAndSettle();
    expect(confirmedUpgrade, 1);
    expect(confirmedProposal, 1);
  });
}

UpgradeSuggestion _upgrade(String id, String capability) => UpgradeSuggestion(
  id: id,
  lexicalEntryId: 'lexical-1',
  lexicalDisplayForm: 'notice',
  previousStatus: null,
  suggestedStatus: null,
  status: 'pending',
  evidenceContextCount: 3,
  evidenceIds: const ['evidence-1'],
  threshold: 3,
  evidenceClass: 'listening',
  createdAtMs: 1,
  resolvedAtMs: null,
  cooldownUntilMs: null,
  capability: capability,
  previousAssessment: 'unassessed',
  suggestedAssessment: 'known_recognized',
);

ProjectionProposalView _proposal(String id, String capability) =>
    ProjectionProposalView(
      id: id,
      lexicalEntryId: 'lexical-1',
      capability: capability,
      proposedConclusion: 'acquired',
      algorithmVersion: 'v1',
      confidence: 0.8,
      evidenceAsOfMs: 1,
      evidence: const [],
      rationale: 'listening evidence',
      status: 'pending',
      createdAtMs: 1,
    );
