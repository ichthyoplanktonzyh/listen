import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/auxiliary_audio_controller.dart';
import 'package:llplayer_next/controllers/hunting_controller.dart';
import 'package:llplayer_next/data/repositories/lexical_repository.dart';
import 'package:llplayer_next/data/repositories/semantic_search_repository.dart';
import 'package:llplayer_next/screens/vocabulary_screen.dart';
import 'package:llplayer_next/services/api_service.dart';

void main() {
  testWidgets(
    'first frame does not notify the shared hunting controller mid-build',
    (tester) async {
      final api = LocalApi.withTransport(
        baseUrl: 'http://test',
        token: 'tok',
        transport: (method, path, body) async {
          if (method == 'GET' && path.startsWith('/v1/vocabulary?')) {
            return (statusCode: 200, body: '[]');
          }
          if (method == 'GET' && path.startsWith('/v1/hunting/targets?')) {
            return (statusCode: 200, body: '[]');
          }
          if (method == 'GET' && path.startsWith('/v1/hunting/candidates?')) {
            return (statusCode: 200, body: '[]');
          }
          throw StateError('unexpected $method $path');
        },
      );
      final hunting = HuntingController();
      addTearDown(hunting.dispose);
      final auxiliaryAudio = AuxiliaryAudioController();
      addTearDown(auxiliaryAudio.dispose);

      // Mirrors the app shell: main.dart wraps the Navigator in a
      // ListenableBuilder that is already subscribed to the shared hunting
      // controller, and showVocabularyFlow pushes VocabularyScreen as a route.
      // A synchronous notify from the route's initState would then mark that
      // ancestor builder dirty while its subtree is still being built.
      await tester.pumpWidget(
        ListenableBuilder(
          listenable: hunting,
          builder: (context, _) => MaterialApp(
            home: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VocabularyScreen(
                        repository: LexicalRepository(api),
                        semanticSearchRepository: LocalSemanticSearchRepository(
                          api,
                        ),
                        language: 'en',
                        onExport: () async {},
                        onImport: () async {},
                        huntingController: hunting,
                        auxiliaryAudio: auxiliaryAudio,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'route mount must not notify shared listeners during build',
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(hunting.state.busy, isFalse);
    },
  );
}
