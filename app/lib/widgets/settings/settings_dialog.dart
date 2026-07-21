import 'dart:async';

import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../services/api_service.dart';
import 'llm_provider_settings.dart';
import 'syntax_capability_settings.dart';

/// Settings dialog content widget. Takes all setting values via constructor
/// and communicates changes back through callbacks.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    this.api,
    this.currentTrackId,
    required this.language,
    required this.themeMode,
    required this.subtitlePreset,
    required this.primaryFontSize,
    required this.primaryFontFamily,
    required this.secondaryFontSize,
    required this.secondaryFontFamily,
    required this.subtitlePositionX,
    required this.subtitlePositionY,
    required this.subtitleBackgroundOpacity,
    required this.transcriptWidth,
    required this.primaryColor,
    required this.secondaryColor,
    required this.transcriptionQuality,
    required this.transcriptionLanguage,
    required this.transcriptionDestination,
    required this.ffmpegPath,
    required this.ffprobePath,
    required this.ytDlpPath,
    required this.openSubtitlesApiKey,
    required this.wordSyncVisible,
    required this.groupingMode,
    required this.senseGroupsAvailable,
    required this.chunkDisplayStyle,
    required this.highlightCurrentChunk,
    required this.chunkHighlightStyle,
    required this.wordHighlightStyle,
    required this.wordAnimationIntensity,
    required this.ruleHintsLevel,
    required this.phonemeRibbonVisible,
    required this.soundPatternRibbonVisible,
    required this.soundPatternDisplayMode,
    required this.phonemeRibbonStyle,
    required this.phoneticAnalysisPreference,
    required this.learningLanguage,
    required this.availableLanguages,
    required this.l1Language,
    required this.onLearningLanguageChanged,
    required this.onL1LanguageChanged,
    required this.onLanguageChanged,
    required this.onThemeModeChanged,
    required this.onSubtitlePresetChanged,
    required this.onPrimaryFontSizeChanged,
    required this.onPrimaryFontFamilyChanged,
    required this.onSecondaryFontSizeChanged,
    required this.onSecondaryFontFamilyChanged,
    required this.onSubtitlePositionXChanged,
    required this.onSubtitlePositionYChanged,
    required this.onSubtitlePositionReset,
    required this.onBackgroundOpacityChanged,
    required this.onTranscriptWidthChanged,
    required this.onPrimaryColorChanged,
    required this.onSecondaryColorChanged,
    required this.onTranscriptionQualityChanged,
    required this.onTranscriptionLanguageChanged,
    required this.onTranscriptionDestinationChanged,
    required this.onWordSyncVisibleChanged,
    required this.onGroupingModeChanged,
    required this.onChunkDisplayStyleChanged,
    required this.onHighlightCurrentChunkChanged,
    required this.onChunkHighlightStyleChanged,
    required this.onWordHighlightStyleChanged,
    required this.onWordAnimationIntensityChanged,
    required this.onRuleHintsLevelChanged,
    required this.onPhonemeRibbonVisibleChanged,
    required this.onSoundPatternRibbonVisibleChanged,
    required this.onSoundPatternDisplayModeChanged,
    required this.onPhonemeRibbonStyleChanged,
    required this.onPhoneticAnalysisPreferenceChanged,
    required this.onSave,
  });

  // Current values
  /// Phase 3.12: when a sidecar is connected, the AI-providers section can
  /// manage vendor-neutral LLM providers. Null keeps that section inert.
  final LocalApi? api;
  final String? currentTrackId;
  final String language;
  final String themeMode;
  final String subtitlePreset;
  final double primaryFontSize;
  final String primaryFontFamily;
  final double secondaryFontSize;
  final String secondaryFontFamily;
  final double subtitlePositionX;
  final double subtitlePositionY;
  final double subtitleBackgroundOpacity;
  final double transcriptWidth;
  final Color primaryColor;
  final Color secondaryColor;
  final String transcriptionQuality;
  final String transcriptionLanguage;
  final String transcriptionDestination;
  final String ffmpegPath;
  final String ffprobePath;
  final String ytDlpPath;
  final String openSubtitlesApiKey;
  final bool wordSyncVisible;
  final String groupingMode;
  final bool senseGroupsAvailable;
  final String chunkDisplayStyle;
  final bool highlightCurrentChunk;
  final String chunkHighlightStyle;
  final String wordHighlightStyle;
  final double wordAnimationIntensity;
  final String ruleHintsLevel;
  final bool phonemeRibbonVisible;
  final bool soundPatternRibbonVisible;
  final String soundPatternDisplayMode;
  final String phonemeRibbonStyle;
  final String phoneticAnalysisPreference;
  final String learningLanguage;
  final List<String> availableLanguages;

  /// The learner's declared L1 (native language); empty string means unset.
  /// Persisted backend-side (Phase 3.9), unlike the local file settings above.
  final String l1Language;

  // Callbacks
  final ValueChanged<String> onLearningLanguageChanged;
  final ValueChanged<String> onL1LanguageChanged;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onThemeModeChanged;
  final ValueChanged<String> onSubtitlePresetChanged;
  final ValueChanged<double> onPrimaryFontSizeChanged;
  final ValueChanged<String> onPrimaryFontFamilyChanged;
  final ValueChanged<double> onSecondaryFontSizeChanged;
  final ValueChanged<String> onSecondaryFontFamilyChanged;
  final ValueChanged<double> onSubtitlePositionXChanged;
  final ValueChanged<double> onSubtitlePositionYChanged;
  final VoidCallback onSubtitlePositionReset;
  final ValueChanged<double> onBackgroundOpacityChanged;
  final ValueChanged<double> onTranscriptWidthChanged;
  final ValueChanged<Color> onPrimaryColorChanged;
  final ValueChanged<Color> onSecondaryColorChanged;
  final ValueChanged<String> onTranscriptionQualityChanged;
  final ValueChanged<String> onTranscriptionLanguageChanged;
  final ValueChanged<String> onTranscriptionDestinationChanged;
  final ValueChanged<bool> onWordSyncVisibleChanged;
  final ValueChanged<String> onGroupingModeChanged;
  final ValueChanged<String> onChunkDisplayStyleChanged;
  final ValueChanged<bool> onHighlightCurrentChunkChanged;
  final ValueChanged<String> onChunkHighlightStyleChanged;
  final ValueChanged<String> onWordHighlightStyleChanged;
  final ValueChanged<double> onWordAnimationIntensityChanged;
  final ValueChanged<String> onRuleHintsLevelChanged;
  final ValueChanged<bool> onPhonemeRibbonVisibleChanged;
  final ValueChanged<bool> onSoundPatternRibbonVisibleChanged;
  final ValueChanged<String> onSoundPatternDisplayModeChanged;
  final ValueChanged<String> onPhonemeRibbonStyleChanged;
  final ValueChanged<String> onPhoneticAnalysisPreferenceChanged;
  final Future<void> Function({
    required String ffmpegPath,
    required String ffprobePath,
    required String ytDlpPath,
    required String openSubtitlesApiKey,
  })
  onSave;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final ScrollController _settingsScrollController = ScrollController();
  final List<GlobalKey> _categoryKeys = List.generate(7, (_) => GlobalKey());
  int _selectedCategory = 2;
  late String language;
  late String themeMode;
  late String subtitlePreset;
  late double primaryFontSize;
  late String primaryFontFamily;
  late double secondaryFontSize;
  late String secondaryFontFamily;
  late double subtitlePositionX;
  late double subtitlePositionY;
  late double subtitleBackgroundOpacity;
  late double transcriptWidth;
  late Color primaryColor;
  late Color secondaryColor;
  late String transcriptionQuality;
  late String transcriptionLanguage;
  late String transcriptionDestination;
  late bool wordSyncVisible;
  late String groupingMode;
  late String chunkDisplayStyle;
  late bool highlightCurrentChunk;
  late String chunkHighlightStyle;
  late String wordHighlightStyle;
  late double wordAnimationIntensity;
  late String ruleHintsLevel;
  late bool phonemeRibbonVisible;
  late bool soundPatternRibbonVisible;
  late String soundPatternDisplayMode;
  late String phonemeRibbonStyle;
  late String phoneticAnalysisPreference;
  late String learningLanguage;
  late String l1Language;

  late final TextEditingController ffmpegController;
  late final TextEditingController ffprobeController;
  late final TextEditingController ytDlpController;
  late final TextEditingController openSubtitlesController;

  @override
  void initState() {
    super.initState();
    _initFromWidget();
  }

  @override
  void didUpdateWidget(covariant SettingsDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    _initFromWidget();
  }

  void _initFromWidget() {
    language = widget.language;
    themeMode = widget.themeMode;
    subtitlePreset = widget.subtitlePreset;
    primaryFontSize = widget.primaryFontSize;
    primaryFontFamily = widget.primaryFontFamily;
    secondaryFontSize = widget.secondaryFontSize;
    secondaryFontFamily = widget.secondaryFontFamily;
    subtitlePositionX = widget.subtitlePositionX;
    subtitlePositionY = widget.subtitlePositionY;
    subtitleBackgroundOpacity = widget.subtitleBackgroundOpacity;
    transcriptWidth = widget.transcriptWidth;
    primaryColor = widget.primaryColor;
    secondaryColor = widget.secondaryColor;
    transcriptionQuality = widget.transcriptionQuality;
    transcriptionLanguage = widget.transcriptionLanguage;
    transcriptionDestination = widget.transcriptionDestination;
    wordSyncVisible = widget.wordSyncVisible;
    groupingMode = widget.groupingMode;
    chunkDisplayStyle = widget.chunkDisplayStyle;
    highlightCurrentChunk = widget.highlightCurrentChunk;
    chunkHighlightStyle = widget.chunkHighlightStyle;
    wordHighlightStyle = widget.wordHighlightStyle;
    wordAnimationIntensity = widget.wordAnimationIntensity;
    ruleHintsLevel = widget.ruleHintsLevel;
    phonemeRibbonVisible = widget.phonemeRibbonVisible;
    soundPatternRibbonVisible = widget.soundPatternRibbonVisible;
    soundPatternDisplayMode = widget.soundPatternDisplayMode;
    phonemeRibbonStyle = widget.phonemeRibbonStyle;
    phoneticAnalysisPreference = widget.phoneticAnalysisPreference;
    learningLanguage = widget.learningLanguage;
    l1Language = widget.l1Language;
    ffmpegController = TextEditingController(text: widget.ffmpegPath);
    ffprobeController = TextEditingController(text: widget.ffprobePath);
    ytDlpController = TextEditingController(text: widget.ytDlpPath);
    openSubtitlesController = TextEditingController(
      text: widget.openSubtitlesApiKey,
    );
  }

  @override
  void dispose() {
    _settingsScrollController.dispose();
    ffmpegController.dispose();
    ffprobeController.dispose();
    ytDlpController.dispose();
    openSubtitlesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: Text(l.text('settings')),
        content: SizedBox(
          width: 820,
          height: 650,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 178,
                child: NavigationRail(
                  extended: true,
                  minExtendedWidth: 178,
                  selectedIndex: _selectedCategory,
                  groupAlignment: -1,
                  onDestinationSelected: (index) {
                    _selectedCategory = index;
                    refresh(() {});
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      final target = _categoryKeys[index].currentContext;
                      if (target == null) return;
                      Scrollable.ensureVisible(
                        target,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: 0,
                      );
                    });
                  },
                  destinations: [
                    NavigationRailDestination(
                      icon: const Icon(Icons.tune),
                      label: Text(l.text('general')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.subtitles_outlined),
                      label: Text(l.text('subtitles')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.school_outlined),
                      label: Text(l.text('learning')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(l.text('resourceSettings')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.build_outlined),
                      label: Text(l.text('externalToolsShort')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.science_outlined),
                      label: Text(l.text('experimental')),
                    ),
                    NavigationRailDestination(
                      icon: const Icon(Icons.smart_toy_outlined),
                      label: Text(l.text('llmProviders')),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              const SizedBox(width: 18),
              Expanded(
                child: ListView(
                  controller: _settingsScrollController,
                  padding: const EdgeInsets.only(right: 8),
                  children: [
                    Text(
                      key: _categoryKeys[2],
                      l.text('learning'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: learningLanguage,
                      decoration: InputDecoration(
                        labelText: l.text('learningLanguage'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'auto',
                          child: Text(l.text('automatic')),
                        ),
                        for (final code in widget.availableLanguages)
                          DropdownMenuItem(
                            value: code,
                            child: Text(_languageLabel(l, code)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        learningLanguage = value;
                        widget.onLearningLanguageChanged(value);
                        refresh(() {});
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: l1Language,
                      decoration: InputDecoration(
                        labelText: l.text('l1Language'),
                        helperText: l.text('l1LanguageHint'),
                        helperMaxLines: 2,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(l.text('l1NotSet')),
                        ),
                        for (final code in widget.availableLanguages)
                          DropdownMenuItem(
                            value: code,
                            child: Text(_languageLabel(l, code)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        l1Language = value;
                        widget.onL1LanguageChanged(value);
                        refresh(() {});
                      },
                    ),
                    const Divider(),
                    Text(
                      l.text('subtitles'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SwitchListTile(
                      value: wordSyncVisible,
                      title: Text(l.text('highlightCurrentWord')),
                      onChanged: (value) {
                        wordSyncVisible = value;
                        widget.onWordSyncVisibleChanged(value);
                        refresh(() {});
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: groupingMode,
                      decoration: InputDecoration(
                        labelText: l.text('groupingMode'),
                        helperText:
                            !widget.senseGroupsAvailable &&
                                (groupingMode == 'semantic' ||
                                    groupingMode == 'compare')
                            ? l.text('senseGroupDataNotReadyHint')
                            : l.text('groupingModeHint'),
                        helperMaxLines: 2,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'off',
                          child: Text(l.text('groupingModeOff')),
                        ),
                        DropdownMenuItem(
                          value: 'prosodic',
                          child: Text(l.text('groupingModeProsodic')),
                        ),
                        DropdownMenuItem(
                          value: 'semantic',
                          child: Text(
                            '${l.text('groupingModeSemantic')} · '
                            '${l.text(widget.senseGroupsAvailable ? 'senseGroupDataAvailable' : 'senseGroupDataNotReady')}',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'compare',
                          child: Text(
                            '${l.text('groupingModeCompare')} · '
                            '${l.text(widget.senseGroupsAvailable ? 'senseGroupDataAvailable' : 'senseGroupDataNotReady')}',
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        groupingMode = value;
                        widget.onGroupingModeChanged(value);
                        refresh(() {});
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: chunkDisplayStyle,
                      decoration: InputDecoration(
                        labelText: l.text('chunkDisplayStyle'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'capsule',
                          child: Text(l.text('chunkDisplayCapsule')),
                        ),
                        DropdownMenuItem(
                          value: 'spacing',
                          child: Text(l.text('chunkDisplaySpacing')),
                        ),
                      ],
                      onChanged: groupingMode != 'off'
                          ? (value) {
                              if (value == null) return;
                              chunkDisplayStyle = value;
                              widget.onChunkDisplayStyleChanged(value);
                              refresh(() {});
                            }
                          : null,
                    ),
                    SwitchListTile(
                      value: highlightCurrentChunk,
                      title: Text(l.text('highlightCurrentChunk')),
                      onChanged: groupingMode != 'off'
                          ? (value) {
                              highlightCurrentChunk = value;
                              widget.onHighlightCurrentChunkChanged(value);
                              refresh(() {});
                            }
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: chunkHighlightStyle,
                      decoration: InputDecoration(
                        labelText: l.text('chunkHighlightStyle'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'background',
                          child: Text(l.text('chunkHighlightBackground')),
                        ),
                        DropdownMenuItem(
                          value: 'bounce',
                          child: Text(l.text('chunkHighlightBounce')),
                        ),
                        DropdownMenuItem(
                          value: 'glow',
                          child: Text(l.text('chunkHighlightGlow')),
                        ),
                      ],
                      onChanged: groupingMode != 'off' && highlightCurrentChunk
                          ? (value) {
                              if (value == null) return;
                              chunkHighlightStyle = value;
                              widget.onChunkHighlightStyleChanged(value);
                              refresh(() {});
                            }
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: wordHighlightStyle,
                      decoration: InputDecoration(
                        labelText: l.text('wordHighlightStyle'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'background',
                          child: Text(l.text('wordHighlightBackground')),
                        ),
                        DropdownMenuItem(
                          value: 'bounce',
                          child: Text(l.text('wordHighlightBounce')),
                        ),
                        DropdownMenuItem(
                          value: 'glow',
                          child: Text(l.text('wordHighlightGlow')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        wordHighlightStyle = value;
                        widget.onWordHighlightStyleChanged(value);
                        refresh(() {});
                      },
                    ),
                    _settingSlider(
                      l.text('wordHighlightIntensity'),
                      wordAnimationIntensity,
                      0,
                      1,
                      (value) {
                        wordAnimationIntensity = value;
                        widget.onWordAnimationIntensityChanged(value);
                      },
                      refresh,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: ruleHintsLevel,
                      decoration: InputDecoration(
                        labelText: l.text('ruleHints'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'off',
                          child: Text(l.text('ruleHintsOff')),
                        ),
                        DropdownMenuItem(
                          value: 'likely',
                          child: Text(l.text('ruleHintsLikely')),
                        ),
                        DropdownMenuItem(
                          value: 'all',
                          child: Text(l.text('ruleHintsAll')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        ruleHintsLevel = value;
                        widget.onRuleHintsLevelChanged(value);
                        refresh(() {});
                      },
                    ),
                    const Divider(),
                    Text(
                      key: _categoryKeys[5],
                      l.text('phoneticAnalysis'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SwitchListTile(
                      value: phonemeRibbonVisible,
                      title: Text(l.text('phonemeRibbonVisible')),
                      onChanged: (value) {
                        phonemeRibbonVisible = value;
                        widget.onPhonemeRibbonVisibleChanged(value);
                        refresh(() {});
                      },
                    ),
                    SwitchListTile(
                      value: soundPatternRibbonVisible,
                      title: Text(l.text('soundPatternRibbonVisible')),
                      onChanged: (value) {
                        soundPatternRibbonVisible = value;
                        widget.onSoundPatternRibbonVisibleChanged(value);
                        refresh(() {});
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: soundPatternDisplayMode,
                      decoration: InputDecoration(
                        labelText: l.text('soundPatternDisplayMode'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'citation',
                          child: Text(l.text('rhythmReferenceCitation')),
                        ),
                        DropdownMenuItem(
                          value: 'connected',
                          child: Text(l.text('rhythmReferenceConnected')),
                        ),
                        DropdownMenuItem(
                          value: 'actual',
                          child: Text(l.text('rhythmReferenceActual')),
                        ),
                      ],
                      onChanged: soundPatternRibbonVisible
                          ? (value) {
                              if (value == null) return;
                              soundPatternDisplayMode = value;
                              widget.onSoundPatternDisplayModeChanged(value);
                              refresh(() {});
                            }
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: phonemeRibbonStyle,
                      decoration: InputDecoration(
                        labelText: l.text('phonemeRibbonStyle'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'window',
                          child: Text(l.text('phonemeRibbonWindow')),
                        ),
                        DropdownMenuItem(
                          value: 'wave',
                          child: Text(l.text('phonemeRibbonWave')),
                        ),
                      ],
                      onChanged: phonemeRibbonVisible
                          ? (value) {
                              if (value == null) return;
                              phonemeRibbonStyle = value;
                              widget.onPhonemeRibbonStyleChanged(value);
                              refresh(() {});
                            }
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: phoneticAnalysisPreference,
                      decoration: InputDecoration(
                        labelText: l.text('phoneticAnalysisPreference'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'on_demand',
                          child: Text(l.text('phoneticOnDemand')),
                        ),
                        DropdownMenuItem(
                          value: 'batch',
                          child: Text(l.text('phoneticBatch')),
                        ),
                        DropdownMenuItem(
                          value: 'off',
                          child: Text(l.text('disabled')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        phoneticAnalysisPreference = value;
                        widget.onPhoneticAnalysisPreferenceChanged(value);
                        refresh(() {});
                      },
                    ),
                    const Divider(),
                    Text(
                      key: _categoryKeys[0],
                      l.text('general'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: language,
                      decoration: InputDecoration(
                        labelText: l.text('language'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text(l.text('system')),
                        ),
                        DropdownMenuItem(
                          value: 'en',
                          child: Text(l.text('english')),
                        ),
                        DropdownMenuItem(
                          value: 'zh',
                          child: Text(l.text('chinese')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        language = value;
                        widget.onLanguageChanged(value);
                        refresh(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: themeMode,
                      decoration: InputDecoration(
                        labelText: l.text('appearance'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'system',
                          child: Text(l.text('appearanceSystem')),
                        ),
                        DropdownMenuItem(
                          value: 'light',
                          child: Text(l.text('appearanceLight')),
                        ),
                        DropdownMenuItem(
                          value: 'dark',
                          child: Text(l.text('appearanceDark')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        themeMode = value;
                        widget.onThemeModeChanged(value);
                        refresh(() {});
                      },
                    ),
                    const Divider(),
                    Text(
                      key: _categoryKeys[1],
                      l.text('subtitles'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: subtitlePreset,
                      decoration: InputDecoration(
                        labelText: l.text('subtitlePreset'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'watching',
                          child: Text(l.text('watching')),
                        ),
                        DropdownMenuItem(
                          value: 'learning',
                          child: Text(l.text('learning')),
                        ),
                        DropdownMenuItem(
                          value: 'compact',
                          child: Text(l.text('compact')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        subtitlePreset = value;
                        widget.onSubtitlePresetChanged(value);
                        refresh(() {});
                      },
                    ),
                    _settingSlider(
                      l.text('subtitleScale'),
                      primaryFontSize,
                      0.5,
                      2,
                      (v) {
                        primaryFontSize = v;
                        widget.onPrimaryFontSizeChanged(v);
                      },
                      refresh,
                    ),
                    _fontSelector(l.text('primaryFont'), primaryFontFamily, (
                      v,
                    ) {
                      primaryFontFamily = v;
                      widget.onPrimaryFontFamilyChanged(v);
                    }, refresh),
                    _settingSlider(
                      l.text('secondaryScale'),
                      secondaryFontSize,
                      0.5,
                      2,
                      (v) {
                        secondaryFontSize = v;
                        widget.onSecondaryFontSizeChanged(v);
                      },
                      refresh,
                    ),
                    _fontSelector(
                      l.text('secondaryFont'),
                      secondaryFontFamily,
                      (v) {
                        secondaryFontFamily = v;
                        widget.onSecondaryFontFamilyChanged(v);
                      },
                      refresh,
                    ),
                    Text(
                      l.text('dragSubtitleHint'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    _settingSlider(
                      l.text('horizontalPosition'),
                      subtitlePositionX,
                      0,
                      1,
                      (v) {
                        subtitlePositionX = v;
                        widget.onSubtitlePositionXChanged(v);
                      },
                      refresh,
                    ),
                    _settingSlider(
                      l.text('verticalPosition'),
                      subtitlePositionY,
                      0,
                      1,
                      (v) {
                        subtitlePositionY = v;
                        widget.onSubtitlePositionYChanged(v);
                      },
                      refresh,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          subtitlePositionX = 0.5;
                          subtitlePositionY = 0.82;
                          widget.onSubtitlePositionReset();
                          refresh(() {});
                        },
                        icon: const Icon(Icons.restart_alt),
                        label: Text(l.text('resetSubtitlePosition')),
                      ),
                    ),
                    _settingSlider(
                      l.text('backgroundOpacity'),
                      subtitleBackgroundOpacity,
                      0,
                      1,
                      (v) {
                        subtitleBackgroundOpacity = v;
                        widget.onBackgroundOpacityChanged(v);
                      },
                      refresh,
                    ),
                    _settingSlider(
                      l.text('transcriptWidth'),
                      transcriptWidth,
                      260,
                      900,
                      (v) {
                        transcriptWidth = v;
                        widget.onTranscriptWidthChanged(v);
                      },
                      refresh,
                    ),
                    const SizedBox(height: 8),
                    Text(l.text('primaryColor')),
                    _colorChoices(primaryColor, (v) {
                      primaryColor = v;
                      widget.onPrimaryColorChanged(v);
                      refresh(() {});
                    }),
                    Text(l.text('secondaryColor')),
                    _colorChoices(secondaryColor, (v) {
                      secondaryColor = v;
                      widget.onSecondaryColorChanged(v);
                      refresh(() {});
                    }),
                    const Divider(),
                    Text(
                      key: _categoryKeys[3],
                      l.text('transcriptionDefaults'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: transcriptionQuality,
                      decoration: InputDecoration(
                        labelText: l.text('preferredQuality'),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'fast', child: Text('Fast')),
                        DropdownMenuItem(
                          value: 'balanced',
                          child: Text('Balanced'),
                        ),
                        DropdownMenuItem(
                          value: 'accurate',
                          child: Text('Accurate'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        transcriptionQuality = value;
                        widget.onTranscriptionQualityChanged(value);
                        refresh(() {});
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: transcriptionLanguage,
                      decoration: InputDecoration(
                        labelText: l.text('transcriptionLanguage'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'auto',
                          child: Text(l.text('automatic')),
                        ),
                        const DropdownMenuItem(
                          value: 'en',
                          child: Text('English'),
                        ),
                        const DropdownMenuItem(value: 'zh', child: Text('中文')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        transcriptionLanguage = value;
                        widget.onTranscriptionLanguageChanged(value);
                        refresh(() {});
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: transcriptionDestination,
                      decoration: InputDecoration(
                        labelText: l.text('defaultDestination'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'primary',
                          child: Text(l.text('primarySubtitle')),
                        ),
                        DropdownMenuItem(
                          value: 'secondary',
                          child: Text(l.text('secondarySubtitle')),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        transcriptionDestination = value;
                        widget.onTranscriptionDestinationChanged(value);
                        refresh(() {});
                      },
                    ),
                    const Divider(),
                    Text(
                      l.text('syntaxCapabilityTitle'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (widget.api != null)
                      SyntaxCapabilitySettings(
                        api: widget.api!,
                        currentTrackId: widget.currentTrackId,
                      )
                    else
                      Text(l.text('syntaxCoreUnavailable')),
                    const Divider(),
                    Text(
                      key: _categoryKeys[4],
                      l.text('externalTools'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextField(
                      controller: ffmpegController,
                      decoration: const InputDecoration(
                        labelText: 'ffmpeg path (auto-detect when empty)',
                      ),
                    ),
                    TextField(
                      controller: ffprobeController,
                      decoration: const InputDecoration(
                        labelText: 'ffprobe path (auto-detect when empty)',
                      ),
                    ),
                    TextField(
                      controller: ytDlpController,
                      decoration: const InputDecoration(
                        labelText: 'yt-dlp path (auto-detect when empty)',
                      ),
                    ),
                    TextField(
                      controller: openSubtitlesController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l.text('openSubtitlesApiKey'),
                      ),
                    ),
                    const Divider(),
                    Text(
                      key: _categoryKeys[6],
                      l.text('llmProviders'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (widget.api != null)
                      LlmProviderSettings(api: widget.api!)
                    else
                      Text(l.text('llmSidecarUnavailable')),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.text('close')),
          ),
          FilledButton(
            onPressed: () {
              widget.onSave(
                ffmpegPath: ffmpegController.text.trim(),
                ffprobePath: ffprobeController.text.trim(),
                ytDlpPath: ytDlpController.text.trim(),
                openSubtitlesApiKey: openSubtitlesController.text.trim(),
              );
              Navigator.pop(context);
            },
            child: Text(l.text('save')),
          ),
        ],
      ),
    );
  }

  Widget _settingSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> update,
    StateSetter refresh,
  ) => Row(
    children: [
      SizedBox(width: 160, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (next) {
            update(next);
            refresh(() {});
          },
        ),
      ),
      SizedBox(width: 56, child: Text(value.toStringAsFixed(1))),
    ],
  );

  Widget _colorChoices(Color selected, ValueChanged<Color> update) => Wrap(
    spacing: 8,
    children: [
      for (final color in const [
        Colors.white,
        Color(0xffb8d8ff),
        Colors.amber,
        Colors.greenAccent,
        Colors.pinkAccent,
      ])
        ChoiceChip(
          selected: selected.toARGB32() == color.toARGB32(),
          label: Container(width: 32, height: 16, color: color),
          onSelected: (_) => update(color),
        ),
    ],
  );

  String _languageLabel(AppLocalizations l, String code) => switch (code) {
    'en' => l.text('english'),
    'zh' => l.text('chinese'),
    'ja' => l.text('japanese'),
    _ => code,
  };

  Widget _fontSelector(
    String label,
    String value,
    ValueChanged<String> update,
    StateSetter refresh,
  ) {
    final l = AppLocalizations.of(context);
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: 'system', child: Text(l.text('systemFont'))),
        DropdownMenuItem(value: 'serif', child: Text(l.text('serifFont'))),
        DropdownMenuItem(
          value: 'monospace',
          child: Text(l.text('monospaceFont')),
        ),
      ],
      onChanged: (next) {
        if (next == null) return;
        update(next);
        refresh(() {});
      },
    );
  }
}
