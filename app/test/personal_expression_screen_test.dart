import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/personal_expression_view_model.dart';
import 'package:llplayer_next/data/repositories/personal_expression_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/screens/personal_expression_screen.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/theme/breakpoints.dart';
import 'package:llplayer_next/theme/icon_size.dart';
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

/// A copy of [_asset] with the fields a layout/hygiene test needs to vary.
Map<String, dynamic> _assetWith({
  required String id,
  String language = 'en',
  String? name,
  String? patternText,
  String? sourceText,
}) => {
  ..._asset,
  'id': id,
  'language': language,
  'source': {
    ...(_asset['source'] as Map<String, dynamic>),
    'text': ?sourceText,
  },
  'current_version': {
    ...(_asset['current_version'] as Map<String, dynamic>),
    'pattern_id': id,
    'name': ?name,
    'pattern_text': ?patternText,
  },
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
  List<Map<String, dynamic>>? assets,
}) {
  final versionList =
      versions ?? [_asset['current_version'] as Map<String, dynamic>];
  final assetList = assets ?? [_asset];
  return LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'token',
    transport: (method, path, body) async {
      if (path.startsWith('/v1/personal-expression/patterns?') ||
          path == '/v1/personal-expression/patterns') {
        return (statusCode: 200, body: jsonEncode(assetList));
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

LocalApi _apiWithOneDetailFailure() {
  var versionLoads = 0;
  return LocalApi.withTransport(
    baseUrl: 'http://test',
    token: 'token',
    transport: (method, path, body) async {
      if (path.startsWith('/v1/personal-expression/patterns?') ||
          path == '/v1/personal-expression/patterns') {
        return (statusCode: 200, body: jsonEncode([_asset]));
      }
      if (path.endsWith('/attempts')) {
        return (statusCode: 200, body: jsonEncode(const []));
      }
      if (path.endsWith('/versions')) {
        versionLoads++;
        if (versionLoads == 1) {
          return (statusCode: 503, body: '{"code":"temporarily_unavailable"}');
        }
        return (statusCode: 200, body: jsonEncode([_asset['current_version']]));
      }
      throw StateError('$method $path was not expected');
    },
  );
}

/// The strings under test, read the way the screen reads them.
///
/// Before S6 (#7) this file asserted Chinese literals while pumping an `en`
/// app — which passed only because the screen ignored the locale entirely. An
/// assertion written against `AppLocalizations` cannot pass that way: it moves
/// with the table, and running it under both locales is then free.
late AppLocalizations l;

Future<void> _pumpScreen(
  WidgetTester tester,
  LocalApi api, {
  Locale locale = const Locale('en'),
  Size size = _tallWindow,
}) async {
  l = AppLocalizations(locale);
  _setWindow(tester, size);
  final repository = LocalPersonalExpressionRepository(api);
  final viewModel = PersonalExpressionViewModel(repository, language: 'en');
  addTearDown(viewModel.dispose);
  await tester.pumpWidget(
    MaterialApp(
      // Keyed on the locale so re-pumping with a different one rebuilds from
      // the root. Without it Flutter updates the existing `MaterialApp`
      // element, the `Navigator` keeps whatever route the previous pass pushed,
      // and the second locale is asserted against the first one's screen.
      key: ValueKey(locale),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: PersonalExpressionScreen(
        viewModel: viewModel,
        onOpenPattern: (context, pattern) async {
          final detailViewModel = PersonalExpressionDetailViewModel(
            repository,
            pattern: pattern,
          );
          try {
            return await Navigator.of(
                  context,
                ).push<PersonalExpressionDetailOutcome>(
                  MaterialPageRoute(
                    builder: (_) => PersonalExpressionDetailScreen(
                      viewModel: detailViewModel,
                      pattern: pattern,
                    ),
                  ),
                ) ??
                PersonalExpressionDetailOutcome.closed;
          } finally {
            detailViewModel.dispose();
          }
        },
        language: 'en',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// One usage-history line, assembled from the table the same way `_HistoryRow`
/// assembles it — channel, rung, self-assessment, relative time.
String _historyLine({
  required String channelKey,
  required String rungKey,
  required String assessmentKey,
}) =>
    '${l.text(channelKey)} · ${l.text(rungKey)} · '
    '${l.text(assessmentKey)} · ';

/// Tall enough that every row of the detail page and the writing desk is
/// built.
///
/// Not cosmetic: both are `ListView`s, which build lazily, so an unbuilt row is
/// indistinguishable from a missing one to `find.text`. At the 800×600 default
/// the English copy — longer than the Chinese it replaced — pushed the delete
/// action and the writing desk's lower half out of the viewport, and three
/// assertions started failing for a reason that had nothing to do with them.
const _tallWindow = Size(900, 1600);

/// Sizes the test window, so a layout claim ("the search field is capped at the
/// content column") is made at a width where the uncapped form would be
/// visibly wider — the ~950pt window of the audit screenshot.
void _setWindow(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openWritingDesk(WidgetTester tester) async {
  await tester.tap(find.text('Ended up'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l.text('expressionWriteYourOwn')));
  await tester.pumpAndSettle();
}

/// Han ideographs, for the "no Chinese survives an English interface" check.
final _han = RegExp(r'[一-鿿]');

void main() {
  testWidgets('详情加载失败显示可重试状态，重试后恢复详情', (tester) async {
    await _pumpScreen(tester, _apiWithOneDetailFailure());

    await tester.tap(find.text('Ended up'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal-expression-detail-retry')),
      findsOneWidget,
    );
    expect(find.text(l.text('retry')), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('personal-expression-detail-retry')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('personal-expression-detail-retry')),
      findsNothing,
    );
    expect(find.text(l.text('expressionUsageHistory')), findsOneWidget);
  });

  testWidgets('#7: the screen speaks the interface language, in both '
      'directions', (tester) async {
    // The regression this slice exists for. 我的表达 had 65 Chinese literals
    // and a single `l.text` call, so an `en` learner opened it to a full screen
    // of Chinese and the language setting did nothing at all.
    for (final locale in const [Locale('en'), Locale('zh')]) {
      await _pumpScreen(tester, _api(), locale: locale);

      // The list surface: page title, both AppBar actions, the starter guide.
      for (final key in const [
        'personalExpressions',
        'expressionStarterTitle',
        'expressionStarterBody',
        'expressionStarterCreate',
      ]) {
        expect(
          find.textContaining(l.text(key)),
          findsAtLeastNWidgets(1),
          reason: '$key is missing under $locale',
        );
      }

      // Down into the detail page and the writing desk, which is where most of
      // the welded copy lived.
      await tester.tap(find.text('Ended up'));
      await tester.pumpAndSettle();
      for (final key in const [
        'expressionWriteYourOwn',
        'expressionSpeakUnscripted',
        'expressionUsageHistory',
        'expressionNoUsageYet',
        'expressionDeleteAction',
      ]) {
        expect(
          find.textContaining(l.text(key)),
          findsAtLeastNWidgets(1),
          reason: '$key is missing under $locale',
        );
      }

      await tester.tap(find.text(l.text('expressionWriteYourOwn')));
      await tester.pumpAndSettle();
      for (final key in const [
        'expressionLadderTitle',
        'expressionYourSentence',
        'expressionHowItFelt',
        'expressionSaveAttempt',
        'expressionAssessNeedsWork',
        'expressionAssessExpressed',
      ]) {
        expect(
          find.textContaining(l.text(key)),
          findsAtLeastNWidgets(1),
          reason: '$key is missing under $locale',
        );
      }
    }
  });

  testWidgets('#7: under an English interface no Chinese is left on screen', (
    tester,
  ) async {
    // The direction `cjk_literal_discipline_test.dart` cannot check: that gate
    // reads source, so a key whose `en` value was filled with the Chinese
    // string, or one that fell back to a Chinese literal, passes it and is
    // still wrong here. This reads what renders.
    await _pumpScreen(tester, _api());
    await tester.tap(find.text('Ended up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.text('expressionWriteYourOwn')));
    await tester.pumpAndSettle();

    final chinese = [
      for (final widget in tester.widgetList<Text>(find.byType(Text)))
        if (widget.data case final text?)
          if (_han.hasMatch(text)) text,
    ];
    expect(
      chinese,
      isEmpty,
      reason:
          'Still welded to Chinese, or a `zh` value leaked into the `en` '
          'table:\n${chinese.join('\n')}',
    );
  });

  testWidgets('写作台是页面不是弹窗；梯子四阶月白光比例单调递减；不看模板隐藏模板', (tester) async {
    await _pumpScreen(tester, _api());
    await _openWritingDesk(tester);

    // 弹窗死刑：写作流程不再是 AlertDialog。
    expect(find.byType(AlertDialog), findsNothing);

    // 梯子四阶都在。
    for (final key in const [
      'expressionRungTemplateVisible',
      'expressionRungSlotHints',
      'expressionRungKeywords',
      'expressionRungNoText',
    ]) {
      expect(find.text(l.text(key)), findsOneWidget);
    }

    // 月白光比例随档位单调递减（撤一阶脚手架，月白少一分）。
    final moonFinder = find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox && widget.color == ListenColors.moonWhite,
    );
    final moonFlexes = moonFinder.evaluate().map((element) {
      final expanded = element.findAncestorWidgetOfExactType<Expanded>();
      return expanded!.flex;
    }).toList();
    expect(moonFlexes, [3, 2, 1]);
    for (var i = 0; i < moonFlexes.length - 1; i++) {
      expect(moonFlexes[i] > moonFlexes[i + 1], isTrue);
    }

    // 默认档 template_visible：模板可见。
    expect(find.text('I ended up {result}.'), findsOneWidget);

    // 撤到最底一阶：模板与槽位退场。
    await tester.tap(find.text(l.text('expressionRungNoText')));
    await tester.pumpAndSettle();
    expect(find.text('I ended up {result}.'), findsNothing);
    expect(find.text(l.text('expressionNoTemplateHint')), findsOneWidget);
  });

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

    String used(int count) =>
        l.text('expressionRungUsed').replaceAll('{count}', '$count');

    expect(
      find.text(l.text('expressionRungCurrent')),
      findsOneWidget,
    ); // 当前档 template_visible
    expect(find.text(used(2)), findsOneWidget); // slot_hints
    expect(find.text(used(1)), findsOneWidget); // keywords
    expect(find.text(l.text('expressionRungUntried')), findsOneWidget);
  });

  testWidgets('历史为空则梯子只显当前档，不编造「还没试过」', (tester) async {
    await _pumpScreen(tester, _api());
    await _openWritingDesk(tester);

    expect(find.text(l.text('expressionRungCurrent')), findsOneWidget);
    expect(find.text(l.text('expressionRungUntried')), findsNothing);
    expect(
      find.text(l.text('expressionRungUsed').replaceAll('{count}', '1')),
      findsNothing,
    );
  });

  testWidgets('降档轻提示：上次表达自然→提示更少帮助，可忽略，绝不自动降档', (tester) async {
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
    final hint = l
        .text('expressionDownshiftHint')
        .replaceAll('{rung}', l.text('expressionRungSlotHints'));
    expect(find.text(hint), findsOneWidget);
    // 绝不自动降档：当前仍是 template_visible，模板仍在场。
    expect(find.text('I ended up {result}.'), findsOneWidget);

    // 可忽略：点「知道了」后提示消失。
    await tester.tap(find.text(l.text('expressionDownshiftDismiss')));
    await tester.pumpAndSettle();
    expect(find.text(hint), findsNothing);
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

    await tester.tap(find.text(l.text('expressionDeleteAction')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        l
            .text('expressionDeleteBody')
            .replaceAll('{versions}', '2')
            .replaceAll('{attempts}', '2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('E3 列表卡你上次写的句子上屏 · E4 历史行人话替 raw 枚举', (tester) async {
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
      find.text(
        l
            .text('expressionLastWrote')
            .replaceAll('{text}', 'Last summer I ended up taking a job.'),
      ),
      findsOneWidget,
    );

    // 进入详情看使用历史。
    await tester.tap(find.text('Ended up'));
    await tester.pumpAndSettle();

    // E4：历史行是人话，不直出 raw 枚举。
    expect(
      find.textContaining(
        _historyLine(
          channelKey: 'expressionChannelWritten',
          rungKey: 'expressionRungTemplateVisible',
          assessmentKey: 'expressionAssessPartlyExpressed',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('template_visible'), findsNothing);
    expect(find.textContaining('partly_expressed'), findsNothing);
    expect(find.textContaining('writing'), findsNothing);
  });

  testWidgets('§3.6-1 搜索框与内容列同宽，且同锁在内容列宽内', (tester) async {
    // 宽窗（截图 1 的量级）：未收口时搜索框会是满窗宽，内容列却停在 780。
    await _pumpScreen(tester, _api(), size: const Size(1000, 900));

    final searchWidth = tester.getSize(find.byType(TextField)).width;
    final cardWidth = tester.getSize(find.byType(Card).first).width;

    expect(searchWidth, cardWidth);
    expect(searchWidth, lessThan(1000));
    expect(searchWidth, lessThanOrEqualTo(ListenBreakpoints.contentColumnMax));
    // 两者左缘对齐——同一把尺子量出来的。
    expect(
      tester.getTopLeft(find.byType(TextField)).dx,
      tester.getTopLeft(find.byType(Card).first).dx,
    );
  });

  testWidgets('§3.6-2 AppBar 两个动作有名字：窄窗 tooltip，宽窗文字标签，图标收到 chrome 尺寸', (
    tester,
  ) async {
    await _pumpScreen(tester, _api(), size: const Size(700, 800));

    // 窄窗：纯图标，但名字通过 tooltip（也是读屏播报的那一份）可达。
    expect(find.byTooltip('Export expressions'), findsOneWidget);
    expect(find.byTooltip('New expression'), findsOneWidget);
    expect(find.text('Export expressions'), findsNothing);

    for (final icon in [Icons.download_outlined, Icons.add]) {
      final glyph = tester.widget<Icon>(
        find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon)),
      );
      expect(glyph.size, ListenIconSize.chrome);
    }

    // 长按 tooltip 真的显形（可达性不是只写在代码里）。
    await tester.longPress(find.byTooltip('Export expressions'));
    await tester.pumpAndSettle();
    expect(find.text('Export expressions'), findsOneWidget);
  });

  testWidgets('§3.6-2 宽窗下 AppBar 动作直接显示文字标签', (tester) async {
    await _pumpScreen(tester, _api(), size: const Size(1200, 900));

    expect(find.text('Export expressions'), findsOneWidget);
    expect(find.text('New expression'), findsOneWidget);
  });

  testWidgets('§3.6-3 字幕残留清洗后才上屏：去前导 dash，按学习语言规范化标点', (tester) async {
    await _pumpScreen(
      tester,
      _api(
        assets: [
          _assetWith(
            id: 'pattern-1',
            patternText: '- I need to do something。',
            sourceText: '- I need to wear this, yes.',
          ),
        ],
      ),
    );

    expect(find.text('I need to do something.'), findsOneWidget);
    expect(
      find.text(
        l
            .text('expressionSourceLine')
            .replaceAll('{text}', 'I need to wear this, yes.'),
      ),
      findsOneWidget,
    );
    // 脏形态一处都不许上屏。
    expect(find.textContaining('- I need'), findsNothing);
    expect(find.textContaining('。'), findsNothing);
  });

  testWidgets('§3.6-3 学习语言是中文时，全角标点是正字法，不被 UI 语言带偏', (tester) async {
    await _pumpScreen(
      tester,
      _api(
        assets: [
          _assetWith(
            id: 'pattern-1',
            language: 'zh',
            patternText: '- 我最后还是{结果}。',
            sourceText: '我最后还是去了。',
          ),
        ],
      ),
    );

    expect(find.text('我最后还是{结果}。'), findsOneWidget);
    expect(
      find.text(
        l.text('expressionSourceLine').replaceAll('{text}', '我最后还是去了。'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('§3.6-4 少于 3 条时下方接起步引导，不是留白', (tester) async {
    await _pumpScreen(tester, _api());

    expect(find.text('Save a sentence pattern from subtitles'), findsOneWidget);
    expect(find.text('Write one by hand'), findsOneWidget);
  });

  testWidgets('§3.6-4 满 3 条后引导退场，列表自己就够了', (tester) async {
    await _pumpScreen(
      tester,
      _api(
        assets: [
          _assetWith(id: 'pattern-1', name: 'One'),
          _assetWith(id: 'pattern-2', name: 'Two'),
          _assetWith(id: 'pattern-3', name: 'Three'),
        ],
      ),
    );

    expect(find.text('Three'), findsOneWidget);
    expect(find.text('Save a sentence pattern from subtitles'), findsNothing);
  });

  testWidgets('§3.6-4 一条都没有时，空态自己带入口', (tester) async {
    await _pumpScreen(tester, _api(assets: const []));

    expect(
      find.textContaining('Save a sentence pattern from subtitles'),
      findsOneWidget,
    );
    expect(find.text('Write one by hand'), findsOneWidget);
  });
}
