import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/widgets/home/personal_library_section.dart';

import 'support/learning_material_fixtures.dart';

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

/// A media-only library row: the revision carries [entry]'s media as an
/// available rendition, so all media capabilities resolve.
PersonalLibraryEntry _mediaRow(
  MediaLibraryEntry entry, {
  String materialId = 'material-1',
}) => PersonalLibraryEntry(
  details: materialDetails(
    materialId: materialId,
    title: entry.media.title,
    documentRenditions: const [],
    mediaRenditions: [
      mediaRendition(
        id: 'asset-1',
        mediaId: entry.media.id,
        kind: MediaRenditionKind.video,
        fingerprint: 'fp',
      ),
    ],
    shape: MaterialShape.video,
  ),
  mediaEntries: [entry],
);

/// A text-only library row: inline document rendition, no media at all.
PersonalLibraryEntry _textRow(String id, String title) => PersonalLibraryEntry(
  details: materialDetails(
    materialId: id,
    revisionId: 'revision-$id',
    title: title,
    documentRenditions: [
      documentRendition(id: 'text-$id', text: 'A readable document.'),
    ],
    shape: MaterialShape.text,
  ),
  mediaEntries: const [],
);

/// A mixed row: both inline text and a bound media rendition.
PersonalLibraryEntry _mixedRow(
  MediaLibraryEntry entry,
  String id, {
  String title = 'Mixed',
}) => PersonalLibraryEntry(
  details: materialDetails(
    materialId: id,
    revisionId: 'revision-$id',
    title: title,
    documentRenditions: [
      documentRendition(id: 'text-$id', text: 'A readable document.'),
    ],
    mediaRenditions: [
      mediaRendition(
        id: 'asset-$id',
        mediaId: entry.media.id,
        kind: MediaRenditionKind.video,
        fingerprint: 'fp',
      ),
    ],
    shape: MaterialShape.mixed,
  ),
  mediaEntries: [entry],
);

Widget _host(
  List<PersonalLibraryEntry> entries, {
  bool familiarSupplyEnabled = true,
  void Function(PersonalLibraryEntry)? onOpenDocument,
  void Function(PersonalLibraryEntry)? onOpenMedia,
  void Function(PersonalLibraryEntry)? onStartExtensive,
  void Function(PersonalLibraryEntry)? onStartIntensive,
  void Function(PersonalLibraryEntry, String?)? onSetIntent,
  void Function(bool)? onToggleFamiliarSupply,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: SingleChildScrollView(
      child: PersonalLibrarySection(
        entries: entries,
        familiarSupplyEnabled: familiarSupplyEnabled,
        onOpenDocument: onOpenDocument ?? (_) {},
        onOpenMedia: onOpenMedia ?? (_) {},
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
        _mediaRow(
          _entry(id: 'easy', title: 'Easy', soundFit: 'comprehensible'),
        ),
        _mediaRow(_entry(id: 'golden', title: 'Golden')),
        _mediaRow(_entry(id: 'hard', title: 'Hard', meaningFit: 'too_hard')),
        _mediaRow(_entry(id: 'unrated', title: 'Unrated', withFit: false)),
        _textRow('text-1', 'Text document'),
      ]),
    );
    expect(find.text('Intensive picks'), findsOneWidget);
    expect(find.text('Extensive listening'), findsOneWidget);
    expect(find.text('Set aside for now'), findsOneWidget);
    expect(find.text('Not rated yet'), findsOneWidget);

    // Text-only rows carry no media facts, so they land in the unsorted group
    // with the unrated media row — never a fabricated media queue.
    expect(find.text('Text document'), findsOneWidget);

    // S2 token provenance. The section used to carry five icon sizes
    // (13/15/18/18/20) and a 7/2 pill inset; every glyph it renders now lands
    // on a `ListenIconSize` step — the check a source scan cannot make, since a
    // size can reach an `Icon` through a variable.
    final steps = <double>{
      ListenIconSize.inline,
      ListenIconSize.control,
      ListenIconSize.chrome,
      ListenIconSize.illustration,
    };
    for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
      if (icon.size != null) expect(steps, contains(icon.size));
    }

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
      _host([
        _mediaRow(_entry(id: 'golden', title: 'Pinned away', intent: 'defer')),
      ]),
    );
    expect(find.text('Set aside for now'), findsOneWidget);
    expect(find.text('Intensive picks'), findsNothing);
  });

  testWidgets('familiar supply toggle moves familiar material', (tester) async {
    final entries = [
      _mediaRow(_entry(id: 'fam', title: 'Familiar', familiar: true)),
    ];
    await tester.pumpWidget(_host(entries));
    // Supply on: familiar golden-target relists as extensive with the badge.
    expect(find.text('Extensive listening'), findsOneWidget);
    expect(find.text('Relisten'), findsOneWidget);

    await tester.pumpWidget(_host(entries, familiarSupplyEnabled: false));
    // Supply off: falls back to the fit-derived intensive group, no badge.
    expect(find.text('Intensive picks'), findsOneWidget);
    expect(find.text('Relisten'), findsNothing);
  });

  testWidgets('media one-click actions and intent menu reach the callbacks', (
    tester,
  ) async {
    PersonalLibraryEntry? extensiveStarted;
    PersonalLibraryEntry? intensiveStarted;
    (PersonalLibraryEntry, String?)? intentSet;
    await tester.pumpWidget(
      _host(
        [_mediaRow(_entry(id: 'm', title: 'Row'))],
        onStartExtensive: (entry) => extensiveStarted = entry,
        onStartIntensive: (entry) => intensiveStarted = entry,
        onSetIntent: (entry, intent) => intentSet = (entry, intent),
      ),
    );
    await tester.tap(find.text('Listen'));
    expect(extensiveStarted?.materialId, 'material-1');
    await tester.tap(find.text('Work on it'));
    expect(intensiveStarted?.materialId, 'material-1');

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // The CheckedPopupMenuItem's leading checkmark shifts the label off the
    // text's own hit-test center; the selection expectation below verifies
    // the tap regardless.
    await tester.tap(find.text('Set aside'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(intentSet?.$1.materialId, 'material-1');
    expect(intentSet?.$2, 'defer');
  });

  testWidgets('a text-only row opens the document and offers no media triage', (
    tester,
  ) async {
    PersonalLibraryEntry? opened;
    await tester.pumpWidget(
      _host([
        _textRow('text-1', 'Text document'),
      ], onOpenDocument: (entry) => opened = entry),
    );

    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Open media'), findsNothing);
    expect(find.text('Listen'), findsNothing);
    expect(find.text('Work on it'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);

    await tester.tap(find.text('Read'));
    expect(opened?.materialId, 'text-1');
  });

  testWidgets(
    'a mixed row shows Read and Listen/Watch and dispatches each intent',
    (tester) async {
      PersonalLibraryEntry? documentOpened;
      PersonalLibraryEntry? mediaOpened;
      await tester.pumpWidget(
        _host(
          [
            _mixedRow(
              _entry(id: 'm', title: 'Mixed'),
              'mixed-1',
              title: 'Mixed material',
            ),
          ],
          onOpenDocument: (entry) => documentOpened = entry,
          onOpenMedia: (entry) => mediaOpened = entry,
        ),
      );

      // Both capabilities are named on the same row; the row never guesses
      // from a bare tap.
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Open media'), findsOneWidget);
      expect(find.text('Listen'), findsOneWidget);

      await tester.tap(find.text('Read'));
      expect(documentOpened?.materialId, 'mixed-1');
      await tester.tap(find.text('Open media'));
      expect(mediaOpened?.materialId, 'mixed-1');
    },
  );

  testWidgets('a mixed row with missing media still reads', (tester) async {
    final missing = MediaLibraryEntry.fromJson({
      'media': {
        'id': 'media-gone',
        'path': '/gone/m.mp4',
        'fingerprint': 'fp',
        'title': 'Gone',
        'kind': 'video',
        'duration': 60000,
        'availability': 'available',
        'created_at_ms': 1,
        'updated_at_ms': 2,
      },
      'primary_track_id': null,
      'fit': null,
      'triage_intent': null,
      'familiar_material': false,
    });
    PersonalLibraryEntry? opened;
    await tester.pumpWidget(
      _host([
        _mixedRow(missing, 'mixed-gone', title: 'Mixed with missing media'),
      ], onOpenDocument: (entry) => opened = entry),
    );

    // The document capability is intact even though the media is gone: Read
    // must never be gated on media availability.
    expect(find.text('Read'), findsOneWidget);
    await tester.tap(find.text('Read'));
    expect(opened?.materialId, 'mixed-gone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty library shows the neutral empty note', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.text('Materials you keep will appear here.'), findsOneWidget);
  });

  testWidgets('the section is titled Personal library', (tester) async {
    await tester.pumpWidget(_host(const []));
    expect(find.text('Personal library'), findsOneWidget);
    expect(find.text('Media library'), findsNothing);
  });
}
