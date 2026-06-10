import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';

void main() {
  testWidgets('ASR desktop actions are localized in simplified Chinese', (
    tester,
  ) async {
    const localization = AppLocalizations(Locale('zh'));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [Text('生成字幕'), Text('ASR 模型与任务'), Text('转录默认设置')],
          ),
        ),
      ),
    );
    expect(localization.text('generateSubtitles'), '生成字幕');
    expect(find.text(localization.text('transcriptionCenter')), findsOneWidget);
    expect(
      find.text(localization.text('transcriptionDefaults')),
      findsOneWidget,
    );
  });
}
