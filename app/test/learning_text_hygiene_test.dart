import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/utils/learning_text_hygiene.dart';

void main() {
  group('前导字幕标记', () {
    test('去掉 SRT 的说话人短横', () {
      expect(
        cleanLearningText('- I need to wear this, yes.', language: 'en'),
        'I need to wear this, yes.',
      );
    });

    test('多重前导符（破折号 + 短横 + 项目符）一并去掉', () {
      expect(
        cleanLearningText('— - • I need to do something.', language: 'en'),
        'I need to do something.',
      );
    });

    test('句中的连字符与减号不动', () {
      expect(
        cleanLearningText('It is a well-known trade-off.', language: 'en'),
        'It is a well-known trade-off.',
      );
    });

    test('整行只有短横时保留原样，不悄悄抹成空行', () {
      expect(cleanLearningText('---', language: 'en'), '---');
    });

    test('空串与纯空白归一为空串', () {
      expect(cleanLearningText('', language: 'en'), '');
      expect(cleanLearningText('   \n ', language: 'en'), '');
    });
  });

  group('标点按学习语言规范化', () {
    test('英文学习语言：全角句号变半角', () {
      expect(
        cleanLearningText('- I need to do something。', language: 'en'),
        'I need to do something.',
      );
    });

    test('英文学习语言：全角逗号/问号补回英文的词间空格', () {
      expect(cleanLearningText('Wait，what？', language: 'en'), 'Wait, what?');
    });

    test('英文学习语言：全角标点前的空隙收掉', () {
      expect(
        cleanLearningText('I am done 。 Yes', language: 'en'),
        'I am done. Yes',
      );
    });

    test('英文学习语言：括号与全角空格', () {
      expect(
        cleanLearningText('He said（quietly）it works', language: 'en'),
        'He said (quietly) it works',
      );
      expect(cleanLearningText('one　two', language: 'en'), 'one two');
    });

    test('中文学习语言：全角标点是正字法，不动', () {
      expect(cleanLearningText('我需要做点什么。', language: 'zh'), '我需要做点什么。');
      expect(cleanLearningText('等等，什么？', language: 'zh-Hans'), '等等，什么？');
    });

    test('中文学习语言：仍然去前导短横，但标点不动', () {
      expect(cleanLearningText('- 我需要做点什么。', language: 'zh_CN'), '我需要做点什么。');
    });

    test('日文学习语言同样保留全角标点', () {
      expect(cleanLearningText('これで大丈夫。', language: 'ja-JP'), 'これで大丈夫。');
    });

    test('韩文按 ASCII 标点排版，全角句号视作输入法残留', () {
      expect(usesFullwidthPunctuation('ko'), isFalse);
      expect(usesFullwidthPunctuation('zh-Hant'), isTrue);
    });

    test('英文引号（弯引号）是正常英文排版，不改写', () {
      expect(
        cleanLearningText('I don’t “know” yet.', language: 'en'),
        'I don’t “know” yet.',
      );
    });

    test('模板槽位的花括号不受影响', () {
      expect(
        cleanLearningText('- I ended up {result}。', language: 'en'),
        'I ended up {result}.',
      );
    });
  });

  group('幂等与无害', () {
    test('已经干净的英文原样返回', () {
      const clean = 'I ended up fixing it.';
      expect(cleanLearningText(clean, language: 'en'), clean);
    });

    test('清洗两次与一次结果相同', () {
      const dirty = '— - I need to do something。 And then，this？';
      final once = cleanLearningText(dirty, language: 'en');
      expect(cleanLearningText(once, language: 'en'), once);
    });

    test('相邻标点之间不插入多余空格', () {
      expect(cleanLearningText('Really？！', language: 'en'), 'Really?!');
    });
  });
}
