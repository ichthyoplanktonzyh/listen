import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/posture_actions.dart';
import 'package:llplayer_next/widgets/layout/side_panel_tabs.dart';

const _cells = [
  Key('posture-understand'),
  Key('posture-test'),
  Key('posture-shadow'),
  Key('posture-read'),
];

void main() {
  group('PostureActions', () {
    testWidgets('lays the four postures out as a 2×2 grid', (tester) async {
      await tester.pumpWidget(_grid(width: 520));
      await tester.pumpAndSettle();

      final rects = {
        for (final key in _cells) key: tester.getRect(find.byKey(key)),
      };

      // Row one and row two, two cells each — never the 3+1 the old Wrap
      // produced (§3.7 item 3).
      expect(rects[_cells[0]]!.top, closeTo(rects[_cells[1]]!.top, 0.5));
      expect(rects[_cells[2]]!.top, closeTo(rects[_cells[3]]!.top, 0.5));
      expect(rects[_cells[2]]!.top, greaterThan(rects[_cells[0]]!.bottom));

      // Equal siblings: same width in each column pair, same height overall.
      expect(rects[_cells[0]]!.width, closeTo(rects[_cells[1]]!.width, 0.5));
      expect(rects[_cells[2]]!.width, closeTo(rects[_cells[3]]!.width, 0.5));
      for (final key in _cells.skip(1)) {
        expect(rects[key]!.height, closeTo(rects[_cells[0]]!.height, 0.5));
      }
    });

    testWidgets('keeps the 2×2 grid at a narrow panel width', (tester) async {
      // The width that used to break the row into 3+1.
      await tester.pumpWidget(_grid(width: 360));
      await tester.pumpAndSettle();

      final first = tester.getRect(find.byKey(_cells[0]));
      final second = tester.getRect(find.byKey(_cells[1]));
      final third = tester.getRect(find.byKey(_cells[2]));

      expect(second.top, closeTo(first.top, 0.5));
      expect(third.top, greaterThan(first.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('each cell names an action and says what it does', (
      tester,
    ) async {
      await tester.pumpWidget(_grid(width: 520));
      await tester.pumpAndSettle();

      // Action names, not four interchangeable questions.
      expect(find.text('拆解这句'), findsOneWidget);
      expect(find.text('测一下'), findsOneWidget);
      expect(find.text('跟读'), findsOneWidget);
      expect(find.text('通读全文'), findsOneWidget);

      // And one line each saying what happens — this is what told nobody
      // apart the shadow and read postures before.
      expect(find.text('跟着原声说一遍并录下来'), findsOneWidget);
      expect(find.text('离开听力姿态，整篇读一遍'), findsOneWidget);
    });

    testWidgets('without a current sentence three postures rest, read stays', (
      tester,
    ) async {
      var read = 0;
      var diagnosed = 0;
      await tester.pumpWidget(
        _grid(
          width: 520,
          hasCue: false,
          onRead: () => read += 1,
          onDiagnose: () => diagnosed += 1,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(_cells[0]));
      await tester.tap(find.byKey(_cells[3]));
      await tester.pumpAndSettle();

      expect(diagnosed, 0);
      // Reading needs a transcript, not a current sentence.
      expect(read, 1);
      // The grid keeps its shape either way.
      expect(find.byType(PostureCell), findsNWidgets(4));
    });
  });

  group('SidePanelTabs', () {
    testWidgets('shows text labels at and above the label breakpoint', (
      tester,
    ) async {
      await tester.pumpWidget(
        _tabs(width: ListenBreakpoints.sidePanelTabLabels),
      );
      await tester.pumpAndSettle();

      for (final label in ['文稿', '资源', '词', '诊断', '收件箱']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('drops to icons only below the breakpoint', (tester) async {
      await tester.pumpWidget(
        _tabs(width: ListenBreakpoints.sidePanelTabLabels - 1),
      );
      await tester.pumpAndSettle();

      expect(find.text('文稿'), findsNothing);
      // The name stays reachable through the tooltip at every width.
      expect(
        tester
            .widgetList<Tooltip>(find.byType(Tooltip))
            .map((tooltip) => tooltip.message),
        contains('文稿'),
      );
    });
  });
}

Widget _grid({
  required double width,
  bool hasCue = true,
  VoidCallback? onRead,
  VoidCallback? onDiagnose,
}) => _harness(
  width: width,
  child: PostureActions(
    hasCue: hasCue,
    canCloze: true,
    canChunkDictation: true,
    canRead: true,
    onDiagnose: onDiagnose ?? () {},
    onCloze: () {},
    onChunkDictation: () {},
    onSentenceDictation: () {},
    onShadow: () {},
    onRead: onRead ?? () {},
  ),
);

Widget _tabs({required double width}) => _harness(
  width: width,
  child: SidePanelTabs(
    destinations: const [
      (icon: Icons.subtitles_outlined, label: '文稿'),
      (icon: Icons.inventory_2_outlined, label: '资源'),
      (icon: Icons.menu_book_outlined, label: '词'),
      (icon: Icons.analytics_outlined, label: '诊断'),
      (icon: Icons.inbox_outlined, label: '收件箱'),
    ],
    selectedIndex: 0,
    onSelected: (_) {},
  ),
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
    body: Center(child: SizedBox(width: width, child: child)),
  ),
);
