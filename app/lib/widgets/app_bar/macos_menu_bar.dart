import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../localization.dart';
import '../../player_shortcuts.dart';
import 'app_bar_capabilities.dart';

/// #23: the native macOS menu bar, built with [PlatformMenuBar] so AppKit
/// renders it — no Swift beyond the existing runner.
///
/// Three disciplines keep this a *presentation surface*, never a second
/// definition:
///
/// * **Availability** comes from [AppBarCapabilities] — the same object the
///   AppBar menus read (#24). A menu item is disabled by passing a null
///   `onSelected`, exactly when the AppBar would disable its counterpart.
/// * **Playback and Help items** take their labels and callbacks from the
///   shortcut table (`player_shortcuts.dart`, #25) via the same actions map
///   `main.dart` hands to `buildPlayerShortcutBindings` — one id, one label,
///   one callback, two surfaces.
/// * **Key equivalents on menu items are ⌘-only** (owner decision on #23).
///   AppKit fires a menu item's key equivalent *before* the event reaches
///   Flutter, so a bare-key equivalent (Space, F, [ ]) would swallow typing
///   in every text field, and ⌥←/⌥→ would break word-wise caret movement.
///   Bare-key bindings stay in the shortcut table and are discoverable
///   through the `?` cheat sheet; the ⌘ accelerators below (⌘, ⌘O ⇧⌘O and
///   the Edit set) are menu-owned and appear nowhere else.
class MacosMenuBar extends StatelessWidget {
  const MacosMenuBar({
    super.key,
    required this.capabilities,
    required this.shortcutActions,
    required this.onOpenSettings,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onImportPrimarySubtitle,
    required this.onImportSecondarySubtitle,
    required this.onImportEmbeddedSubtitle,
    required this.onArchiveMedia,
    required this.onOpenVocabulary,
    required this.onOpenReview,
    required this.onOpenCoach,
    required this.child,
  });

  final AppBarCapabilities capabilities;

  /// The same id → callback map that feeds `buildPlayerShortcutBindings`;
  /// Playback/Help menu items are the table rows wearing native dress.
  final Map<String, VoidCallback> shortcutActions;

  final VoidCallback onOpenSettings;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback onImportPrimarySubtitle;
  final VoidCallback onImportSecondarySubtitle;
  final VoidCallback onImportEmbeddedSubtitle;
  final VoidCallback onArchiveMedia;
  final VoidCallback onOpenVocabulary;
  final VoidCallback onOpenReview;
  final VoidCallback onOpenCoach;
  final Widget child;

  @override
  Widget build(BuildContext context) => PlatformMenuBar(
    menus: buildMacosMenus(
      l: AppLocalizations.of(context),
      capabilities: capabilities,
      shortcutActions: shortcutActions,
      onOpenSettings: onOpenSettings,
      onOpenMedia: onOpenMedia,
      onOpenOnline: onOpenOnline,
      onImportPrimarySubtitle: onImportPrimarySubtitle,
      onImportSecondarySubtitle: onImportSecondarySubtitle,
      onImportEmbeddedSubtitle: onImportEmbeddedSubtitle,
      onArchiveMedia: onArchiveMedia,
      onOpenVocabulary: onOpenVocabulary,
      onOpenReview: onOpenReview,
      onOpenCoach: onOpenCoach,
    ),
    child: child,
  );
}

/// Pure builder so tests can pin the structure without a platform channel.
List<PlatformMenu> buildMacosMenus({
  required AppLocalizations l,
  required AppBarCapabilities capabilities,
  required Map<String, VoidCallback> shortcutActions,
  required VoidCallback onOpenSettings,
  required VoidCallback onOpenMedia,
  required VoidCallback onOpenOnline,
  required VoidCallback onImportPrimarySubtitle,
  required VoidCallback onImportSecondarySubtitle,
  required VoidCallback onImportEmbeddedSubtitle,
  required VoidCallback onArchiveMedia,
  required VoidCallback onOpenVocabulary,
  required VoidCallback onOpenReview,
  required VoidCallback onOpenCoach,
}) {
  // A table row as a menu item: label from the table's l10n key, callback
  // from the shared actions map (missing id = wiring bug, fail fast), no key
  // equivalent (bare keys are cheat-sheet territory, see the class comment).
  PlatformMenuItem tableItem(String id, {bool enabled = true}) {
    final shortcut = playerShortcuts.singleWhere((s) => s.id == id);
    final action = shortcutActions[id]!;
    return PlatformMenuItem(
      label: l.text(shortcut.labelKey),
      onSelected: enabled ? action : null,
    );
  }

  return <PlatformMenu>[
    // ── App menu (label is replaced by the app name at runtime) ──
    PlatformMenu(
      label: 'LLPlayerNext',
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            // The ⌘, muscle memory (#23 acceptance item 1).
            PlatformMenuItem(
              label: l.text('menuPreferences'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: onOpenSettings,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    ),
    // ── File ──
    PlatformMenu(
      label: l.text('menuFile'),
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.text('openMedia'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: onOpenMedia,
            ),
            PlatformMenuItem(
              label: l.text('openUrl'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
                shift: true,
              ),
              onSelected: onOpenOnline,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.text('menuImportPrimarySubtitle'),
              onSelected: capabilities.canActOnMedia
                  ? onImportPrimarySubtitle
                  : null,
            ),
            PlatformMenuItem(
              label: l.text('menuImportSecondarySubtitle'),
              onSelected: capabilities.canActOnMedia
                  ? onImportSecondarySubtitle
                  : null,
            ),
            PlatformMenuItem(
              label: l.text('importEmbeddedText'),
              onSelected: capabilities.canActOnMedia
                  ? onImportEmbeddedSubtitle
                  : null,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.text('archiveMedia'),
              onSelected: capabilities.canActOnMedia ? onArchiveMedia : null,
            ),
          ],
        ),
      ],
    ),
    // ── Edit: the six standard items, routed to the focused text field via
    // text-editing intents. Everything else the template carried was noise
    // in this app (#23 acceptance item 2). ──
    PlatformMenu(
      label: l.text('menuEdit'),
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.text('menuUndo'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: () => _invokeOnFocusedField(
                const UndoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: l.text('menuRedo'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: () => _invokeOnFocusedField(
                const RedoTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.text('menuCut'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyX,
                meta: true,
              ),
              onSelected: () => _invokeOnFocusedField(
                CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: l.text('menuCopy'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
              ),
              onSelected: () =>
                  _invokeOnFocusedField(CopySelectionTextIntent.copy),
            ),
            PlatformMenuItem(
              label: l.text('menuPaste'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                meta: true,
              ),
              onSelected: () => _invokeOnFocusedField(
                const PasteTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
            PlatformMenuItem(
              label: l.text('menuSelectAll'),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyA,
                meta: true,
              ),
              onSelected: () => _invokeOnFocusedField(
                const SelectAllTextIntent(SelectionChangedCause.keyboard),
              ),
            ),
          ],
        ),
      ],
    ),
    // ── Playback: the shortcut table's rows, gated on a loaded media
    // session like the transport itself. ──
    PlatformMenu(
      label: l.text('menuPlayback'),
      menus: [
        PlatformMenuItemGroup(
          members: [tableItem('playPause', enabled: capabilities.hasMedia)],
        ),
        PlatformMenuItemGroup(
          members: [
            tableItem('previousSentence', enabled: capabilities.hasMedia),
            tableItem('nextSentence', enabled: capabilities.hasMedia),
            tableItem('loopSentence', enabled: capabilities.hasMedia),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            tableItem('toggleSubtitles', enabled: capabilities.hasMedia),
            tableItem('toggleFullscreen', enabled: capabilities.hasMedia),
          ],
        ),
      ],
    ),
    // ── Learning: every destination needs the local core, same gate the
    // AppBar applies. ──
    PlatformMenu(
      label: l.text('menuLearning'),
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.text('vocabulary'),
              onSelected: capabilities.coreReady ? onOpenVocabulary : null,
            ),
            PlatformMenuItem(
              label: l.text('review'),
              onSelected: capabilities.coreReady ? onOpenReview : null,
            ),
            PlatformMenuItem(
              label: l.text('coachDashboard'),
              onSelected: capabilities.coreReady ? onOpenCoach : null,
            ),
          ],
        ),
      ],
    ),
    // ── Window ──
    PlatformMenu(
      label: l.text('menuWindow'),
      menus: const [
        PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
      ],
    ),
    // ── Help: the cheat sheet is the discovery surface for every bare-key
    // binding the menus deliberately do not carry. ──
    PlatformMenu(
      label: l.text('menuHelp'),
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l.text('shortcutsTitle'),
              onSelected: shortcutActions['showCheatSheet']!,
            ),
          ],
        ),
      ],
    ),
  ];
}

/// Routes an Edit-menu command to whatever text field holds focus; with no
/// focused editable the command is a quiet no-op, matching how a native app
/// disables these items without a first responder.
void _invokeOnFocusedField(Intent intent) {
  final context = primaryFocus?.context;
  if (context == null) return;
  Actions.maybeInvoke(context, intent);
}
