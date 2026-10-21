import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/controllers/semantic_search_view_model.dart';
import 'package:llplayer_next/controllers/slice_player_controller.dart';
import 'package:llplayer_next/controllers/vocabulary_view_model.dart';
import 'package:llplayer_next/data/repositories/lexical_repository.dart';
import 'package:llplayer_next/data/repositories/semantic_search_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/vocabulary_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/widgets/vocabulary/vocabulary_book_view.dart';

Map<String, dynamic> _entry(String id, String form) => {
  'entry': {
    'id': id,
    'normalized_form': form.toLowerCase(),
    'display_form': form,
    'kind': 'word',
    'language': 'en',
  },
  'history': <dynamic>[],
  'occurrences': <dynamic>[],
  'sense_folders': <dynamic>[],
  'capability_profile': {
    'lexical_entry_id': id,
    'sense_id': null,
    for (final capability in const [
      'reading',
      'listening',
      'speaking',
      'writing',
    ])
      capability: {'projection': null, 'user_override': null},
  },
};

void main() {
  testWidgets(
    'the vocabulary lens filters four channels without coach or gap requests',
    (tester) async {
      final requests = <String>[];
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          requests.add('$method $path');
          if (method == 'GET' && path.startsWith('/v1/vocabulary?')) {
            return (
              statusCode: 200,
              body: jsonEncode([_entry('entry-endedup', 'ended up')]),
            );
          }
          if (method == 'GET' && path.startsWith('/v1/hunting/targets?')) {
            return (statusCode: 200, body: '[]');
          }
          return (statusCode: 404, body: 'not found');
        },
      );
      final viewModel = VocabularyViewModel(
        repository: LexicalRepository(api),
        language: 'en',
      );
      final semanticSearch = SemanticSearchViewModel(
        LocalSemanticSearchRepository(api),
      );
      final hunting = HuntingController();
      final audio = AuxiliaryAudioController();
      final slicePlayer = SlicePlayerController();
      addTearDown(viewModel.dispose);
      addTearDown(semanticSearch.dispose);
      addTearDown(hunting.dispose);
      addTearDown(audio.dispose);
      addTearDown(slicePlayer.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });

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
            body: VocabularyScreen(
              viewModel: viewModel,
              semanticSearchViewModel: semanticSearch,
              slicePlayer: slicePlayer,
              language: 'en',
              onExport: () async {},
              onImport: () async {},
              huntingController: hunting,
              auxiliaryAudio: audio,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VocabularyBookView), findsOneWidget);
      expect(find.text('ended up'), findsOneWidget);
      final speakingChip = find.widgetWithText(ChoiceChip, 'Speaking');
      expect(speakingChip, findsOneWidget);
      expect(tester.widget<ChoiceChip>(speakingChip).selected, isFalse);
      final vocabularyRequestCount = requests
          .where((request) => request.startsWith('GET /v1/vocabulary?'))
          .length;

      await tester.tap(speakingChip);
      await tester.pumpAndSettle();

      expect(tester.widget<ChoiceChip>(speakingChip).selected, isTrue);
      expect(
        requests.where((request) => request.contains('capability=speaking')),
        hasLength(1),
      );
      expect(
        requests.where((request) => request.startsWith('GET /v1/vocabulary?')),
        hasLength(vocabularyRequestCount + 1),
      );
      expect(
        requests.any(
          (request) =>
              request.contains('/v1/coach/') ||
              request.contains('/v1/production-gap/') ||
              request.contains('/v1/review/cross-modal') ||
              request.contains('/v1/hunting/candidates'),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
