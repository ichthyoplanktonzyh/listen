import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/player/retention_menu.dart';

/// The Keep affordance: Temporary Material offers Keep (copy, the default) and
/// reference-in-place; Personal Library material shows its retained state and
/// offers unretain; in-flight work renders as the unified waiting mark and
/// refuses re-entry. Success/error feedback lives on the status line, so this
/// widget only forwards intent — an exception can never reach it.
void main() {
  setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

  Future<PlayerController> pump(WidgetTester tester, RetentionMenu menu) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ListenTheme.dark(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: Center(child: menu)),
      ),
    );
    await tester.pumpAndSettle();
    return menu.player;
  }

  testWidgets('temporary media shows Keep with copy as the first choice', (
    tester,
  ) async {
    final player = PlayerController();
    var copies = 0;
    var references = 0;
    await pump(
      tester,
      RetentionMenu(
        player: player,
        onKeepCopy: () => copies++,
        onKeepReference: () => references++,
        onUnretain: () {},
      ),
    );
    player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    player.setMediaRetained(false);
    await tester.pumpAndSettle();

    expect(find.text('Keep'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retention-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Keep a copy'), findsOneWidget);
    expect(find.text('Keep as reference'), findsOneWidget);
    expect(find.text('Remove from Personal Library'), findsNothing);

    // Copy is the default action; the reference is explicitly secondary.
    await tester.tap(find.text('Keep a copy'));
    await tester.pumpAndSettle();
    expect(copies, 1);
    expect(references, 0);
  });

  testWidgets('reference in place is the secondary choice', (tester) async {
    final player = PlayerController();
    var references = 0;
    await pump(
      tester,
      RetentionMenu(
        player: player,
        onKeepCopy: () {},
        onKeepReference: () => references++,
        onUnretain: () {},
      ),
    );
    player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    player.setMediaRetained(false);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('retention-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep as reference'));
    await tester.pumpAndSettle();
    expect(references, 1);
  });

  testWidgets('retained media shows its state and offers unretain only', (
    tester,
  ) async {
    final player = PlayerController();
    var unkept = 0;
    await pump(
      tester,
      RetentionMenu(
        player: player,
        onKeepCopy: () {},
        onKeepReference: () {},
        onUnretain: () => unkept++,
      ),
    );
    player.setMedia(
      id: 'media-1',
      path: '/store/copy.mp3',
      title: 'Kept',
      fingerprint: 'fp',
    );
    player.setMediaRetained(true);
    await tester.pumpAndSettle();

    expect(find.text('In your Personal Library'), findsOneWidget);
    expect(find.text('Keep'), findsNothing);

    await tester.tap(find.byKey(const Key('retention-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Remove from Personal Library'), findsOneWidget);
    expect(find.text('Keep a copy'), findsNothing);
    expect(find.text('Keep as reference'), findsNothing);

    await tester.tap(find.text('Remove from Personal Library'));
    await tester.pumpAndSettle();
    expect(unkept, 1);
  });

  testWidgets('an in-flight retention shows waiting and refuses the menu', (
    tester,
  ) async {
    final player = PlayerController();
    await pump(
      tester,
      RetentionMenu(
        player: player,
        onKeepCopy: () {},
        onKeepReference: () {},
        onUnretain: () {},
      ),
    );
    player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    player.setMediaRetained(false);
    player.setRetentionInFlight(true);
    // The breathing mark animates forever, so this state cannot pumpAndSettle.
    await tester.pump();

    // The unified waiting language, not a spinner and not a dead button.
    expect(find.text('Keep'), findsNothing);
    expect(find.byKey(const Key('retention-menu')), findsNothing);
  });

  testWidgets('no media renders nothing', (tester) async {
    await pump(
      tester,
      RetentionMenu(
        player: PlayerController(),
        onKeepCopy: () {},
        onKeepReference: () {},
        onUnretain: () {},
      ),
    );

    expect(find.text('Keep'), findsNothing);
    expect(find.byKey(const Key('retention-menu')), findsNothing);
  });
}
