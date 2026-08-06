import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/content_channel.dart';
import 'package:llplayer_next/widgets/layout/content_channel_availability.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/side_panel_tabs.dart';
import 'package:llplayer_next/widgets/layout/study_menu.dart';

/// The workbench used to answer "how do I work this material" in four places
/// and "what am I looking at" in five. These pin both counts down.
void main() {
  group('SidePanelTabs', () {
    testWidgets('offers two panes, and the transcript is one of them', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          width: 360,
          child: SidePanelTabs(
            selected: SidePanelTab.transcript,
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Five tabs meant four ways to lose the transcript. Two means the only
      // switch is between the text and what the session produced.
      expect(find.byType(InkWell), findsNWidgets(SidePanelTab.values.length));
      expect(SidePanelTab.values.length, 2);
      expect(find.text('原文'), findsOneWidget);
      expect(find.text('本篇'), findsOneWidget);
    });

    testWidgets('both tabs keep their names at a narrow panel width', (
      tester,
    ) async {
      // The five-tab bar dropped its labels below a breakpoint and became a
      // row of unlabelled glyphs. Two labels fit at any width this panel can
      // reach, so the breakpoint and the memory test both go.
      await tester.pumpWidget(
        _harness(
          width: 280,
          child: SidePanelTabs(
            selected: SidePanelTab.notes,
            onSelected: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('原文'), findsOneWidget);
      expect(find.text('本篇'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting a tab reports which one', (tester) async {
      final selected = <SidePanelTab>[];
      await tester.pumpWidget(
        _harness(
          width: 360,
          child: SidePanelTabs(
            selected: SidePanelTab.transcript,
            onSelected: selected.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('side-panel-tab-notes')));
      expect(selected, [SidePanelTab.notes]);
    });
  });

  group('StudyMenu', () {
    testWidgets('holds every way of working the material in one menu', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(width: 200, child: _menu()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      // The five scattered homes — the channel pills, the posture grid, the
      // popup inside one of its cells, and two transport menus — collapse to
      // this list.
      for (final label in const [
        '听',
        '读',
        '说',
        '写',
        '跟读',
        '挖空',
        '语块听写',
        '整句听写',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // Grouped, because working the whole text, drilling one sentence, and
      // producing something are different kinds of work.
      expect(find.text('整篇'), findsOneWidget);
      expect(find.text('单句'), findsOneWidget);
      expect(find.text('产出'), findsOneWidget);
    });

    testWidgets('the channel you are in carries the selection mark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _harness(
          width: 200,
          child: _menu(selectedChannel: ContentChannel.reading),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      // The channels are mutually exclusive surfaces, so exactly one is
      // marked; the intensive modes are things you start and carry no mark.
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      expect(
        find.byIcon(Icons.radio_button_unchecked),
        findsNWidgets(ContentChannel.values.length - 1),
      );
    });

    testWidgets('an unenterable channel says why and refuses the tap', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final chosen = <ContentChannel>[];
      await tester.pumpWidget(
        _harness(
          width: 200,
          child: _menu(
            channelAvailability: const {
              ContentChannel.listening: ContentChannelAvailability.available(),
              ContentChannel.reading: ContentChannelAvailability.available(),
              ContentChannel.speaking: ContentChannelAvailability.unavailable(
                '尚无录音能力',
              ),
              ContentChannel.writing: ContentChannelAvailability.available(),
            },
            onChannelSelected: chosen.add,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      // Listed with the reason, not hidden and not a clickable promise.
      expect(find.text('尚无录音能力'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('content-channel-speaking')));
      await tester.pumpAndSettle();
      expect(chosen, isEmpty);

      await tester.tap(find.byKey(const ValueKey('content-channel-reading')));
      await tester.pumpAndSettle();
      expect(chosen, [ContentChannel.reading]);
    });

    testWidgets('without a sentence the intensive modes rest, channels stay', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _harness(width: 200, child: _menu(hasCue: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      final items = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .where((item) => item.value != null);
      for (final item in items) {
        // The channels answer to the loaded transcript; only the four
        // intensive modes need the sentence being played.
        expect(
          item.enabled,
          item.value!.startsWith('channel-'),
          reason: '${item.value}',
        );
      }
    });

    testWidgets('an unavailable mode says why instead of vanishing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _harness(width: 200, child: _menu(canCloze: false)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      // Still listed — with the reason on its second line.
      expect(find.text('挖空'), findsOneWidget);
      final cloze = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .firstWhere((item) => item.value == 'cloze');
      expect(cloze.enabled, isFalse);
    });
  });
}

Widget _menu({
  bool hasCue = true,
  bool canCloze = true,
  bool canChunkDictation = true,
  ContentChannel selectedChannel = ContentChannel.listening,
  Map<ContentChannel, ContentChannelAvailability>? channelAvailability,
  ValueChanged<ContentChannel>? onChannelSelected,
}) => StudyMenu(
  selectedChannel: selectedChannel,
  channelAvailability:
      channelAvailability ??
      {
        for (final channel in ContentChannel.values)
          channel: const ContentChannelAvailability.available(),
      },
  onChannelSelected: onChannelSelected ?? (_) {},
  hasCue: hasCue,
  canCloze: canCloze,
  canChunkDictation: canChunkDictation,
  onShadow: () {},
  onCloze: () {},
  onChunkDictation: () {},
  onSentenceDictation: () {},
);

Widget _harness({required double width, required Widget child}) => MaterialApp(
  theme: ListenTheme.dark(),
  locale: const Locale('zh'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);
