import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/learning_edition_controller.dart';
import '../../localization.dart';
import '../../models/learning_edition.dart';
import '../../models/material_capability.dart';
import '../../services/media_import_file_service.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../common/listen_loading.dart';

const learningResourceKinds = <String>[
  'structured_reading',
  'subtitle_text_track',
  'anchor_time_alignment',
  'word_timeline',
  'phone_timeline',
  'sense_group_analysis',
  'word_acoustics',
  'prosody_analysis',
];

Future<void> showLearningEditionPanel({
  required BuildContext context,
  required LearningEditionController controller,
  required String materialId,
  Future<void> Function()? onGenerate,
  Future<void> Function()? onRegenerate,
  Future<void> Function(String path)? onImportPackage,
  Listenable? generationListenable,
  bool Function()? isGenerating,
  CapabilityRunView? Function()? runView,
  Future<void> Function()? onCancelGeneration,
  MediaImportFileService fileService = const LocalMediaImportFileService(),
}) {
  unawaited(controller.load(materialId));
  return showDialog<void>(
    context: context,
    builder: (_) => LearningEditionDialog(
      controller: controller,
      onGenerate: onGenerate,
      onRegenerate: onRegenerate,
      onImportPackage: onImportPackage,
      generationListenable: generationListenable,
      isGenerating: isGenerating,
      runView: runView,
      onCancelGeneration: onCancelGeneration,
      fileService: fileService,
    ),
  );
}

class LearningEditionAction extends StatelessWidget {
  const LearningEditionAction({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('learning-edition-action'),
    tooltip: AppLocalizations.of(context).text('learningEdition'),
    onPressed: onPressed,
    iconSize: ListenIconSize.chrome,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    icon: const Icon(Icons.inventory_2_outlined),
  );
}

class LearningEditionDialog extends StatefulWidget {
  const LearningEditionDialog({
    super.key,
    required this.controller,
    this.onGenerate,
    this.onRegenerate,
    this.onImportPackage,
    this.generationListenable,
    this.isGenerating,
    this.runView,
    this.onCancelGeneration,
    this.fileService = const LocalMediaImportFileService(),
  });

  final LearningEditionController controller;
  final Future<void> Function()? onGenerate;
  final Future<void> Function()? onRegenerate;
  final Future<void> Function(String path)? onImportPackage;
  final Listenable? generationListenable;
  final bool Function()? isGenerating;
  final CapabilityRunView? Function()? runView;
  final Future<void> Function()? onCancelGeneration;
  final MediaImportFileService fileService;

  @override
  State<LearningEditionDialog> createState() => _LearningEditionDialogState();
}

class _LearningEditionDialogState extends State<LearningEditionDialog> {
  bool _generationCallPending = false;
  String? _selectedReleaseId;

  bool get _generating =>
      _generationCallPending || (widget.isGenerating?.call() ?? false);

  Future<void> _generate() async {
    final generate = widget.onGenerate;
    if (generate == null || _generating) return;
    setState(() => _generationCallPending = true);
    try {
      await generate();
      await widget.controller.refresh();
    } finally {
      if (mounted) setState(() => _generationCallPending = false);
    }
  }

  Future<void> _regenerate() async {
    final regenerate = widget.onRegenerate ?? widget.onGenerate;
    if (regenerate == null || _generating) return;
    setState(() => _generationCallPending = true);
    try {
      await regenerate();
      await widget.controller.refresh();
    } finally {
      if (mounted) setState(() => _generationCallPending = false);
    }
  }

  Future<void> _importPackage() async {
    if (widget.controller.busy || _generating) return;
    final path = await widget.fileService.pickLearningPackage();
    if (path == null) return;
    if (widget.onImportPackage != null) {
      await widget.onImportPackage!(path);
      await widget.controller.refresh();
    } else {
      await widget.controller.importPackage(path);
    }
  }

  Future<void> _deleteEdition(LearningEdition edition) async {
    final l = AppLocalizations.of(context);
    if (edition.adopted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l.text('cannotDeleteAdoptedEdition')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.text('deleteLearningEditionConfirmTitle')),
        content: Text(l.text('deleteLearningEditionConfirmMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.text('deleteLearningEdition')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await widget.controller.deleteEdition(edition);
      if (success && mounted) {
        setState(() {
          _selectedReleaseId = widget.controller.adoptedEdition?.releaseId ??
              widget.controller.editions.firstOrNull?.releaseId;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editions = widget.controller.editions;
    final selected = editions.isEmpty
        ? null
        : editions.firstWhere(
            (e) => e.releaseId == _selectedReleaseId,
            orElse: () =>
                widget.controller.adoptedEdition ?? editions.first,
          );

    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: ListenRadii.panelBorder),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.contentColumnMax,
          maxHeight: 760,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(
              hasEditions: editions.isNotEmpty,
              generating: _generating,
              controller: widget.controller,
              onRegenerate: _regenerate,
              onImportPackage: _importPackage,
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  widget.controller,
                  ?widget.generationListenable,
                ]),
                builder: (context, _) => _LearningEditionBody(
                  controller: widget.controller,
                  selectedEdition: selected,
                  generating: _generating,
                  runView: widget.runView?.call(),
                  onSelectRelease: (releaseId) {
                    setState(() => _selectedReleaseId = releaseId);
                  },
                  onAdoptEdition: (edition) async {
                    await widget.controller.adopt(edition);
                    if (mounted) {
                      setState(() => _selectedReleaseId = edition.releaseId);
                    }
                  },
                  onGenerate: widget.onGenerate == null ? null : _generate,
                  onRegenerate: _regenerate,
                  onImportPackage: _importPackage,
                  onDeleteEdition: _deleteEdition,
                  onCancelGeneration: widget.onCancelGeneration,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.hasEditions,
    required this.generating,
    required this.controller,
    required this.onRegenerate,
    required this.onImportPackage,
  });

  final bool hasEditions;
  final bool generating;
  final LearningEditionController controller;
  final VoidCallback onRegenerate;
  final VoidCallback onImportPackage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: ListenPadding.row,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: ListenRadii.controlBorder,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: ListenIconSize.control,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.text('learningEdition'),
                  style: ListenType.emphasis.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  l.text('learningEditionSubtitle'),
                  style: ListenType.caption.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (hasEditions) ...[
            IconButton(
              key: const Key('learning-edition-regenerate'),
              tooltip: l.text('regenerateLearningEditionTooltip'),
              onPressed: generating || controller.busy ? null : onRegenerate,
              iconSize: ListenIconSize.control,
              color: colorScheme.onSurfaceVariant,
              icon: generating
                  ? const SizedBox(
                      width: ListenIconSize.inline,
                      height: ListenIconSize.inline,
                      child: ListenLoading.inline(),
                    )
                  : const Icon(Icons.auto_fix_high_outlined),
            ),
            IconButton(
              key: const Key('learning-edition-import'),
              tooltip: l.text('importLearningPackageTooltip'),
              onPressed:
                  generating || controller.busy ? null : onImportPackage,
              iconSize: ListenIconSize.control,
              color: colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.file_upload_outlined),
            ),
            IconButton(
              key: const Key('learning-edition-refresh'),
              tooltip: l.text('refresh'),
              onPressed: controller.loading || generating
                  ? null
                  : controller.refresh,
              iconSize: ListenIconSize.control,
              color: colorScheme.onSurfaceVariant,
              icon: const Icon(Icons.refresh),
            ),
          ],
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.pop(context),
            iconSize: ListenIconSize.control,
            color: colorScheme.onSurfaceVariant,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _LearningEditionBody extends StatelessWidget {
  const _LearningEditionBody({
    required this.controller,
    required this.selectedEdition,
    required this.generating,
    required this.runView,
    required this.onSelectRelease,
    required this.onAdoptEdition,
    required this.onGenerate,
    required this.onRegenerate,
    required this.onImportPackage,
    required this.onDeleteEdition,
    required this.onCancelGeneration,
  });

  final LearningEditionController controller;
  final LearningEdition? selectedEdition;
  final bool generating;
  final CapabilityRunView? runView;
  final ValueChanged<String> onSelectRelease;
  final Future<void> Function(LearningEdition edition) onAdoptEdition;
  final VoidCallback? onGenerate;
  final VoidCallback? onRegenerate;
  final VoidCallback? onImportPackage;
  final void Function(LearningEdition edition) onDeleteEdition;
  final Future<void> Function()? onCancelGeneration;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (controller.loading && controller.editions.isEmpty) {
      return const Center(child: ListenLoading());
    }
    if (controller.failed && controller.editions.isEmpty) {
      return _EditionMessage(
        icon: Icons.error_outline,
        message: l.text('learningEditionLoadFailed'),
        action: TextButton.icon(
          onPressed: controller.refresh,
          icon: const Icon(Icons.refresh),
          label: Text(l.text('retry')),
        ),
      );
    }
    if (controller.editions.isEmpty) {
      return _EditionMessage(
        icon: Icons.inventory_2_outlined,
        message: l.text('learningEditionEmpty'),
        action: Wrap(
          spacing: ListenSpacing.gap12,
          runSpacing: ListenSpacing.gap8,
          alignment: WrapAlignment.center,
          children: [
            if (onGenerate != null)
              FilledButton.icon(
                key: const Key('learning-edition-generate'),
                onPressed: generating ? null : onGenerate,
                icon: generating
                    ? const ListenLoading.inline()
                    : const Icon(Icons.auto_fix_high_outlined),
                label: Text(l.text('generateLearningMaterials')),
              ),
            OutlinedButton.icon(
              key: const Key('learning-edition-import-empty'),
              onPressed: generating || controller.busy ? null : onImportPackage,
              icon: const Icon(Icons.file_upload_outlined),
              label: Text(l.text('importLearningPackage')),
            ),
          ],
        ),
      );
    }

    final selected = selectedEdition ??
        controller.adoptedEdition ??
        controller.editions.first;

    return SingleChildScrollView(
      padding: ListenPadding.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (generating || (runView?.busy ?? false)) ...[
            _GenerationStatusCard(
              runView: runView,
              onCancel: onCancelGeneration,
            ),
            const SizedBox(height: ListenSpacing.gap16),
          ],
          _VersionControlCard(
            controller: controller,
            edition: selected,
            onSelectRelease: onSelectRelease,
            onAdoptEdition: onAdoptEdition,
            onDeleteEdition: onDeleteEdition,
          ),
          if (controller.failed) ...[
            const SizedBox(height: ListenSpacing.gap8),
            Text(
              l.text('learningEditionAdoptFailed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: ListenSpacing.gap16),
          _CapabilityMatrix(edition: selected),
          const SizedBox(height: ListenSpacing.gap16),
          _DialogFooterNote(
            generating: generating,
            controller: controller,
            onRegenerate: onRegenerate,
            onImportPackage: onImportPackage,
          ),
        ],
      ),
    );
  }
}

class _GenerationStatusCard extends StatelessWidget {
  const _GenerationStatusCard({
    required this.runView,
    required this.onCancel,
  });

  final CapabilityRunView? runView;
  final Future<void> Function()? onCancel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final phase = runView?.phase;
    final stageText = switch (phase) {
      CapabilityRunPhase.resolving => l.text('generationStage_resolving'),
      CapabilityRunPhase.generating =>
        runView?.stage != null && runView!.stage!.isNotEmpty
            ? '${l.text('generationStage_generating')} (${runView!.stage})'
            : l.text('generationStage_generating'),
      CapabilityRunPhase.installing => l.text('generationStage_installing'),
      CapabilityRunPhase.adopting => l.text('generationStage_adopting'),
      _ => l.text('generationStage_generating'),
    };

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: ListenRadii.surfaceBorder,
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      padding: ListenPadding.card,
      child: Row(
        children: [
          const SizedBox(
            width: ListenIconSize.control,
            height: ListenIconSize.control,
            child: ListenLoading.inline(),
          ),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stageText,
                  style: ListenType.emphasis.copyWith(
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                if (runView != null && runView!.warnings.isNotEmpty) ...[
                  const SizedBox(height: ListenSpacing.gap4),
                  Text(
                    runView!.warnings.last,
                    style: ListenType.caption.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onCancel != null)
            TextButton.icon(
              onPressed: () => unawaited(onCancel!()),
              icon: Icon(
                Icons.cancel_outlined,
                size: ListenIconSize.inline,
                color: colorScheme.error,
              ),
              label: Text(
                l.text('cancelGeneration'),
                style: TextStyle(color: colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

class _VersionControlCard extends StatelessWidget {
  const _VersionControlCard({
    required this.controller,
    required this.edition,
    required this.onSelectRelease,
    required this.onAdoptEdition,
    required this.onDeleteEdition,
  });

  final LearningEditionController controller;
  final LearningEdition edition;
  final ValueChanged<String> onSelectRelease;
  final Future<void> Function(LearningEdition edition) onAdoptEdition;
  final void Function(LearningEdition edition) onDeleteEdition;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    final availableCount = learningResourceKinds.where((kind) {
      return edition.baseResourceOfKind(kind)?.availability == 'available';
    }).length;
    final totalCount = learningResourceKinds.length;
    final progress = availableCount / totalCount;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: ListenRadii.surfaceBorder,
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
      ),
      padding: ListenPadding.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  key: const Key('learning-edition-selector'),
                  decoration: InputDecoration(
                    contentPadding: ListenPadding.tight,
                    isDense: true,
                    prefixIcon: const Icon(
                      Icons.layers_outlined,
                      size: ListenIconSize.control,
                    ),
                    suffixIcon: controller.adoptingReleaseId == null &&
                            controller.deletingReleaseId == null
                        ? null
                        : const Padding(
                            padding: ListenPadding.tight,
                            child: ListenLoading.inline(),
                          ),
                    border: const OutlineInputBorder(
                      borderRadius: ListenRadii.controlBorder,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: edition.releaseId,
                      isExpanded: true,
                      isDense: true,
                      items: [
                        for (final item in controller.editions)
                          DropdownMenuItem(
                            value: item.releaseId,
                            child: Text(
                              _editionLabel(context, l, item),
                              style: ListenType.body,
                            ),
                          ),
                      ],
                      onChanged: controller.busy
                          ? null
                          : (releaseId) {
                              if (releaseId == null) return;
                              onSelectRelease(releaseId);
                            },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              if (edition.adopted)
                Container(
                  padding: ListenPadding.tight,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: ListenRadii.pillBorder,
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check,
                        size: ListenIconSize.inline,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: ListenSpacing.gap4),
                      Text(
                        l.text('learningEditionInUse'),
                        style: ListenType.caption.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                FilledButton.tonalIcon(
                  key: const Key('learning-edition-adopt-btn'),
                  onPressed: controller.busy
                      ? null
                      : () => unawaited(onAdoptEdition(edition)),
                  icon: const Icon(Icons.check, size: ListenIconSize.inline),
                  label: Text(l.text('useLearningEdition')),
                ),
              const SizedBox(width: ListenSpacing.gap4),
              IconButton(
                key: const Key('learning-edition-delete-btn'),
                tooltip: edition.adopted
                    ? l.text('cannotDeleteAdoptedEdition')
                    : l.text('deleteLearningEditionTooltip'),
                onPressed: edition.adopted || controller.busy
                    ? null
                    : () => onDeleteEdition(edition),
                iconSize: ListenIconSize.control,
                color: edition.adopted
                    ? colorScheme.outline
                    : colorScheme.error,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap12),
          Row(
            children: [
              Text(
                '$availableCount / $totalCount',
                key: const Key('learning-resource-count'),
                style: ListenType.emphasis.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Text(
                  l
                      .text('learningEditionReadinessSummary')
                      .replaceAll('{ready}', '$availableCount')
                      .replaceAll('{total}', '$totalCount'),
                  style: ListenType.caption.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap6),
          ClipRRect(
            borderRadius: ListenRadii.pillBorder,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  static String _editionLabel(
    BuildContext context,
    AppLocalizations l,
    LearningEdition edition,
  ) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      edition.installedAtMs,
    );
    final date = MaterialLocalizations.of(context).formatShortDate(timestamp);
    final inUse = edition.adopted ? ' · ${l.text('learningEditionInUse')}' : '';
    return '${edition.title} · $date$inUse';
  }
}

class _CapabilityMatrix extends StatelessWidget {
  const _CapabilityMatrix({required this.edition});

  final LearningEdition edition;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CapabilitySection(
          title: l.text('learningResourceSection_foundation'),
          icon: Icons.article_outlined,
          iconColor: scheme.primary,
          kinds: const ['structured_reading', 'subtitle_text_track'],
          edition: edition,
        ),
        const SizedBox(height: ListenSpacing.gap12),
        _CapabilitySection(
          title: l.text('learningResourceSection_timing'),
          icon: Icons.timer_outlined,
          iconColor: scheme.secondary,
          kinds: const [
            'anchor_time_alignment',
            'word_timeline',
            'phone_timeline',
          ],
          edition: edition,
        ),
        const SizedBox(height: ListenSpacing.gap12),
        _CapabilitySection(
          title: l.text('learningResourceSection_linguistics'),
          icon: Icons.psychology_outlined,
          iconColor: scheme.tertiary,
          kinds: const [
            'sense_group_analysis',
            'word_acoustics',
            'prosody_analysis',
          ],
          edition: edition,
        ),
      ],
    );
  }
}

class _CapabilitySection extends StatelessWidget {
  const _CapabilitySection({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.kinds,
    required this.edition,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<String> kinds;
  final LearningEdition edition;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: ListenRadii.surfaceBorder,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      padding: ListenPadding.row,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: ListenIconSize.inline, color: iconColor),
              const SizedBox(width: ListenSpacing.gap6),
              Text(
                title,
                style: ListenType.emphasis.copyWith(
                  fontSize: 13,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '${kinds.length}',
                style: ListenType.caption.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: ListenSpacing.gap8),
          for (var i = 0; i < kinds.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
            _CapabilityRow(kind: kinds[i], edition: edition),
          ],
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({required this.kind, required this.edition});

  final String kind;
  final LearningEdition edition;

  static IconData _iconForKind(String kind) => switch (kind) {
    'structured_reading' => Icons.auto_stories_outlined,
    'subtitle_text_track' => Icons.subtitles_outlined,
    'anchor_time_alignment' => Icons.schedule_outlined,
    'word_timeline' => Icons.text_fields_outlined,
    'phone_timeline' => Icons.record_voice_over_outlined,
    'sense_group_analysis' => Icons.grain_outlined,
    'word_acoustics' => Icons.graphic_eq_outlined,
    'prosody_analysis' => Icons.tune_outlined,
    _ => Icons.widgets_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final resource = edition.baseResourceOfKind(kind);
    final available = resource?.availability == 'available';
    final missing = resource == null || resource.availability == 'missing';
    final colorScheme = Theme.of(context).colorScheme;

    final helpKey = 'learningResourceHelp_$kind';
    final helpText = l.hasKey(helpKey) ? l.text(helpKey) : null;

    return Padding(
      key: Key('learning-resource-$kind'),
      padding: ListenPadding.row,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: available
                  ? colorScheme.primaryContainer.withValues(alpha: 0.6)
                  : colorScheme.surfaceContainerHighest,
              borderRadius: ListenRadii.controlBorder,
            ),
            child: Icon(
              _iconForKind(kind),
              size: ListenIconSize.inline,
              color: available
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.text('learningResource_$kind'),
                  style: ListenType.body.copyWith(
                    fontWeight: available ? FontWeight.w600 : FontWeight.w400,
                    color: available
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (!available && helpText != null) ...[
            Tooltip(
              message: helpText,
              child: Icon(
                Icons.info_outline,
                size: ListenIconSize.inline,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: ListenSpacing.gap8),
          ],
          Container(
            padding: ListenPadding.tight,
            decoration: BoxDecoration(
              color: available
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              borderRadius: ListenRadii.pillBorder,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  available
                      ? Icons.check_circle
                      : missing
                          ? Icons.radio_button_unchecked
                          : Icons.block_outlined,
                  size: ListenIconSize.inline,
                  color: available
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: ListenSpacing.gap4),
                Text(
                  l.text(
                    available
                        ? 'learningResourceAvailable'
                        : missing
                            ? 'learningResourceMissing'
                            : 'learningResourceUnavailable',
                  ),
                  style: ListenType.caption.copyWith(
                    color: available
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogFooterNote extends StatelessWidget {
  const _DialogFooterNote({
    required this.generating,
    required this.controller,
    required this.onRegenerate,
    required this.onImportPackage,
  });

  final bool generating;
  final LearningEditionController controller;
  final VoidCallback? onRegenerate;
  final VoidCallback? onImportPackage;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(
          Icons.lightbulb_outline,
          size: ListenIconSize.inline,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: ListenSpacing.gap8),
        Expanded(
          child: Text(
            l.text('learningEditionFooterNote'),
            style: ListenType.caption.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: ListenSpacing.gap12),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}

class _EditionMessage extends StatelessWidget {
  const _EditionMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: ListenPadding.page,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ListenIconSize.illustration),
          const SizedBox(height: ListenSpacing.gap12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: ListenSpacing.gap16),
            action!,
          ],
        ],
      ),
    ),
  );
}
