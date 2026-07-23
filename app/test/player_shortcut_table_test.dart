import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/player_shortcuts.dart';
import 'package:llplayer_next/widgets/player/player_global_shortcuts.dart';

/// #25: the shortcut table is the single source of truth — these tests pin
/// its invariants, the owner-approved key allocation, and the wiring builder.
void main() {
  String activatorSignature(ShortcutActivator activator) {
    if (activator is CharacterActivator) return 'char:${activator.character}';
    final single = activator as SingleActivator;
    return [
      single.trigger.keyId,
      single.control,
      single.shift,
      single.alt,
      single.meta,
    ].join('|');
  }

  Map<String, VoidCallback> allActions([VoidCallback? callback]) => {
    for (final shortcut in playerShortcuts) shortcut.id: callback ?? () {},
  };

  test('ids and key combos are unique', () {
    final ids = playerShortcuts.map((s) => s.id).toList();
    expect(ids.toSet().length, ids.length);

    final combos = playerShortcuts
        .map((s) => activatorSignature(s.activator))
        .toList();
    expect(combos.toSet().length, combos.length, reason: '键位冲突: $combos');
  });

  test('every label localizes in both locales', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = AppLocalizations(locale);
      for (final shortcut in playerShortcuts) {
        expect(
          l.text(shortcut.labelKey),
          isNot(shortcut.labelKey),
          reason: '${shortcut.labelKey} missing for $locale',
        );
      }
      for (final category in PlayerShortcutCategory.values) {
        expect(l.text(category.labelKey), isNot(category.labelKey));
      }
    }
  });

  test('the owner-approved allocation holds (#25 决策)', () {
    PlayerShortcut byId(String id) =>
        playerShortcuts.singleWhere((s) => s.id == id);

    // ←/→ went back to seek; sentence navigation moved to ⌥←/⌥→.
    expect(
      byId('seekBack').activator,
      const SingleActivator(LogicalKeyboardKey.arrowLeft),
    );
    expect(
      byId('previousSentence').activator,
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
    );
    expect(
      byId('nextSentence').activator,
      const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true),
    );
    // M mute, ↑/↓ volume, [ ] speed.
    expect(
      byId('toggleMute').activator,
      const SingleActivator(LogicalKeyboardKey.keyM),
    );
    expect(
      byId('volumeUp').activator,
      const SingleActivator(LogicalKeyboardKey.arrowUp),
    );
    expect(
      byId('speedUp').activator,
      const SingleActivator(LogicalKeyboardKey.bracketRight),
    );
    // F/Esc fullscreen (#25-A: 全屏沉浸态随本表落地).
    expect(
      byId('toggleFullscreen').activator,
      const SingleActivator(LogicalKeyboardKey.keyF),
    );
    expect(
      byId('exitFullscreen').activator,
      const SingleActivator(LogicalKeyboardKey.escape),
    );
    // Only the three bare digits sit behind the settings toggle.
    expect(playerShortcuts.where((s) => s.isMarkKey).map((s) => s.id).toSet(), {
      'markUnknown',
      'markKnownNotRecognized',
      'markKnownRecognized',
    });
  });

  test('captions render macOS-style', () {
    PlayerShortcut byId(String id) =>
        playerShortcuts.singleWhere((s) => s.id == id);
    expect(shortcutCaption(byId('playPause').activator), 'Space');
    expect(shortcutCaption(byId('seekBack').activator), '←');
    expect(shortcutCaption(byId('previousSentence').activator), '⌥ ←');
    expect(shortcutCaption(byId('toggleExtensiveListening').activator), '⇧ I');
    expect(shortcutCaption(byId('speedDown').activator), '[');
    expect(shortcutCaption(byId('toggleFullscreen').activator), 'F');
    expect(shortcutCaption(byId('exitFullscreen').activator), 'Esc');
    expect(shortcutCaption(byId('showCheatSheet').activator), '?');
  });

  test('builder covers the whole table and honors the mark-keys toggle', () {
    final all = buildPlayerShortcutBindings(
      actions: allActions(),
      markKeysEnabled: true,
    );
    expect(all.length, playerShortcuts.length);

    final trimmed = buildPlayerShortcutBindings(
      actions: allActions(),
      markKeysEnabled: false,
    );
    expect(trimmed.length, playerShortcuts.length - 3);
    expect(
      trimmed.containsKey(const SingleActivator(LogicalKeyboardKey.digit1)),
      isFalse,
    );
  });

  test('a missing or unknown action id fails fast in debug', () {
    final incomplete = allActions()..remove('playPause');
    expect(
      () => buildPlayerShortcutBindings(
        actions: incomplete,
        markKeysEnabled: true,
      ),
      throwsFlutterError,
    );
    final extra = allActions()..['madeUp'] = () {};
    expect(
      () => buildPlayerShortcutBindings(actions: extra, markKeysEnabled: true),
      throwsFlutterError,
    );
  });

  test('main.dart no longer hard-codes key bindings', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(
      source.contains('SingleActivator('),
      isFalse,
      reason: '键位只能活在 player_shortcuts.dart 的表里',
    );
    expect(source.contains('CharacterActivator('), isFalse);
    expect(source.contains('buildPlayerShortcutBindings('), isTrue);
  });

  testWidgets('disabled mark keys really do nothing at the widget layer', (
    tester,
  ) async {
    var marks = 0;
    var seeks = 0;
    Widget host(bool markKeysEnabled) => MaterialApp(
      home: PlayerGlobalShortcuts(
        bindings: buildPlayerShortcutBindings(
          markKeysEnabled: markKeysEnabled,
          actions: {
            for (final shortcut in playerShortcuts)
              shortcut.id: switch (shortcut.id) {
                'markUnknown' => () => marks++,
                'seekBack' => () => seeks++,
                _ => () {},
              },
          },
        ),
        child: const Focus(
          autofocus: true,
          child: Scaffold(body: Text('player')),
        ),
      ),
    );

    await tester.pumpWidget(host(false));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    expect(marks, 0);
    expect(seeks, 1);

    await tester.pumpWidget(host(true));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(marks, 1);
  });
}
