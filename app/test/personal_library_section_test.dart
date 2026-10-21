import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/widgets/home/personal_library_section.dart';

import 'support/learning_material_fixtures.dart';

MediaLibraryEntry _entry({String id = 'media-1', String title = 'Media 1'}) =>
    MediaLibraryEntry.fromJson({
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
      'fit': null,
      'triage_intent': null,
    });

PersonalLibraryEntry _row(MediaLibraryEntry entry, {String? materialId}) =>
    PersonalLibraryEntry(
      details: materialDetails(
        materialId: materialId ?? entry.media.id,
        title: entry.media.title,
        mediaRenditions: [
          mediaRendition(
            id: 'asset-${entry.media.id}',
            mediaId: entry.media.id,
            kind: MediaRenditionKind.video,
            fingerprint: entry.media.fingerprint,
          ),
        ],
        shape: MaterialShape.video,
      ),
      mediaEntries: [entry],
    );

Widget _host(
  List<PersonalLibraryEntry> entries, {
  void Function(PersonalLibraryEntry)? onOpen,
  void Function(PersonalLibraryEntry)? onStartExtensive,
  void Function(PersonalLibraryEntry)? onStartIntensive,
  void Function(PersonalLibraryEntry, String?)? onSetIntent,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: PersonalLibrarySection(
        entries: entries,
        onOpen: onOpen ?? (_) {},
        onStartExtensive: onStartExtensive ?? (_) {},
        onStartIntensive: onStartIntensive ?? (_) {},
        onSetIntent: onSetIntent ?? (_, _) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('library lists audio and video materials without fit groups', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        _row(_entry(id: 'audio-1', title: 'First episode')),
        _row(_entry(id: 'video-1', title: 'Second lesson')),
      ]),
    );

    expect(find.text('First episode'), findsOneWidget);
    expect(find.text('Second lesson'), findsOneWidget);
    for (final removedGroup in [
      'Intensive picks',
      'Extensive listening',
      'Set aside for now',
      'Not rated yet',
    ]) {
      expect(find.text(removedGroup), findsNothing);
    }
    expect(
      tester.getTopLeft(find.text('First episode')).dy,
      lessThan(tester.getTopLeft(find.text('Second lesson')).dy),
    );
  });

  testWidgets('video extensive and intensive shortcuts reach their callbacks', (
    tester,
  ) async {
    PersonalLibraryEntry? extensiveStarted;
    PersonalLibraryEntry? intensiveStarted;
    (PersonalLibraryEntry, String?)? intentSet;
    final row = _row(_entry(id: 'm', title: 'Row'));
    await tester.pumpWidget(
      _host(
        [row],
        onStartExtensive: (entry) => extensiveStarted = entry,
        onStartIntensive: (entry) => intensiveStarted = entry,
        onSetIntent: (entry, intent) => intentSet = (entry, intent),
      ),
    );

    await tester.tap(find.text('Listen'));
    expect(extensiveStarted?.materialId, row.materialId);
    await tester.tap(find.text('Work on it'));
    expect(intensiveStarted?.materialId, row.materialId);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set aside'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(intentSet?.$1.materialId, row.materialId);
    expect(intentSet?.$2, 'defer');
  });

  testWidgets('opening a media row enters its material workbench', (
    tester,
  ) async {
    PersonalLibraryEntry? opened;
    final row = _row(_entry(title: 'CNN10'));
    await tester.pumpWidget(_host([row], onOpen: (entry) => opened = entry));

    await tester.tap(find.text('CNN10'));

    expect(opened?.materialId, row.materialId);
  });

  testWidgets(
    'video rows keep open and study actions without requesting audio generation',
    (tester) async {
      final row = _row(_entry(id: 'video-1', title: 'Video lesson'));
      PersonalLibraryEntry? opened;
      PersonalLibraryEntry? extensivelyStarted;
      PersonalLibraryEntry? intensified;

      await tester.pumpWidget(
        _host(
          [row],
          onOpen: (entry) => opened = entry,
          onStartExtensive: (entry) => extensivelyStarted = entry,
          onStartIntensive: (entry) => intensified = entry,
        ),
      );

      expect(find.text('Listen'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Work on it'), findsOneWidget);
      expect(find.text('Generate listening'), findsNothing);

      await tester.tap(find.text('Listen'));
      await tester.tap(find.text('Work on it'));
      await tester.tap(find.text('Open'));

      expect(extensivelyStarted?.materialId, row.materialId);
      expect(intensified?.materialId, row.materialId);
      expect(opened?.materialId, row.materialId);
    },
  );

  testWidgets('empty library explains where retained materials appear', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const []));

    expect(find.text('Materials you keep will appear here.'), findsOneWidget);
    expect(find.text('Personal library'), findsOneWidget);
  });
}
