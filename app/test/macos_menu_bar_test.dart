import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_shortcuts.dart';
import 'package:llplayer_next/widgets/app_bar/app_bar_capabilities.dart';
import 'package:llplayer_next/widgets/app_bar/macos_menu_bar.dart';

/// #23: the native menu bar is a presentation surface. These tests pin its
/// three disciplines — availability from [AppBarCapabilities], labels and
/// callbacks from the shortcut table, and the ⌘-only key-equivalent rule
/// that keeps menus from swallowing typing.
void main() {
  Map<String, VoidCallback> allActions([VoidCallback? callback]) => {
    for (final shortcut in playerShortcuts) shortcut.id: callback ?? () {},
  };

  List<PlatformMenu> build({
    AppBarCapabilities capabilities = const AppBarCapabilities.available(),
    Map<String, VoidCallback>? shortcutActions,
    Locale locale = const Locale('zh'),
    VoidCallback? onOpenSettings,
    VoidCallback? onOpenMedia,
  }) => buildMacosMenus(
    l: AppLocalizations(locale),
    capabilities: capabilities,
    shortcutActions: shortcutActions ?? allActions(),
    onOpenSettings: onOpenSettings ?? () {},
    onOpenMedia: onOpenMedia ?? () {},
    onOpenOnline: () {},
    onImportPrimarySubtitle: () {},
    onImportSecondarySubtitle: () {},
    onImportEmbeddedSubtitle: () {},
    onArchiveMedia: () {},
    onOpenSubtitleResources: () {},
    onOpenVocabulary: () {},
    onOpenReview: () {},
    onOpenCoach: () {},
    onOpenPhoneticAnalysisCenter: () {},
  );

  Iterable<PlatformMenuItem> flatten(List<PlatformMenuItem> items) sync* {
    for (final item in items) {
      if (item is PlatformMenu) {
        yield* flatten(item.menus);
      } else if (item is PlatformMenuItemGroup) {
        yield* flatten(item.members);
      } else {
        yield item;
      }
    }
  }

  PlatformMenuItem byLabel(List<PlatformMenu> menus, String label) =>
      flatten(menus).singleWhere((item) => item.label == label);

  test('every label localizes in both locales (no raw keys leak)', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = AppLocalizations(locale);
      final menus = build(locale: locale);
      final labels = [
        ...menus.skip(1).map((menu) => menu.label),
        ...flatten(menus)
            .where((item) => item is! PlatformProvidedMenuItem)
            .map((item) => item.label),
      ];
      for (final label in labels) {
        expect(
          label,
          isNot(matches(RegExp(r'^[a-z][a-zA-Z0-9]+$'))),
          reason: '"$label" looks like an unlocalized key for $locale',
        );
      }
      // Top-level menus carry the localized names.
      expect(menus.map((menu) => menu.label), [
        'LLPlayerNext',
        l.text('menuFile'),
        l.text('menuEdit'),
        l.text('menuPlayback'),
        l.text('menuLearning'),
        l.text('menuWindow'),
        l.text('menuHelp'),
      ]);
    }
  });

  test('every menu key equivalent carries ⌘ (typing safety, #23 决策)', () {
    for (final item in flatten(build())) {
      final shortcut = item.shortcut;
      if (shortcut == null) continue;
      expect(
        (shortcut as SingleActivator).meta,
        isTrue,
        reason: '"${item.label}" 的键位没有 ⌘ — 裸键会在菜单层截获,吞掉文本框输入',
      );
    }
  });

  test('⌘, opens settings and ⌘O/⇧⌘O open media (#23 验收项 1)', () {
    var settings = 0;
    var media = 0;
    final l = AppLocalizations(const Locale('zh'));
    final menus = build(
      onOpenSettings: () => settings++,
      onOpenMedia: () => media++,
    );

    final preferences = byLabel(menus, l.text('menuPreferences'));
    expect(
      preferences.shortcut,
      const SingleActivator(LogicalKeyboardKey.comma, meta: true),
    );
    preferences.onSelected!();
    expect(settings, 1);

    final openMedia = byLabel(menus, l.text('openMedia'));
    expect(
      openMedia.shortcut,
      const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
    );
    openMedia.onSelected!();
    expect(media, 1);

    expect(
      byLabel(menus, l.text('openUrl')).shortcut,
      const SingleActivator(LogicalKeyboardKey.keyO, meta: true, shift: true),
    );
  });

  test('playback items are the shortcut table rows (#25 单一来源)', () {
    var played = 0;
    final l = AppLocalizations(const Locale('zh'));
    final actions = allActions()..['playPause'] = () => played++;
    final menus = build(shortcutActions: actions);

    for (final id in [
      'playPause',
      'previousSentence',
      'nextSentence',
      'loopSentence',
      'toggleSubtitles',
      'toggleFullscreen',
    ]) {
      final labelKey = playerShortcuts.singleWhere((s) => s.id == id).labelKey;
      final item = byLabel(menus, l.text(labelKey));
      expect(item.shortcut, isNull, reason: '$id 是裸键,不得挂菜单键位');
    }
    byLabel(menus, l.text('shortcutPlayPause')).onSelected!();
    expect(played, 1);
  });

  test('availability mirrors AppBarCapabilities (#24 同一判定来源)', () {
    final l = AppLocalizations(const Locale('zh'));

    final noMedia = build(
      capabilities: const AppBarCapabilities(hasMedia: false, coreReady: true),
    );
    for (final label in [
      l.text('menuImportPrimarySubtitle'),
      l.text('menuImportSecondarySubtitle'),
      l.text('importEmbeddedText'),
      l.text('archiveMedia'),
      l.text('shortcutPlayPause'),
      l.text('shortcutToggleFullscreen'),
    ]) {
      expect(
        byLabel(noMedia, label).onSelected,
        isNull,
        reason: '"$label" 无媒体时应禁用',
      );
    }
    // Learning stays open: it needs the core, not a media session.
    expect(byLabel(noMedia, l.text('vocabulary')).onSelected, isNotNull);
    expect(byLabel(noMedia, l.text('openMedia')).onSelected, isNotNull);

    final noCore = build(
      capabilities: const AppBarCapabilities(hasMedia: true, coreReady: false),
    );
    for (final label in [
      l.text('subtitleResources'),
      l.text('vocabulary'),
      l.text('review'),
      l.text('coachDashboard'),
      l.text('phoneticAnalysisCenter'),
    ]) {
      expect(
        byLabel(noCore, label).onSelected,
        isNull,
        reason: '"$label" 核心断连时应禁用',
      );
    }
  });

  test('a missing shortcut action id fails fast', () {
    expect(
      () => build(shortcutActions: allActions()..remove('playPause')),
      throwsA(isA<TypeError>()),
    );
  });

  testWidgets('Edit menu routes to the focused text field via intents', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'bonjour le monde');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: controller, autofocus: true),
        ),
      ),
    );
    await tester.pump();

    final l = AppLocalizations(const Locale('zh'));
    final selectAll = byLabel(build(), l.text('menuSelectAll'));
    expect(
      selectAll.shortcut,
      const SingleActivator(LogicalKeyboardKey.keyA, meta: true),
    );
    selectAll.onSelected!();
    await tester.pump();
    expect(
      controller.selection,
      TextSelection(baseOffset: 0, extentOffset: controller.text.length),
    );
  });

  testWidgets('Edit menu without any focused field is a quiet no-op', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('no field'))),
    );
    final l = AppLocalizations(const Locale('zh'));
    byLabel(build(), l.text('menuPaste')).onSelected!();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
