import 'package:flutter/material.dart';

import '../../controllers/material_capability_coordinator.dart';
import '../../controllers/media_library_scan_controller.dart';
import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/learning_material.dart';
import '../../models/personal_library.dart';
import '../../theme/breakpoints.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import 'personal_library_section.dart';

/// The learner-facing state views of one material library.
enum LibraryView { all, recent, offline }

/// Material kinds are filters on one library, never separate destinations.
enum LibraryTypeFilter { all, article, audio, video }

/// The learner's retained materials, regardless of whether their usable form
/// is text, audio, video, or a mixture of them.
///
/// It no longer answers "what should I do now". The continue card and the
/// status strip that used to sit on top moved to the today pane, because a
/// library that also opened the day was half of why two sidebar rows asked
/// the same question.
class ListeningHome extends StatefulWidget {
  const ListeningHome({
    super.key,
    required this.onOpenMedia,
    required this.onOpenOnline,
    this.onOpenDocument,
    this.personalLibrary,
    this.personalLibraryFailure,
    this.onRetryLibrary,
    this.offlineEntries,
    this.familiarSupplyEnabled = true,
    this.scan,
    this.onScanRefresh,
    this.onScanCancel,
    this.onRetryScanRegistrations,
    this.onChooseManagedStoreLocation,
    this.onOpenLibraryEntry,
    this.onStartExtensiveEntry,
    this.onStartIntensiveEntry,
    this.onSetLibraryIntent,
    this.onToggleFamiliarSupply,
    this.capabilityCoordinator,
    this.onRequestCapability,
    this.onCancelCapability,
  });

  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;

  /// The primary "Open document" action, opening the direct document session.
  final VoidCallback? onOpenDocument;

  /// The authoritative library: retained materials projected with their media
  /// rows. Membership, order, and titles come from here; the raw media
  /// snapshot is not a library authority for the UI.
  final List<PersonalLibraryEntry>? personalLibrary;
  final ApiFailure? personalLibraryFailure;
  final VoidCallback? onRetryLibrary;

  /// The offline subset of [personalLibrary] (rows whose document rendition
  /// bytes or local media file is available). Offline used to be its own
  /// sidebar destination; it is a filter on the library now.
  final List<PersonalLibraryEntry>? offlineEntries;
  final bool familiarSupplyEnabled;

  /// Folder-scan state, or null on a surface that has no scan wired. The scan
  /// is the only thing that can tell an empty library apart from a library
  /// nobody could read, so it renders even when [personalLibrary] is unknown.
  final MediaLibraryScanState? scan;
  final VoidCallback? onScanRefresh;
  final VoidCallback? onScanCancel;
  final VoidCallback? onRetryScanRegistrations;
  final VoidCallback? onChooseManagedStoreLocation;

  /// Activates a library row's workbench session — the single primary
  /// action every row now offers.
  final void Function(PersonalLibraryEntry entry)? onOpenLibraryEntry;
  final void Function(PersonalLibraryEntry entry)? onStartExtensiveEntry;
  final void Function(PersonalLibraryEntry entry)? onStartIntensiveEntry;
  final void Function(PersonalLibraryEntry entry, String? intent)?
  onSetLibraryIntent;
  final void Function(bool enabled)? onToggleFamiliarSupply;

  /// Capability completion wiring for library rows (optional: without it rows
  /// render today's actions only).
  final MaterialCapabilityCoordinator? capabilityCoordinator;
  final void Function(
    PersonalLibraryEntry entry,
    MaterialCapability capability,
  )?
  onRequestCapability;
  final void Function(
    PersonalLibraryEntry entry,
    MaterialCapability capability,
  )?
  onCancelCapability;

  @override
  State<ListeningHome> createState() => _ListeningHomeState();
}

class _ListeningHomeState extends State<ListeningHome> {
  var _view = LibraryView.all;
  var _type = LibraryTypeFilter.all;

  /// History used to be its own sidebar destination whose entire body was
  /// this list sorted by `updatedAtMs` — one data source, two rooms, one
  /// `sort` apart. It is an ordering on the library now, next to the offline
  /// filter that was demoted for the same reason. The timestamp is the
  /// retained material's: membership, ordering, and titles all come from the
  /// Personal Library projection.
  List<PersonalLibraryEntry>? _visibleEntries() {
    final source = _view == LibraryView.offline
        ? widget.offlineEntries
        : widget.personalLibrary;
    if (source == null) return null;
    final filtered = switch (_type) {
      LibraryTypeFilter.all => source,
      LibraryTypeFilter.article => source.where((entry) => entry.canRead),
      LibraryTypeFilter.audio => source.where((entry) => entry.canListen),
      LibraryTypeFilter.video => source.where((entry) => entry.canWatch),
    }.toList(growable: false);
    if (_view == LibraryView.recent) {
      filtered.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < ListenBreakpoints.homeSidebar;
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: _HomeContent(
          compact: compact,
          onOpenMedia: widget.onOpenMedia,
          onOpenOnline: widget.onOpenOnline,
          onOpenDocument: widget.onOpenDocument,
          view: _view,
          onViewChanged: (value) => setState(() => _view = value),
          type: _type,
          onTypeChanged: (value) => setState(() => _type = value),
          personalLibrary: _visibleEntries(),
          personalLibraryFailure: widget.personalLibraryFailure,
          onRetryLibrary: widget.onRetryLibrary,
          familiarSupplyEnabled: widget.familiarSupplyEnabled,
          scan: widget.scan,
          onScanRefresh: widget.onScanRefresh,
          onScanCancel: widget.onScanCancel,
          onRetryScanRegistrations: widget.onRetryScanRegistrations,
          onChooseManagedStoreLocation: widget.onChooseManagedStoreLocation,
          onOpenLibraryEntry: widget.onOpenLibraryEntry,
          onStartExtensiveEntry: widget.onStartExtensiveEntry,
          onStartIntensiveEntry: widget.onStartIntensiveEntry,
          onSetLibraryIntent: widget.onSetLibraryIntent,
          onToggleFamiliarSupply: widget.onToggleFamiliarSupply,
          capabilityCoordinator: widget.capabilityCoordinator,
          onRequestCapability: widget.onRequestCapability,
          onCancelCapability: widget.onCancelCapability,
        ),
      );
    },
  );
}

class _HomeContent extends StatelessWidget {
  const _HomeContent({
    required this.compact,
    required this.onOpenMedia,
    required this.onOpenOnline,
    required this.onOpenDocument,
    required this.view,
    required this.onViewChanged,
    required this.type,
    required this.onTypeChanged,
    required this.personalLibrary,
    required this.personalLibraryFailure,
    required this.onRetryLibrary,
    required this.familiarSupplyEnabled,
    required this.scan,
    required this.onScanRefresh,
    required this.onScanCancel,
    required this.onRetryScanRegistrations,
    required this.onChooseManagedStoreLocation,
    required this.onOpenLibraryEntry,
    required this.onStartExtensiveEntry,
    required this.onStartIntensiveEntry,
    required this.onSetLibraryIntent,
    required this.onToggleFamiliarSupply,
    this.capabilityCoordinator,
    this.onRequestCapability,
    this.onCancelCapability,
  });

  final bool compact;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback? onOpenDocument;

  /// The library's offline filter: offline used to be a sidebar destination
  /// sharing one data source with this section, so it reads as a view on the
  /// library now.
  final LibraryView view;
  final ValueChanged<LibraryView> onViewChanged;
  final LibraryTypeFilter type;
  final ValueChanged<LibraryTypeFilter> onTypeChanged;

  final List<PersonalLibraryEntry>? personalLibrary;
  final ApiFailure? personalLibraryFailure;
  final VoidCallback? onRetryLibrary;
  final bool familiarSupplyEnabled;
  final MediaLibraryScanState? scan;
  final VoidCallback? onScanRefresh;
  final VoidCallback? onScanCancel;
  final VoidCallback? onRetryScanRegistrations;
  final VoidCallback? onChooseManagedStoreLocation;
  final void Function(PersonalLibraryEntry entry)? onOpenLibraryEntry;
  final void Function(PersonalLibraryEntry entry)? onStartExtensiveEntry;
  final void Function(PersonalLibraryEntry entry)? onStartIntensiveEntry;
  final void Function(PersonalLibraryEntry entry, String? intent)?
  onSetLibraryIntent;
  final void Function(bool enabled)? onToggleFamiliarSupply;
  final MaterialCapabilityCoordinator? capabilityCoordinator;
  final void Function(
    PersonalLibraryEntry entry,
    MaterialCapability capability,
  )?
  onRequestCapability;
  final void Function(
    PersonalLibraryEntry entry,
    MaterialCapability capability,
  )?
  onCancelCapability;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      // One page role per window width, instead of four different numbers in
      // four directions (24|48 / 28|44 / 24|48 / 40, three of them off any
      // ladder). This is the inset the coach dashboard and the vocabulary
      // detail already use, so the home page finally measures its margin the
      // same way the rest of the app does.
      padding: compact ? ListenPadding.pageCompact : ListenPadding.page,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // Wide content that carries media, not a reading measure: the cap
          // only stops the layout sprawling once the window is much wider than
          // the content needs.
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.wideColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.text('sidebarLibrary'),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: ListenSpacing.gap4),
                        Text(
                          l.text('librarySubtitle'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ListenSpacing.gap16),
                  _UnifiedImportAction(
                    onOpenDocument: onOpenDocument,
                    onOpenMedia: onOpenMedia,
                    onOpenOnline: onOpenOnline,
                  ),
                ],
              ),
              if (personalLibrary != null &&
                  onOpenLibraryEntry != null &&
                  onStartExtensiveEntry != null &&
                  onStartIntensiveEntry != null &&
                  onSetLibraryIntent != null &&
                  onToggleFamiliarSupply != null) ...[
                const SizedBox(height: ListenSpacing.gap24),
                Text(
                  l.text('libraryStatusFilter'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                Wrap(
                  spacing: ListenSpacing.gap8,
                  runSpacing: ListenSpacing.gap8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text(l.text('libraryFilterAll')),
                      selected: view == LibraryView.all,
                      onSelected: (_) => onViewChanged(LibraryView.all),
                    ),
                    ChoiceChip(
                      label: Text(l.text('sidebarHistory')),
                      selected: view == LibraryView.recent,
                      onSelected: (_) => onViewChanged(LibraryView.recent),
                    ),
                    ChoiceChip(
                      label: Text(l.text('sidebarOfflineDownloads')),
                      selected: view == LibraryView.offline,
                      onSelected: (_) => onViewChanged(LibraryView.offline),
                    ),
                  ],
                ),
                const SizedBox(height: ListenSpacing.gap12),
                Text(
                  l.text('libraryTypeFilter'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                Wrap(
                  spacing: ListenSpacing.gap8,
                  runSpacing: ListenSpacing.gap8,
                  children: [
                    ChoiceChip(
                      label: Text(l.text('libraryTypeAll')),
                      selected: type == LibraryTypeFilter.all,
                      onSelected: (_) => onTypeChanged(LibraryTypeFilter.all),
                    ),
                    ChoiceChip(
                      label: Text(l.text('libraryTypeArticle')),
                      selected: type == LibraryTypeFilter.article,
                      onSelected: (_) =>
                          onTypeChanged(LibraryTypeFilter.article),
                    ),
                    ChoiceChip(
                      label: Text(l.text('libraryTypeAudio')),
                      selected: type == LibraryTypeFilter.audio,
                      onSelected: (_) => onTypeChanged(LibraryTypeFilter.audio),
                    ),
                    ChoiceChip(
                      label: Text(l.text('libraryTypeVideo')),
                      selected: type == LibraryTypeFilter.video,
                      onSelected: (_) => onTypeChanged(LibraryTypeFilter.video),
                    ),
                  ],
                ),
                const SizedBox(height: ListenSpacing.gap12),
                PersonalLibrarySection(
                  entries: personalLibrary,
                  showHeader: false,
                  groupByQueue: false,
                  simplifiedRows: true,
                  familiarSupplyEnabled: familiarSupplyEnabled,
                  sidecarSubtitlePaths:
                      scan?.sidecarSubtitlePaths ?? const <String>{},
                  onOpen: onOpenLibraryEntry!,
                  onStartExtensive: onStartExtensiveEntry!,
                  onStartIntensive: onStartIntensiveEntry!,
                  onSetIntent: onSetLibraryIntent!,
                  onToggleFamiliarSupply: onToggleFamiliarSupply!,
                  capabilityCoordinator: capabilityCoordinator,
                  onRequestCapability: onRequestCapability,
                  onCancelCapability: onCancelCapability,
                ),
              ] else if (personalLibraryFailure != null) ...[
                const SizedBox(height: ListenSpacing.gap24),
                ApiFailureNotice(
                  message: l.text('personalLibraryLoadFailed'),
                  failure: personalLibraryFailure,
                ),
                if (onRetryLibrary != null) ...[
                  const SizedBox(height: ListenSpacing.gap8),
                  OutlinedButton.icon(
                    onPressed: onRetryLibrary,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.text('retry')),
                  ),
                ],
              ] else ...[
                const SizedBox(height: ListenSpacing.gap24),
                Text(
                  l.text('personalLibraryLoading'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (scan != null &&
                  onScanRefresh != null &&
                  onScanCancel != null &&
                  onRetryScanRegistrations != null &&
                  onChooseManagedStoreLocation != null) ...[
                const SizedBox(height: ListenSpacing.gap24),
                Text(
                  l.text('libraryStorageAndScan'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                MediaLibraryScanCard(
                  state: scan!,
                  onRefresh: onScanRefresh!,
                  onCancel: onScanCancel!,
                  onRetryFailures: onRetryScanRegistrations!,
                  onChooseFolder: onChooseManagedStoreLocation!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedImportAction extends StatelessWidget {
  const _UnifiedImportAction({
    required this.onOpenDocument,
    required this.onOpenMedia,
    required this.onOpenOnline,
  });

  final VoidCallback? onOpenDocument;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return MenuAnchor(
      menuChildren: [
        if (onOpenDocument != null)
          MenuItemButton(
            onPressed: onOpenDocument,
            leadingIcon: const Icon(Icons.description_outlined),
            child: Text(l.text('openDocument')),
          ),
        MenuItemButton(
          onPressed: onOpenMedia,
          leadingIcon: const Icon(Icons.video_file_outlined),
          child: Text(l.text('openVideoAudio')),
        ),
        MenuItemButton(
          onPressed: onOpenOnline,
          leadingIcon: const Icon(Icons.link_outlined),
          child: Text(l.text('openUrl')),
        ),
      ],
      builder: (context, controller, child) => Tooltip(
        message: l.text('libraryImportMaterial'),
        child: FilledButton.icon(
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.add),
          label: Text(l.text('libraryImportMaterial')),
        ),
      ),
    );
  }
}
