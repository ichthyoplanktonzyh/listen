import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/widgets/flows/media_import_flows.dart';

void main() {
  testWidgets('add source validates URL and identifies YouTube', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());

    await tester.tap(find.widgetWithText(FilledButton, 'Add source'));
    await tester.pump();
    expect(find.text('Enter a valid http or https address.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('online-source-url')),
      'https://www.youtube.com/watch?v=fixture',
    );
    await tester.pump();
    expect(find.text('YouTube'), findsOneWidget);

    // S2 token provenance: the recognized-source glyph and the authorization
    // notice glyph are both `control` — they used to be 20 and 18, two steps
    // apart in a dialog where they play the same role.
    expect(
      tester.widget<Icon>(find.byIcon(Icons.play_circle_outline)).size,
      ListenIconSize.control,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.gavel_outlined)).size,
      ListenIconSize.control,
    );

    await tester.tap(find.text('Download to this Mac'));
    await tester.pump();
    final control = tester.widget<SegmentedButton<OnlineSourceAction>>(
      find.byType(SegmentedButton<OnlineSourceAction>),
    );
    expect(control.selected, {OnlineSourceAction.download});
  });
}

class _Harness extends StatelessWidget {
  const _Harness();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: OnlineSourceDialog()),
  );
}
