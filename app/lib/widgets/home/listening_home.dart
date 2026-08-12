import 'package:flutter/material.dart';

import '../../controllers/material_capability_coordinator.dart';
import '../../controllers/media_library_scan_controller.dart';
import '../../localization.dart';
import '../../models/learning_material.dart';
import '../../models/personal_library.dart';
import '../../theme/breakpoints.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'personal_library_section.dart';

/// How the media library is ordered.
///
/// [recent] is what the history destination used to be: the same rows, sorted
/// by `updatedAtMs` on the retained material. [queue] is the triage grouping
/// the library section does on its own.
enum LibrarySort { queue, recent }

/// The capability view over the Personal Library.
///
/// Read and Listen/Watch are capabilities of the same retained materials —
/// filtering is a view, never a copy and never a separate library object.
enum LibraryCapabilityFilter { all, read, listen, watch }

/// The Personal Library: what is already here, and how to add more. One
/// segment of the "listen" destination — discovery is the other, and both end
/// in this same library.
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
    this.offlineEntries,
    this.familiarSupplyEnabled = true,
    this.scan,
    this.onScanRefresh,
    this.onScanCancel,
    this.onRetryScanRegistrations,
    this.onChooseManagedStoreLocation,
    this.onOpenLibraryDocument,
    this.onOpenLibraryMedia,
    this.onStartExtensiveEntry,
    this.onStartIntensiveEntry,
    this.onSetLibraryIntent,
    this.onToggleFamiliarSupply,
    this.capabilityCoordinator,
    this.onRequestCapability,
    this.onCancelCapability,
    this.onOpenComposition,
  });

  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;

  /// The primary "Open document" action, opening the direct document session.
  final VoidCallback? onOpenDocument;

  /// The authoritative library: retained materials projected with their media
  /// rows. Membership, order, and titles come from here; the raw media
  /// snapshot is not a library authority for the UI.
  final List<PersonalLibraryEntry>? personalLibrary;

  /// The offline subset of [personalLibrary] (rows whose inline text or local
  /// media file is available). Offline used to be its own sidebar destination;
  /// it is a filter on the library now.
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
  final void Function(PersonalLibraryEntry entry)? onOpenLibraryDocument;
  final void Function(PersonalLibraryEntry entry)? onOpenLibraryMedia;
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
  )? onRequestCapability;
  final void Function(
    PersonalLibraryEntry entry,
    MaterialCapability capability,
  )? onCancelCapability;
  final void Function(PersonalLibraryEntry entry)? onOpenComposition;

  @override
  State<ListeningHome> createState() => _ListeningHomeState();
}

class _ListeningHomeState extends State<ListeningHome> {
  var _offlineOnly = false;
  var _sort = LibrarySort.queue;
  var _capability = LibraryCapabilityFilter.all;

  /// History used to be its own sidebar destination whose entire body was
  /// this list sorted by `updatedAtMs` — one data source, two rooms, one
  /// `sort` apart. It is an ordering on the library now, next to the offline
  /// filter that was demoted for the same reason. The timestamp is the
  /// retained material's: membership, ordering, and titles all come from the
  /// Personal Library projection.
  List<PersonalLibraryEntry>? _ordered(List<PersonalLibraryEntry>? entries) {
    if (entries == null || _sort == LibrarySort.queue) return entries;
    return [...entries]..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
  }

  /// Applies the capability view. A filter never changes membership — the
  /// same rows reappear when it is cleared.
  List<PersonalLibraryEntry>? _capabilityFiltered(
    List<PersonalLibraryEntry>? entries,
  ) {
    if (entries == null || _capability == LibraryCapabilityFilter.all) {
      return entries;
    }
    return switch (_capability) {
      LibraryCapabilityFilter.read =>
        entries.where((entry) => entry.canRead).toList(growable: false),
      LibraryCapabilityFilter.listen =>
        entries.where((entry) => entry.canListen).toList(growable: false),
      LibraryCapabilityFilter.watch =>
        entries.where((entry) => entry.canWatch).toList(growable: false),
      LibraryCapabilityFilter.all => entries,
    };
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
          offlineOnly: _offlineOnly,
          onOfflineOnlyChanged: (value) => setState(() => _offlineOnly = value),
          sort: _sort,
          onSortChanged: (value) => setState(() => _sort = value),
          capability: _capability,
          onCapabilityChanged: (value) => setState(() => _capability = value),
          personalLibrary: _ordered(
            _capabilityFiltered(
              _offlineOnly ? widget.offlineEntries : widget.personalLibrary,
            ),
          ),
          familiarSupplyEnabled: widget.familiarSupplyEnabled,
          scan: widget.scan,
          onScanRefresh: widget.onScanRefresh,
          onScanCancel: widget.onScanCancel,
          onRetryScanRegistrations: widget.onRetryScanRegistrations,
          onChooseManagedStoreLocation: widget.onChooseManagedStoreLocation,
          onOpenLibraryDocument: widget.onOpenLibraryDocument,
          onOpenLibraryMedia: widget.onOpenLibraryMedia,
          onStartExtensiveEntry: widget.onStartExtensiveEntry,
          onStartIntensiveEntry: widget.onStartIntensiveEntry,
          onSetLibraryIntent: widget.onSetLibraryIntent,
          onToggleFamiliarSupply: widget.onToggleFamiliarSupply,
          capabilityCoordinator: widget.capabilityCoordinator,
          onRequestCapability: widget.onRequestCapability,
          onCancelCapability: widget.onCancelCapability,
          onOpenComposition: widget.onOpenComposition,
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
    required this.offlineOnly,
    required this.onOfflineOnlyChanged,
    required this.sort,
    required this.onSortChanged,
    required this.capability,
    required this.onCapabilityChanged,
    required this.personalLibrary,
    required this.familiarSupplyEnabled,
    required this.scan,
    required this.onScanRefresh,
    required this.onScanCancel,
    required this.onRetryScanRegistrations,
    required this.onChooseManagedStoreLocation,
    required this.onOpenLibraryDocument,
    required this.onOpenLibraryMedia,
    required this.onStartExtensiveEntry,
    required this.onStartIntensiveEntry,
    required this.onSetLibraryIntent,
    required this.onToggleFamiliarSupply,
    this.capabilityCoordinator,
    this.onRequestCapability,
    this.onCancelCapability,
    this.onOpenComposition,
  });

  final bool compact;
  final VoidCallback onOpenMedia;
  final VoidCallback onOpenOnline;
  final VoidCallback? onOpenDocument;

  /// The library's offline filter: offline used to be a sidebar destination
  /// sharing one data source with this section, so it reads as a view on the
  /// library now.
  final bool offlineOnly;
  final ValueChanged<bool> onOfflineOnlyChanged;

  /// The library's ordering. History was demoted from a destination to this,
  /// for the same reason offline was.
  final LibrarySort sort;
  final ValueChanged<LibrarySort> onSortChanged;

  /// The capability view: All / Read / Listen-Watch.
  final LibraryCapabilityFilter capability;
  final ValueChanged<LibraryCapabilityFilter> onCapabilityChanged;

  final List<PersonalLibraryEntry>? personalLibrary;
  final bool familiarSupplyEnabled;
  final MediaLibraryScanState? scan;
  final VoidCallback? onScanRefresh;
  final VoidCallback? onScanCancel;
  final VoidCallback? onRetryScanRegistrations;
  final VoidCallback? onChooseManagedStoreLocation;
  final void Function(PersonalLibraryEntry entry)? onOpenLibraryDocument;
  final void Function(PersonalLibraryEntry entry)? onOpenLibraryMedia;
  final void Function(PersonalLibraryEntry entry)? onStartExtensiveEntry;
  final void Function(PersonalLibraryEntry entry)? onStartIntensiveEntry;
  final void Function(PersonalLibraryEntry entry, String? intent)?
  onSetLibraryIntent;
  final void Function(bool enabled)? onToggleFamiliarSupply;
  final MaterialCapabilityCoordinator? capabilityCoordinator;
  final void Function(
    PersonalLibraryEntry entry,
    MaterialCapability capability,
  )? onRequestCapability;
  final void Function(
    PersonalLibraryEntry entry,
    MaterialCapability capability,
  )? onCancelCapability;
  final void Function(PersonalLibraryEntry entry)? onOpenComposition;

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
              // No page title: this surface is a segment of the "listen"
              // destination now, and the segment row above it already says
              // which one. "Continue learning" and the status strip moved to
              // the today pane — the library answering "what should I do now"
              // was half of why two destinations asked the same question.
              Text(
                l.text('addContentSource'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ListenSpacing.gap12),
              _ResponsiveActionGrid(
                compact: compact,
                children: [
                  if (onOpenDocument != null)
                    _SourceAction(
                      icon: Icons.description_outlined,
                      label: l.text('openDocument'),
                      sourceLabel: l.text('documentSource'),
                      onTap: onOpenDocument!,
                      primary: true,
                    ),
                  _SourceAction(
                    icon: Icons.folder_open_outlined,
                    label: l.text('openVideoAudio'),
                    sourceLabel: l.text('localSource'),
                    onTap: onOpenMedia,
                  ),
                  _SourceAction(
                    icon: Icons.link_outlined,
                    label: l.text('openUrl'),
                    sourceLabel: l.text('onlineSource'),
                    onTap: onOpenOnline,
                  ),
                ],
              ),
              if (scan != null &&
                  onScanRefresh != null &&
                  onScanCancel != null &&
                  onRetryScanRegistrations != null &&
                  onChooseManagedStoreLocation != null) ...[
                const SizedBox(height: ListenSpacing.gap32),
                MediaLibraryScanCard(
                  state: scan!,
                  onRefresh: onScanRefresh!,
                  onCancel: onScanCancel!,
                  onRetryFailures: onRetryScanRegistrations!,
                  onChooseFolder: onChooseManagedStoreLocation!,
                ),
              ],
              if (personalLibrary != null &&
                  onOpenLibraryDocument != null &&
                  onOpenLibraryMedia != null &&
                  onStartExtensiveEntry != null &&
                  onStartIntensiveEntry != null &&
                  onSetLibraryIntent != null &&
                  onToggleFamiliarSupply != null) ...[
                SizedBox(
                  height: scan == null
                      ? ListenSpacing.gap32
                      : ListenSpacing.gap12,
                ),
                Wrap(
                  spacing: ListenSpacing.gap8,
                  runSpacing: ListenSpacing.gap8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: Text(l.text('libraryFilterAll')),
                      selected: capability == LibraryCapabilityFilter.all,
                      onSelected: (_) =>
                          onCapabilityChanged(LibraryCapabilityFilter.all),
                    ),
                    ChoiceChip(
                      label: Text(l.text('libraryFilterRead')),
                      selected: capability == LibraryCapabilityFilter.read,
                      onSelected: (_) =>
                          onCapabilityChanged(LibraryCapabilityFilter.read),
                    ),
                    ChoiceChip(
                      label: Text(l.text('libraryFilterListen')),
                      selected: capability == LibraryCapabilityFilter.listen,
                      onSelected: (_) =>
                          onCapabilityChanged(LibraryCapabilityFilter.listen),
                    ),
                    ChoiceChip(
                      label: Text(l.text('libraryFilterWatch')),
                      selected: capability == LibraryCapabilityFilter.watch,
                      onSelected: (_) =>
                          onCapabilityChanged(LibraryCapabilityFilter.watch),
                    ),
                    FilterChip(
                      // Offline used to occupy its own sidebar slot with the
                      // same data source; as a filter it stays one view on
                      // the library.
                      label: Text(l.text('sidebarOfflineDownloads')),
                      selected: offlineOnly,
                      onSelected: onOfflineOnlyChanged,
                    ),
                    // And so did history, whose whole body was this list in
                    // `updatedAtMs` order.
                    ChoiceChip(
                      label: Text(l.text('librarySortQueue')),
                      selected: sort == LibrarySort.queue,
                      onSelected: (_) => onSortChanged(LibrarySort.queue),
                    ),
                    ChoiceChip(
                      label: Text(l.text('sidebarHistory')),
                      selected: sort == LibrarySort.recent,
                      onSelected: (_) => onSortChanged(LibrarySort.recent),
                    ),
                  ],
                ),
                const SizedBox(height: ListenSpacing.gap12),
                PersonalLibrarySection(
                  entries: personalLibrary,
                  familiarSupplyEnabled: familiarSupplyEnabled,
                  sidecarSubtitlePaths:
                      scan?.sidecarSubtitlePaths ?? const <String>{},
                  onOpenDocument: onOpenLibraryDocument!,
                  onOpenMedia: onOpenLibraryMedia!,
                  onStartExtensive: onStartExtensiveEntry!,
                  onStartIntensive: onStartIntensiveEntry!,
                  onSetIntent: onSetLibraryIntent!,
                  onToggleFamiliarSupply: onToggleFamiliarSupply!,
                  capabilityCoordinator: capabilityCoordinator,
                  onRequestCapability: onRequestCapability,
                  onCancelCapability: onCancelCapability,
                  onOpenComposition: onOpenComposition,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveActionGrid extends StatelessWidget {
  const _ResponsiveActionGrid({required this.compact, required this.children});

  final bool compact;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const SizedBox(height: ListenSpacing.gap8),
          ],
        ],
      );
    }
    final perRow = children.length;
    final rows = <List<Widget?>>[];
    for (var start = 0; start < children.length; start += perRow) {
      final row = <Widget?>[
        ...children.sublist(
          start,
          (start + perRow) > children.length ? children.length : start + perRow,
        ),
      ];
      while (row.length < perRow) {
        row.add(null);
      }
      rows.add(row);
    }
    return Column(
      children: [
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < rows[rowIndex].length; index++) ...[
                Expanded(child: rows[rowIndex][index] ?? const SizedBox()),
                if (index != rows[rowIndex].length - 1)
                  const SizedBox(width: ListenSpacing.gap12),
              ],
            ],
          ),
          if (rowIndex != rows.length - 1)
            const SizedBox(height: ListenSpacing.gap12),
        ],
      ],
    );
  }
}

class _SourceAction extends StatelessWidget {
  const _SourceAction({
    required this.icon,
    required this.label,
    required this.sourceLabel,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final String sourceLabel;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: primary
          ? colors.primaryContainer.withValues(alpha: 0.42)
          : colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(
          color: primary
              ? colors.primary.withValues(alpha: 0.42)
              : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 112,
          child: Padding(
            padding: ListenPadding.card,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary ? colors.primary : colors.secondaryContainer,
                    borderRadius: ListenRadii.controlBorder,
                  ),
                  child: Icon(
                    icon,
                    color: primary
                        ? colors.onPrimary
                        : colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: ListenSpacing.gap4),
                      Text(
                        sourceLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
