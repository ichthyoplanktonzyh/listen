import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/content_channel.dart';
import 'package:llplayer_next/models/workbench_study_mode.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/content_channel_availability.dart';
import 'package:llplayer_next/widgets/layout/side_panel_tabs.dart';
import 'package:llplayer_next/widgets/layout/study_menu.dart';

void main() {
  group('SidePanelTabs', () {
    testWidgets('offers transcript and notes panes', (tester) async {
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

      expect(find.byType(InkWell), findsNWidgets(SidePanelTab.values.length));
      expect(SidePanelTab.values.length, 2);
      expect(find.text('原文'), findsOneWidget);
      expect(find.text('本篇'), findsOneWidget);
    });

    testWidgets('both pane names remain visible at narrow widths', (
      tester,
    ) async {
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

    testWidgets('selecting a pane reports it to the shell', (tester) async {
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
    testWidgets('offers channel surfaces, listening displays and exercises', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(width: 200, child: _menu()));
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      for (final label in const ['边听边看文稿', '盲听', '挖空', '语块听写', '整句听写']) {
        expect(find.text(label), findsOneWidget);
      }
      for (final label in const ['读', '说', '写', '跟读']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('choosing a listening display reports the selected mode', (
      tester,
    ) async {
      final selected = <WorkbenchStudyMode>[];
      await tester.pumpWidget(
        _harness(width: 200, child: _menu(onModeSelected: selected.add)),
      );
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('study-mode-blindListening')));

      expect(selected, [WorkbenchStudyMode.blindListening]);
    });

    testWidgets('sentence exercises rest until a subtitle cue is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(width: 200, child: _menu(hasCue: false)),
      );
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      final items = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .where((item) => item.value != null)
          .toList();
      for (final value in const ['cloze', 'chunk', 'sentence']) {
        expect(
          items.singleWhere((item) => item.value == value).enabled,
          isFalse,
        );
      }
      expect(
        items
            .where((item) => item.value!.startsWith('mode-'))
            .every((item) => item.enabled),
        isTrue,
      );
    });

    testWidgets('unavailable cloze names why it is disabled', (tester) async {
      await tester.pumpWidget(
        _harness(width: 200, child: _menu(canCloze: false)),
      );
      await tester.tap(find.byKey(const Key('study-menu')));
      await tester.pumpAndSettle();

      expect(find.text('挖空'), findsOneWidget);
      final cloze = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .singleWhere((item) => item.value == 'cloze');
      expect(cloze.enabled, isFalse);
      expect(find.text('挖空需要词级时间轴。'), findsOneWidget);
    });
  });
}

Widget _menu({
  bool hasCue = true,
  bool canCloze = true,
  bool canChunkDictation = true,
  WorkbenchStudyMode selectedMode = WorkbenchStudyMode.normal,
  ValueChanged<WorkbenchStudyMode>? onModeSelected,
}) => StudyMenu(
  selectedChannel: ContentChannel.listening,
  channelAvailability: {
    for (final channel in ContentChannel.values)
      channel: const ContentChannelAvailability.available(),
  },
  onChannelSelected: (_) {},
  selectedMode: selectedMode,
  onModeSelected: onModeSelected ?? (_) {},
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
