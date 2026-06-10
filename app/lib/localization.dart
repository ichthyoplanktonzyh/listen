import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

final appLanguage = ValueNotifier<String>('system');

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('zh')];

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      AppLocalizations(
        Localizations.maybeLocaleOf(context) ?? const Locale('en'),
      );

  String text(String key) =>
      (_values[locale.languageCode] ?? _values['en']!)[key] ??
      _values['en']![key] ??
      key;

  String status(String? value) => text(value ?? 'clear');
  String diagnosis(String kind) => text('diagnosis_$kind');

  static const delegate = _AppLocalizationsDelegate();

  static const _values = <String, Map<String, String>>{
    'en': {
      'settings': 'Settings',
      'language': 'Language',
      'system': 'Follow system',
      'english': 'English',
      'chinese': '简体中文',
      'subtitles': 'Subtitles',
      'subtitlePreset': 'Subtitle preset',
      'watching': 'Watching',
      'learning': 'Learning',
      'compact': 'Compact',
      'subtitleScale': 'Subtitle scale',
      'secondaryScale': 'Secondary scale',
      'verticalPosition': 'Vertical position',
      'backgroundOpacity': 'Background opacity',
      'transcriptWidth': 'Transcript width',
      'primaryColor': 'Primary color',
      'secondaryColor': 'Secondary color',
      'externalTools': 'Optional external tools',
      'close': 'Close',
      'save': 'Save',
      'vocabulary': 'Vocabulary',
      'openMedia': 'Open media',
      'openUrl': 'Open URL',
      'primarySubtitle': 'Primary subtitle',
      'secondarySubtitle': 'Secondary subtitle',
      'transcript': 'Transcript',
      'wordLearning': 'Word learning',
      'diagnosis': 'Diagnosis',
      'noWordSelected': 'Click a subtitle word to open its learning details.',
      'dictionary': 'Dictionary',
      'noDictionary': 'No dictionary result',
      'userDefinition': 'Your definition',
      'personalNote': 'Personal note',
      'sources': 'Sources',
      'statusHistory': 'Status history',
      'currentStatus': 'Current status',
      'clear': 'Clear',
      'unknown_meaning': 'Unknown meaning',
      'known_not_recognized': 'Known, not recognized',
      'known_recognized': 'Known and recognized',
      'apply': 'Apply',
      'heard': 'This sentence: heard',
      'notHeard': 'This sentence: not heard',
      'importWordList': 'Import word list',
      'importAssets': 'Import vocabulary assets',
      'exportAssets': 'Export vocabulary assets',
      'overwriteExisting': 'Overwrite existing classified words',
      'previewImport': 'Import preview',
      'import': 'Import',
      'noWords': 'No words in this book',
      'searchVocabulary': 'Search vocabulary',
      'vocabularyBooks': 'Vocabulary books',
      'loopSentence': 'Loop sentence',
      'wordStyles': 'Word styles',
      'secondary': 'Secondary',
      'currentSentenceDiagnosis': 'Current sentence diagnosis',
      'providerUnavailable': 'Provider unavailable',
      'noSourceSnapshot': 'No source snapshot',
      'encountered': 'encountered',
      'times': 'times',
      'openOnlineTitle': 'Open online media with yt-dlp',
      'pageUrl': 'Page URL',
      'cancel': 'Cancel',
      'resolvePlay': 'Resolve and play',
      'importEmbeddedText': 'Import embedded text subtitle',
      'usePrimary': 'Use as primary',
      'useSecondary': 'Use as secondary',
      'exportLogs': 'Export logs',
      'archiveMedia': 'Archive current media',
      'openVideoAudio': 'Open video or audio',
      'importSubtitleHint': 'Import SRT or WebVTT subtitles',
      'previousSentence': 'Previous sentence',
      'nextSentence': 'Next sentence',
      'restartMedia': 'Restart media',
      'playPause': 'Play / pause',
      'stop': 'Stop',
      'stopSourceLoop': 'Stop source loop',
      'audioTrack': 'Audio track',
      'embeddedSubtitles': 'Embedded subtitles',
      'primaryOffset': 'Primary offset',
      'secondaryOffset': 'Secondary offset',
      'diagnosis_meaning_barrier':
          'Unknown vocabulary may block understanding.',
      'diagnosis_recognition_barrier':
          'Known vocabulary was not recognized in this sentence.',
      'diagnosis_insufficient_information':
          'Classify the remaining words before drawing a conclusion.',
      'diagnosis_other_factors':
          'Vocabulary does not fully explain the listening difficulty.',
    },
    'zh': {
      'settings': '设置',
      'language': '界面语言',
      'system': '跟随系统',
      'english': 'English',
      'chinese': '简体中文',
      'subtitles': '字幕',
      'subtitlePreset': '字幕预设',
      'watching': '观影模式',
      'learning': '学习模式',
      'compact': '紧凑模式',
      'subtitleScale': '主字幕缩放',
      'secondaryScale': '副字幕缩放',
      'verticalPosition': '垂直位置',
      'backgroundOpacity': '背景透明度',
      'transcriptWidth': '文稿宽度',
      'primaryColor': '主字幕颜色',
      'secondaryColor': '副字幕颜色',
      'externalTools': '可选外部工具',
      'close': '关闭',
      'save': '保存',
      'vocabulary': '词汇本',
      'openMedia': '打开媒体',
      'openUrl': '打开网址',
      'primarySubtitle': '主字幕',
      'secondarySubtitle': '副字幕',
      'transcript': '字幕文稿',
      'wordLearning': '词汇学习',
      'diagnosis': '句子诊断',
      'noWordSelected': '点击字幕单词以打开学习详情。',
      'dictionary': '词典',
      'noDictionary': '暂无词典结果',
      'userDefinition': '自定义释义',
      'personalNote': '个人笔记',
      'sources': '来源原句',
      'statusHistory': '状态历史',
      'currentStatus': '当前状态',
      'clear': '清除状态',
      'unknown_meaning': '不认识',
      'known_not_recognized': '认识但听不出',
      'known_recognized': '已掌握',
      'apply': '应用',
      'heard': '本句：听出来了',
      'notHeard': '本句：没有听出',
      'importWordList': '导入已有词表',
      'importAssets': '导入词汇资产',
      'exportAssets': '导出词汇资产',
      'overwriteExisting': '覆盖已有状态',
      'previewImport': '导入预览',
      'import': '导入',
      'noWords': '该词汇本暂无词汇',
      'searchVocabulary': '搜索词汇',
      'vocabularyBooks': '动态词汇本',
      'loopSentence': '循环当前句',
      'wordStyles': '词汇状态样式',
      'secondary': '副字幕',
      'currentSentenceDiagnosis': '当前句诊断',
      'providerUnavailable': '词典来源不可用',
      'noSourceSnapshot': '暂无来源原句',
      'encountered': '遇见',
      'times': '次',
      'openOnlineTitle': '使用 yt-dlp 打开在线媒体',
      'pageUrl': '页面网址',
      'cancel': '取消',
      'resolvePlay': '解析并播放',
      'importEmbeddedText': '导入内嵌文本字幕',
      'usePrimary': '作为主字幕',
      'useSecondary': '作为副字幕',
      'exportLogs': '导出日志',
      'archiveMedia': '归档当前媒体',
      'openVideoAudio': '打开视频或音频',
      'importSubtitleHint': '导入 SRT 或 WebVTT 字幕',
      'previousSentence': '上一句',
      'nextSentence': '下一句',
      'restartMedia': '重新播放媒体',
      'playPause': '播放 / 暂停',
      'stop': '停止',
      'stopSourceLoop': '停止来源循环',
      'audioTrack': '音轨',
      'embeddedSubtitles': '内嵌字幕',
      'primaryOffset': '主字幕偏移',
      'secondaryOffset': '副字幕偏移',
      'diagnosis_meaning_barrier': '不认识的词汇可能阻碍理解。',
      'diagnosis_recognition_barrier': '已认识的词汇在本句中没有被听出。',
      'diagnosis_insufficient_information': '请先判断剩余词汇，再形成结论。',
      'diagnosis_other_factors': '词汇状态不能完全解释当前听力困难。',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (value) => value.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
