import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/home/media_library_section.dart';

MediaLibraryEntry _entry({
  String id = 'media-1',
  String title = 'Media 1',
  String meaningFit = 'comprehensible',
  String soundFit = 'challenging',
  String? intent,
  bool familiar = false,
  bool withFit = true,
}) => MediaLibraryEntry.fromJson({
  'media': {
    'id': id,
    'path': '/tmp/$id.mp4',
    'fingerprint': '$id-fp',
    'title': title,
    'kind': 'video',
    'duration': 60000,
    'availability': 'available',
    'created_at_ms': 1,
    'updated_at_ms': 2,
  },
  'primary_track_id': 'track-$id',
  'fit': withFit
      ? {
          'subject_kind': 'media',
          'subject_id': id,
          'language': 'en',
          'meaning': {'fit': meaningFit, 'signals': <Object>[]},
          'sound': {'fit': soundFit, 'signals': <Object>[]},
          'assessed_token_ratio': 0.9,
          'evidence_grade': 'initial_estimate',
          'algorithm_version': 'content-fit-v2',
          'computed_at_ms': 3,
          'input_fingerprint': 'fp',
        }
      : null,
  'triage_intent': intent,
  'familiar_material': familiar,
});

Widget _host(
  List<MediaLibraryEntry> entries, {
  bool familiarSupplyEnabled = true,
  void Function(MediaLibraryEntry)? onOpen,
  void Function(MediaLibraryEntry)? onStartExtensive,
  void Function(MediaLibraryEntry)? onStartIntensive,
  void Function(MediaLibraryEntry, String?)? onSetIntent,
  void Function(bool)? onToggleFamiliarSupply,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: MediaLibrarySection(
        entries: entries,
        familiarSupplyEnabled: familiarSupplyEnabled,
        onOpen: onOpen ?? (_) {},
        onStartExtensive: onStartExtensive ?? (_) {},
        onStartIntensive: onStartIntensive ?? (_) {},
        onSetIntent: onSetIntent ?? (_, _) {},
        onToggleFamiliarSupply: onToggleFamiliarSupply ?? (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('groups entries by derived queue with golden targets on top', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        _entry(id: 'easy', title: 'Easy', soundFit: 'comprehensible'),
        _entry(id: 'golden', title: 'Golden'),
        _entry(id: 'hard', title: 'Hard', meaningFit: 'too_hard'),
        _entry(id: 'unrated', title: 'Unrated', withFit: false),
      ]),
    );
    expect(find.text('Intensive picks'), findsOneWidget);
    expect(find.text('Extensive listening'), findsOneWidget);
    expect(find.text('Set aside for now'), findsOneWidget);
    expect(find.text('Not rated yet'), findsOneWidget);

    // Golden target badge appears on the intensive row.
    expect(find.text('Intensive pick'), findsOneWidget);

    // Group order: intensive header above extensive header above deferred.
    final intensiveY = tester.getTopLeft(find.text('Intensive picks')).dy;
    final extensiveY = tester.getTopLeft(find.text('Extensive listening')).dy;
    final deferredY = tester.getTopLeft(find.text('Set aside for now')).dy;
    final goldenY = tester.getTopLeft(find.text('Golden')).dy;
    final easyY = tester.getTopLeft(find.text('Easy')).dy;
    expect(intensiveY, lessThan(extensiveY));
    expect(extensiveY, lessThan(deferredY));
    expect(goldenY, lessThan(easyY));
  });

  testWidgets('user intent overrides fit-derived grouping', (tester) async {
    await tester.pumpWidget(
      _host([_entry(id: 'golden', title: 'Pinned away', intent: 'defer')]),
    );
    expect(find.text('Set aside for now'), findsOneWidget);
    expect(find.text('Intensive picks'), findsNothing);
  });

  testWidgets('familiar supply toggle moves familiar material', (tester) async {
    final entries = [_entry(id: 'fam', title: 'Familiar', familiar: true)];
    await tester.pumpWidget(_host(entries));
    // Supply on: familiar golden-target relists as extensive with the badge.
    expect(find.text('Extensive listening'), findsOneWidget);
    expect(find.text('Relisten'), findsOneWidget);

    await tester.pumpWidget(_host(entries, familiarSupplyEnabled: false));
    // Supply off: falls back to the fit-derived intensive group, no badge.
    expect(find.text('Intensive picks'), findsOneWidget);
    expect(find.text('Relisten'), findsNothing);
  });

  testWidgets('one-click actions and intent menu reach the callbacks', (
    tester,
  ) async {
    MediaLibraryEntry? extensiveStarted;
    MediaLibraryEntry? intensiveStarted;
    (MediaLibraryEntry, String?)? intentSet;
    await tester.pumpWidget(
      _host(
        [_entry(id: 'm', title: 'Row')],
        onStartExtensive: (entry) => extensiveStarted = entry,
        onStartIntensive: (entry) => intensiveStarted = entry,
        onSetIntent: (entry, intent) => intentSet = (entry, intent),
      ),
    );
    await tester.tap(find.text('Listen'));
    expect(extensiveStarted?.media.id, 'm');
    await tester.tap(find.text('Work on it'));
    expect(intensiveStarted?.media.id, 'm');

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // The CheckedPopupMenuItem's leading checkmark shifts the label off the
    // text's own hit-test center; the selection expectation below verifies
    // the tap regardless.
    await tester.tap(find.text('Set aside'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(intentSet?.$1.media.id, 'm');
    expect(intentSet?.$2, 'defer');
  });

  testWidgets('empty library shows the neutral empty note', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.text('Media you open will appear here.'), findsOneWidget);
  });
}
