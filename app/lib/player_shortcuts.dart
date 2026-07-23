import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// #25: the single source of truth for every player-level key binding.
///
/// The `CallbackShortcuts` map in `main.dart`, the cheat sheet, the settings
/// toggle, and the native macOS menu (#23) all read this table — a key never
/// lives anywhere else. Reassignments here were owner-approved on #25:
/// ←/→ seek (the universal player convention), sentence navigation on ⌥←/⌥→,
/// F/Esc fullscreen (ships with the immersive state, #25 part A), M mute,
/// ↑/↓ volume, [ ] speed (mpv convention).
enum PlayerShortcutCategory {
  playback('shortcutCategoryPlayback'),
  sentences('shortcutCategorySentences'),
  learning('shortcutCategoryLearning'),
  help('shortcutCategoryHelp');

  const PlayerShortcutCategory(this.labelKey);

  /// `AppLocalizations` key for the cheat-sheet section header.
  final String labelKey;
}

class PlayerShortcut {
  const PlayerShortcut({
    required this.id,
    required this.activator,
    required this.labelKey,
    required this.category,
    this.isMarkKey = false,
  });

  /// Stable action id; the host supplies the matching callback.
  final String id;

  final ShortcutActivator activator;

  /// `AppLocalizations` key describing the action.
  final String labelKey;

  final PlayerShortcutCategory category;

  /// Bare digit keys (1/2/3) subject to the settings toggle
  /// (`markKeysEnabled`) — easy to press by accident, so they can be
  /// switched off without losing the rest of the table.
  final bool isMarkKey;
}

/// Declaration order is presentation order in the cheat sheet.
const playerShortcuts = <PlayerShortcut>[
  // ── Playback ──
  PlayerShortcut(
    id: 'playPause',
    activator: SingleActivator(LogicalKeyboardKey.space),
    labelKey: 'shortcutPlayPause',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'seekBack',
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft),
    labelKey: 'shortcutSeekBack',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'seekForward',
    activator: SingleActivator(LogicalKeyboardKey.arrowRight),
    labelKey: 'shortcutSeekForward',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'volumeUp',
    activator: SingleActivator(LogicalKeyboardKey.arrowUp),
    labelKey: 'shortcutVolumeUp',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'volumeDown',
    activator: SingleActivator(LogicalKeyboardKey.arrowDown),
    labelKey: 'shortcutVolumeDown',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'toggleMute',
    activator: SingleActivator(LogicalKeyboardKey.keyM),
    labelKey: 'shortcutMute',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'speedDown',
    activator: SingleActivator(LogicalKeyboardKey.bracketLeft),
    labelKey: 'shortcutSpeedDown',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'speedUp',
    activator: SingleActivator(LogicalKeyboardKey.bracketRight),
    labelKey: 'shortcutSpeedUp',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'toggleFullscreen',
    activator: SingleActivator(LogicalKeyboardKey.keyF),
    labelKey: 'shortcutToggleFullscreen',
    category: PlayerShortcutCategory.playback,
  ),
  PlayerShortcut(
    id: 'exitFullscreen',
    activator: SingleActivator(LogicalKeyboardKey.escape),
    labelKey: 'shortcutExitFullscreen',
    category: PlayerShortcutCategory.playback,
  ),
  // ── Sentences & subtitles ──
  PlayerShortcut(
    id: 'previousSentence',
    activator: SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true),
    labelKey: 'shortcutPreviousSentence',
    category: PlayerShortcutCategory.sentences,
  ),
  PlayerShortcut(
    id: 'nextSentence',
    activator: SingleActivator(LogicalKeyboardKey.arrowRight, alt: true),
    labelKey: 'shortcutNextSentence',
    category: PlayerShortcutCategory.sentences,
  ),
  PlayerShortcut(
    id: 'loopSentence',
    activator: SingleActivator(LogicalKeyboardKey.keyL),
    labelKey: 'shortcutLoopSentence',
    category: PlayerShortcutCategory.sentences,
  ),
  PlayerShortcut(
    id: 'toggleSubtitles',
    activator: SingleActivator(LogicalKeyboardKey.keyH),
    labelKey: 'shortcutToggleSubtitles',
    category: PlayerShortcutCategory.sentences,
  ),
  // ── Learning ──
  PlayerShortcut(
    id: 'captureInbox',
    activator: SingleActivator(LogicalKeyboardKey.keyI),
    labelKey: 'shortcutCaptureInbox',
    category: PlayerShortcutCategory.learning,
  ),
  PlayerShortcut(
    id: 'toggleExtensiveListening',
    activator: SingleActivator(LogicalKeyboardKey.keyI, shift: true),
    labelKey: 'shortcutToggleExtensive',
    category: PlayerShortcutCategory.learning,
  ),
  PlayerShortcut(
    id: 'hardInterrupt',
    activator: SingleActivator(LogicalKeyboardKey.keyP, shift: true),
    labelKey: 'shortcutHardInterrupt',
    category: PlayerShortcutCategory.learning,
  ),
  PlayerShortcut(
    id: 'markUnknown',
    activator: SingleActivator(LogicalKeyboardKey.digit1),
    labelKey: 'shortcutMarkUnknown',
    category: PlayerShortcutCategory.learning,
    isMarkKey: true,
  ),
  PlayerShortcut(
    id: 'markKnownNotRecognized',
    activator: SingleActivator(LogicalKeyboardKey.digit2),
    labelKey: 'shortcutMarkKnownNotRecognized',
    category: PlayerShortcutCategory.learning,
    isMarkKey: true,
  ),
  PlayerShortcut(
    id: 'markKnownRecognized',
    activator: SingleActivator(LogicalKeyboardKey.digit3),
    labelKey: 'shortcutMarkKnownRecognized',
    category: PlayerShortcutCategory.learning,
    isMarkKey: true,
  ),
  // ── Help ──
  // `?` is a shifted character on most layouts, so the character activator
  // matches whatever the keyboard produces instead of hard-coding Shift+/.
  PlayerShortcut(
    id: 'showCheatSheet',
    activator: CharacterActivator('?'),
    labelKey: 'shortcutShowCheatSheet',
    category: PlayerShortcutCategory.help,
  ),
];

/// Builds the live `CallbackShortcuts` bindings from the table.
///
/// Every table id must have a callback in [actions] — a missing or unknown id
/// is a wiring bug and throws in debug builds. Mark keys drop out when
/// [markKeysEnabled] is false.
Map<ShortcutActivator, VoidCallback> buildPlayerShortcutBindings({
  required Map<String, VoidCallback> actions,
  required bool markKeysEnabled,
}) {
  assert(() {
    final tableIds = playerShortcuts.map((s) => s.id).toSet();
    final missing = tableIds.difference(actions.keys.toSet());
    final unknown = actions.keys.toSet().difference(tableIds);
    if (missing.isNotEmpty || unknown.isNotEmpty) {
      throw FlutterError(
        'Shortcut actions out of sync with the table: '
        'missing=$missing unknown=$unknown',
      );
    }
    return true;
  }());
  return {
    for (final shortcut in playerShortcuts)
      if (!shortcut.isMarkKey || markKeysEnabled)
        shortcut.activator: actions[shortcut.id]!,
  };
}

/// macOS-style caption for a shortcut, e.g. `⌥ ←`, `⇧ I`, `Space`, `?`.
String shortcutCaption(ShortcutActivator activator) {
  if (activator is CharacterActivator) return activator.character;
  final single = activator as SingleActivator;
  final parts = <String>[
    if (single.control) '⌃',
    if (single.alt) '⌥',
    if (single.shift) '⇧',
    if (single.meta) '⌘',
    _keyCaption(single.trigger),
  ];
  return parts.join(' ');
}

String _keyCaption(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.space) return 'Space';
  if (key == LogicalKeyboardKey.escape) return 'Esc';
  if (key == LogicalKeyboardKey.arrowLeft) return '←';
  if (key == LogicalKeyboardKey.arrowRight) return '→';
  if (key == LogicalKeyboardKey.arrowUp) return '↑';
  if (key == LogicalKeyboardKey.arrowDown) return '↓';
  if (key == LogicalKeyboardKey.bracketLeft) return '[';
  if (key == LogicalKeyboardKey.bracketRight) return ']';
  final label = key.keyLabel;
  return label.length == 1 ? label.toUpperCase() : label;
}
