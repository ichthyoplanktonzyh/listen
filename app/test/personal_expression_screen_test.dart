import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/personal_expression_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';

const _asset = {
  'id': 'pattern-1',
  'language': 'en',
  'source': {
    'kind': 'reading',
    'text': 'I ended up fixing it.',
    'title': 'Real media',
    'media_id': null,
    'media_fingerprint': null,
    'track_id': null,
    'sentence_id': null,
    'semantic_attempt_id': null,
    'start_ms': null,
    'end_ms': null,
    'candidate_ref': null,
  },
  'current_version': {
    'id': 'version-1',
    'pattern_id': 'pattern-1',
    'version': 1,
    'name': 'Ended up',
    'pattern_text': 'I ended up {result}.',
    'slots': [
      {
        'name': 'result',
        'prompt': 'What happened?',
        'example_value': null,
        'required': true,
      },
    ],
    'note': null,
    'system_construction_id': null,
    'created_at_ms': 1,
  },
  'created_at_ms': 1,
  'updated_at_ms': 1,
};

Map<String, dynamic> _attempt({
  required String id,
  required String assistance,
  required String responseText,
  String channel = 'writing',
  String selfAssessment = 'partly_expressed',
  int completedAtMs = 1000,
}) => {
  'id': id,
  'pattern_id': 'pattern-1',
  'pattern_version_id': 'version-1',
  'channel': channel,
  'assistance': assistance,
  'response_text': responseText,
  'raw_transcript': null,
  'recording_asset_id': null,
  'semantic_attempt_id': null,
  'self_assessment': selfAssessment,
  'context_note': null,
  'completed_at_ms': completedAtMs,
};

LocalApi _api({
  List<Map<String, dynamic>> attempts = const [],
  List<Map<String, dynamic>>? versions,
}) {
  final versionList =
      versions ?? [_asset['current_version'] as Map<String, dynamic>];
  return LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'token',
    transport: (method, path, body) async {
      if (path.startsWith('/v1/personal-expression/patterns?') ||
          path == '/v1/personal-expression/patterns') {
        return (statusCode: 200, body: jsonEncode([_asset]));
      }
      if (path.endsWith('/attempts')) {
        if (method == 'POST') {
          return (
            statusCode: 200,
            body: jsonEncode(
              _attempt(id: 'new', assistance: 'no_text', responseText: 'x'),
            ),
          );
        }
        return (statusCode: 200, body: jsonEncode(attempts));
      }
      if (path.endsWith('/versions')) {
        return (statusCode: 200, body: jsonEncode(versionList));
      }
      throw StateError('$method $path was not expected');
    },
  );
}

Future<void> _pumpScreen(WidgetTester tester, LocalApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      home: PersonalExpressionScreen(api: api, language: 'en'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openWritingDesk(WidgetTester tester) async {
  await tester.tap(find.text('Ended up'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('写自己的句子'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '写作台是页面不是弹窗；梯子四阶月白光比例单调递减；不看模板隐藏模板',
    (tester) async {
      await _pumpScreen(tester, _api());
      await _openWritingDesk(tester);

      // 弹窗死刑：写作流程不再是 AlertDialog。
      expect(find.byType(AlertDialog), findsNothing);

      // 梯子四阶都在。
      for (final label in ['看完整模板', '只看槽位', '只看关键词', '不看模板']) {
        expect(find.text(label), findsOneWidget);
      }

      // 月白光比例随档位单调递减（撤一阶脚手架，月白少一分）。
      final moonFinder = find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == ListenColors.moonWhite,
      );
      final moonFlexes = moonFinder
          .evaluate()
          .map((element) {
            final expanded = element
                .findAncestorWidgetOfExactType<Expanded>();
            return expanded!.flex;
          })
          .toList();
      expect(moonFlexes, [3, 2, 1]);
      for (var i = 0; i < moonFlexes.length - 1; i++) {
        expect(moonFlexes[i] > moonFlexes[i + 1], isTrue);
      }

      // 默认档 template_visible：模板可见。
      expect(find.text('I ended up {result}.'), findsOneWidget);

      // 撤到最底一阶：模板与槽位退场。
      await tester.tap(find.text('不看模板'));
      await tester.pumpAndSettle();
      expect(find.text('I ended up {result}.'), findsNothing);
      expect(find.text('模板与槽位提示已隐藏，请直接写出自己的表达。'), findsOneWidget);
    },
  );

  testWidgets('用过 N 次 / 还没试过：既有 attempts 前端聚合', (tester) async {
    await _pumpScreen(
      tester,
      _api(
        attempts: [
          _attempt(id: 'a1', assistance: 'slot_hints', responseText: 's1'),
          _attempt(id: 'a2', assistance: 'slot_hints', responseText: 's2'),
          _attempt(id: 'a3', assistance: 'keywords', responseText: 'k1'),
        ],
      ),
    );
    await _openWritingDesk(tester);

    expect(find.text('你在这'), findsOneWidget); // 当前档 template_visible
    expect(find.text('用过 2 次'), findsOneWidget); // slot_hints
    expect(find.text('用过 1 次'), findsOneWidget); // keywords
    expect(find.text('还没试过'), findsOneWidget); // no_text
  });

  testWidgets('历史为空则梯子只显当前档，不编造「还没试过」', (tester) async {
    await _pumpScreen(tester, _api());
    await _openWritingDesk(tester);

    expect(find.text('你在这'), findsOneWidget);
    expect(find.text('还没试过'), findsNothing);
    expect(find.text('用过 1 次'), findsNothing);
  });

  testWidgets('降档轻提示：上次表达自然→提示更少帮助，可忽略，绝不自动降档', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _api(
        attempts: [
          _attempt(
            id: 'a1',
            assistance: 'template_visible',
            responseText: 'natural',
            selfAssessment: 'expressed',
            completedAtMs: 9000,
          ),
        ],
      ),
    );
    await _openWritingDesk(tester);

    // 提示出现且指向下一阶（更少帮助）。
    expect(
      find.textContaining('要不要试试更少的帮助（只看槽位）'),
      findsOneWidget,
    );
    // 绝不自动降档：当前仍是 template_visible，模板仍在场。
    expect(find.text('I ended up {result}.'), findsOneWidget);

    // 可忽略：点「知道了」后提示消失。
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.textContaining('要不要试试更少的帮助'), findsNothing);
  });

  testWidgets('E1 删除确认：明说牵连 N 个版本 + M 条使用记录', (tester) async {
    await _pumpScreen(
      tester,
      _api(
        attempts: [
          _attempt(id: 'a1', assistance: 'slot_hints', responseText: 's1'),
          _attempt(id: 'a2', assistance: 'keywords', responseText: 'k1'),
        ],
        versions: [
          _asset['current_version'] as Map<String, dynamic>,
          {
            ...(_asset['current_version'] as Map<String, dynamic>),
            'id': 'version-0',
            'version': 0,
          },
        ],
      ),
    );
    await tester.tap(find.text('Ended up'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除这个表达'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('2 个版本'), findsOneWidget);
    expect(find.textContaining('2 条使用记录'), findsOneWidget);
  });

  testWidgets('E3 列表卡你上次写的句子上屏 · E4 历史行人话替 raw 枚举', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      _api(
        attempts: [
          _attempt(
            id: 'a1',
            assistance: 'template_visible',
            responseText: 'Last summer I ended up taking a job.',
          ),
        ],
      ),
    );

    // E3：列表卡呈现最近一次你写的句子。
    expect(
      find.textContaining('↳ 你上次写：Last summer I ended up'),
      findsOneWidget,
    );

    // 进入详情看使用历史。
    await tester.tap(find.text('Ended up'));
    await tester.pumpAndSettle();

    // E4：历史行是人话，不直出 raw 枚举。
    expect(find.textContaining('书面 · 看完整模板 · 基本表达出来'), findsOneWidget);
    expect(find.textContaining('template_visible'), findsNothing);
    expect(find.textContaining('partly_expressed'), findsNothing);
  });
}
