import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/learning_edition_controller.dart';
import '../../localization.dart';
import '../../models/learning_edition.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
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
  Listenable? generationListenable,
  bool Function()? isGenerating,
}) {
  unawaited(controller.load(materialId));
  return showDialog<void>(
    context: context,
    builder: (_) => LearningEditionDialog(
      controller: controller,
      onGenerate: onGenerate,
      generationListenable: generationListenable,
      isGenerating: isGenerating,
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
    this.generationListenable,
    this.isGenerating,
  });

  final LearningEditionController controller;
  final Future<void> Function()? onGenerate;
  final Listenable? generationListenable;
  final bool Function()? isGenerating;

  @override
  State<LearningEditionDialog> createState() => _LearningEditionDialogState();
}

class _LearningEditionDialogState extends State<LearningEditionDialog> {
  bool _generationCallPending = false;

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.contentColumnMax,
          maxHeight: 720,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: ListenPadding.card,
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: ListenSpacing.gap12),
                  Expanded(
                    child: Text(
                      l.text('learningEdition'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Flexible(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  widget.controller,
                  ?widget.generationListenable,
                ]),
                builder: (context, _) => _LearningEditionBody(
                  controller: widget.controller,
                  generating: _generating,
                  onGenerate: widget.onGenerate == null ? null : _generate,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LearningEditionBody extends StatelessWidget {
  const _LearningEditionBody({
    required this.controller,
    required this.generating,
    required this.onGenerate,
  });

  final LearningEditionController controller;
  final bool generating;
  final VoidCallback? onGenerate;

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
        action: onGenerate == null
            ? null
            : FilledButton.icon(
                key: const Key('learning-edition-generate'),
                onPressed: generating ? null : onGenerate,
                icon: generating
                    ? const ListenLoading.inline()
                    : const Icon(Icons.auto_fix_high_outlined),
                label: Text(l.text('generateLearningMaterials')),
              ),
      );
    }

    final selected = controller.adoptedEdition ?? controller.editions.first;
    return SingleChildScrollView(
      padding: ListenPadding.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.text('learningEditionCurrent'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: ListenSpacing.gap8),
          InputDecorator(
            key: const Key('learning-edition-selector'),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.layers_outlined),
              suffixIcon: controller.adoptingReleaseId == null
                  ? null
                  : const Padding(
                      padding: ListenPadding.tight,
                      child: ListenLoading.inline(),
                    ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected.releaseId,
                isExpanded: true,
                isDense: true,
                items: [
                  for (final edition in controller.editions)
                    DropdownMenuItem(
                      value: edition.releaseId,
                      child: Text(_editionLabel(context, l, edition)),
                    ),
                ],
                onChanged: controller.adoptingReleaseId != null
                    ? null
                    : (releaseId) {
                        if (releaseId == null) return;
                        final edition = controller.editions.singleWhere(
                          (candidate) => candidate.releaseId == releaseId,
                        );
                        unawaited(controller.adopt(edition));
                      },
              ),
            ),
          ),
          if (!selected.adopted) ...[
            const SizedBox(height: ListenSpacing.gap8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: controller.adoptingReleaseId == null
                    ? () => unawaited(controller.adopt(selected))
                    : null,
                child: Text(l.text('useLearningEdition')),
              ),
            ),
          ],
          if (controller.failed) ...[
            const SizedBox(height: ListenSpacing.gap8),
            Text(
              l.text('learningEditionAdoptFailed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: ListenSpacing.gap16),
          _EditionSummary(edition: selected),
          const SizedBox(height: ListenSpacing.gap16),
          _ResourceGroup(
            title: l.text('learningResourceContent'),
            kinds: learningResourceKinds.sublist(0, 2),
            edition: selected,
          ),
          const SizedBox(height: ListenSpacing.gap12),
          _ResourceGroup(
            title: l.text('learningResourceTiming'),
            kinds: learningResourceKinds.sublist(2, 5),
            edition: selected,
          ),
          const SizedBox(height: ListenSpacing.gap12),
          _ResourceGroup(
            title: l.text('learningResourceAnalysis'),
            kinds: learningResourceKinds.sublist(5),
            edition: selected,
          ),
          const SizedBox(height: ListenSpacing.gap16),
          Row(
            children: [
              TextButton.icon(
                onPressed: controller.loading ? null : controller.refresh,
                icon: const Icon(Icons.refresh),
                label: Text(l.text('refresh')),
              ),
            ],
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

class _EditionSummary extends StatelessWidget {
  const _EditionSummary({required this.edition});

  final LearningEdition edition;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final available = learningResourceKinds.where((kind) {
      return edition.baseResourceOfKind(kind)?.availability == 'available';
    }).length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: ListenRadii.surfaceBorder,
      ),
      child: Padding(
        padding: ListenPadding.card,
        child: Row(
          children: [
            Icon(
              available == learningResourceKinds.length
                  ? Icons.check_circle_outline
                  : Icons.pending_outlined,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: ListenSpacing.gap12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$available / ${learningResourceKinds.length}',
                    key: const Key('learning-resource-count'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    l.text('learningEditionResourceSummary'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            if (edition.adopted)
              Chip(
                avatar: const Icon(Icons.check, size: ListenIconSize.control),
                label: Text(l.text('learningEditionInUse')),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResourceGroup extends StatelessWidget {
  const _ResourceGroup({
    required this.title,
    required this.kinds,
    required this.edition,
  });

  final String title;
  final List<String> kinds;
  final LearningEdition edition;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: ListenSpacing.gap6),
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: ListenRadii.surfaceBorder,
        ),
        child: Column(
          children: [
            for (var index = 0; index < kinds.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              _ResourceRow(kind: kinds[index], edition: edition),
            ],
          ],
        ),
      ),
    ],
  );
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({required this.kind, required this.edition});

  final String kind;
  final LearningEdition edition;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final resource = edition.baseResourceOfKind(kind);
    final available = resource?.availability == 'available';
    final missing = resource == null || resource.availability == 'missing';
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: Key('learning-resource-$kind'),
      padding: ListenPadding.row,
      child: Row(
        children: [
          Icon(
            available
                ? Icons.check_circle
                : missing
                ? Icons.radio_button_unchecked
                : Icons.block_outlined,
            size: ListenIconSize.control,
            color: available ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: ListenSpacing.gap8),
          Expanded(child: Text(l.text('learningResource_$kind'))),
          Text(
            l.text(
              available
                  ? 'learningResourceAvailable'
                  : missing
                  ? 'learningResourceMissing'
                  : 'learningResourceUnavailable',
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: available ? colors.primary : colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
