import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/content_package_journey_view_model.dart';
import '../localization.dart';
import '../models/content_package.dart';
import '../theme/icon_size.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import '../widgets/common/api_failure_disclosure.dart';
import '../widgets/common/listen_loading.dart';

class ContentPackageJourneyScreen extends StatelessWidget {
  const ContentPackageJourneyScreen({super.key, required this.viewModel});

  final ContentPackageJourneyViewModel viewModel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      final state = viewModel.state;
      final l = AppLocalizations.of(context);
      return Scaffold(
        appBar: AppBar(title: Text(l.text('contentPackageTitle'))),
        body: SafeArea(
          child: ListView(
            padding: ListenPadding.pageCompact,
            children: [
              Text(
                l.text('contentPackageIntro'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: ListenSpacing.gap16),
              Wrap(
                spacing: ListenSpacing.gap8,
                runSpacing: ListenSpacing.gap8,
                children: [
                  FilledButton.icon(
                    key: const Key('choose-content-package'),
                    onPressed: state.busy
                        ? null
                        : () => unawaited(viewModel.chooseAndImportPackage()),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(l.text('chooseContentPackage')),
                  ),
                  OutlinedButton.icon(
                    key: const Key('generate-content-package'),
                    onPressed: state.busy || !viewModel.generatorConfigured
                        ? null
                        : () => unawaited(viewModel.generateAndImport()),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: Text(l.text('generateContentPackage')),
                  ),
                  if (viewModel.canCancel)
                    TextButton(
                      key: const Key('cancel-content-package'),
                      onPressed: viewModel.cancel,
                      child: Text(l.text('cancel')),
                    ),
                ],
              ),
              if (!viewModel.generatorConfigured) ...[
                const SizedBox(height: ListenSpacing.gap8),
                Text(
                  l.text('contentPackageGeneratorUnavailable'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: ListenSpacing.gap24),
              Semantics(
                liveRegion: true,
                label: l.text('contentPackageProgress'),
                child: _JourneyStatus(state: state),
              ),
              if (_unknownGeneratorPhase(state.generatorPhase))
                _TechnicalTextDisclosure(
                  details: 'phase=${state.generatorPhase}',
                ),
              if (viewModel.canRetry) ...[
                const SizedBox(height: ListenSpacing.gap12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    key: const Key('retry-content-package'),
                    onPressed: () => unawaited(viewModel.retry()),
                    icon: const Icon(Icons.refresh),
                    label: Text(l.text('retry')),
                  ),
                ),
              ],
              if (state.receipt case final receipt?) ...[
                const SizedBox(height: ListenSpacing.gap24),
                _ReceiptView(
                  receipt: receipt,
                  archiveSha256: state.archiveSha256,
                  viewModel: viewModel,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _JourneyStatus extends StatelessWidget {
  const _JourneyStatus({required this.state});

  final ContentPackageJourneyState state;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final message = switch (state.phase) {
      ContentPackageJourneyPhase.idle => l.text('contentPackageIdle'),
      ContentPackageJourneyPhase.preparing => l.text('contentPackagePreparing'),
      ContentPackageJourneyPhase.generating =>
        l
            .text('contentPackageGenerating')
            .replaceAll(
              '{phase}',
              _generatorPhaseLabel(l, state.generatorPhase),
            ),
      ContentPackageJourneyPhase.importing => l.text('contentPackageImporting'),
      ContentPackageJourneyPhase.candidateReady => l.text(
        'contentPackageCandidateReady',
      ),
      ContentPackageJourneyPhase.fingerprintMismatch => l.text(
        'contentPackageFingerprintMismatch',
      ),
      ContentPackageJourneyPhase.failed => l.text('contentPackageFailed'),
      ContentPackageJourneyPhase.cancelled => l.text('contentPackageCancelled'),
      ContentPackageJourneyPhase.retrying => l.text('contentPackageRetrying'),
    };
    if (state.phase == ContentPackageJourneyPhase.failed ||
        state.phase == ContentPackageJourneyPhase.fingerprintMismatch) {
      return ApiFailureNotice(message: message, failure: state.failure);
    }
    if (state.busy) {
      return Row(
        children: [
          const ListenLoading(size: ListenIconSize.chrome),
          const SizedBox(width: ListenSpacing.gap12),
          Expanded(child: Text(message)),
        ],
      );
    }
    return Text(message);
  }
}

String _generatorPhaseLabel(AppLocalizations l, String? phase) =>
    switch (phase) {
      null => l.text('contentPackageStarting'),
      'validating' => l.text('contentPackagePhaseValidating'),
      'probing_media' => l.text('contentPackagePhaseProbing'),
      'normalizing_audio' => l.text('contentPackagePhaseNormalizing'),
      'transcribing' => l.text('contentPackagePhaseTranscribing'),
      'building_package' => l.text('contentPackagePhaseBuilding'),
      _ => l.text('contentPackagePhaseWorking'),
    };

bool _unknownGeneratorPhase(String? phase) =>
    phase != null &&
    !const {
      'validating',
      'probing_media',
      'normalizing_audio',
      'transcribing',
      'building_package',
    }.contains(phase);

class _ReceiptView extends StatelessWidget {
  const _ReceiptView({
    required this.receipt,
    required this.archiveSha256,
    required this.viewModel,
  });

  final ContentPackageImportReceipt receipt;
  final String? archiveSha256;
  final ContentPackageJourneyViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: ListenRadii.panelBorder,
      ),
      child: Padding(
        padding: ListenPadding.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.text('contentPackageReceipt'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: ListenSpacing.gap8),
            SelectableText(
              '${l.text('contentPackageManifestDigest')}: '
              '${receipt.manifestSha256}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (archiveSha256 case final digest?) ...[
              const SizedBox(height: ListenSpacing.gap4),
              SelectableText(
                '${l.text('contentPackageArchiveDigest')}: $digest',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: ListenSpacing.gap12),
            Wrap(
              spacing: ListenSpacing.gap8,
              runSpacing: ListenSpacing.gap4,
              children: [
                _FactChip(label: l.text('contentPackageUnsignedLocal')),
                _FactChip(label: l.text('contentPackagePublisherUnknown')),
                _FactChip(label: l.text('contentPackageReviewUnknown')),
                _FactChip(label: l.text('contentPackageLicenseUnknown')),
              ],
            ),
            if (receipt.warnings.isNotEmpty) ...[
              const SizedBox(height: ListenSpacing.gap12),
              Text(
                l.text('contentPackageWarnings'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final warning in receipt.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: ListenSpacing.gap4),
                  child: Text('• $warning'),
                ),
            ],
            const SizedBox(height: ListenSpacing.gap16),
            for (final resource in receipt.resources)
              Padding(
                padding: const EdgeInsets.only(bottom: ListenSpacing.gap8),
                child: _ResourceReceiptRow(
                  resource: resource,
                  receipt: receipt,
                  viewModel: viewModel,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResourceReceiptRow extends StatelessWidget {
  const _ResourceReceiptRow({
    required this.resource,
    required this.receipt,
    required this.viewModel,
  });

  final ContentPackageResourceDisposition resource;
  final ContentPackageImportReceipt receipt;
  final ContentPackageJourneyViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final state = viewModel.state;
    final canAct = resource.outcome == 'consumed';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: ListenRadii.controlBorder,
      ),
      child: Padding(
        padding: ListenPadding.row,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.dataset_outlined,
                  size: ListenIconSize.control,
                ),
                const SizedBox(width: ListenSpacing.gap8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_resourceKindLabel(l, resource.kind)),
                      const SizedBox(height: ListenSpacing.gap2),
                      Text(
                        [
                          _resourceOutcomeLabel(l, resource.outcome),
                          if (resource.reason != null)
                            _resourceReasonLabel(l, resource.reason!),
                          _reviewStatusLabel(l, resource.reviewStatus),
                          resource.provenance?.tool.label ??
                              l.text('contentPackageProvenanceUnknown'),
                          if (resource.provenance?.provider
                              case final provider?)
                            provider.label,
                          if (resource.provenance?.model case final model?)
                            model.label,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _WireDetailDisclosure(resource: resource),
            Wrap(
              spacing: ListenSpacing.gap8,
              runSpacing: ListenSpacing.gap4,
              children: [
                if (resource.kind == 'subtitle_text_track' && canAct)
                  TextButton(
                    key: const Key('select-imported-subtitle'),
                    onPressed: state.selectedTrackId == receipt.track.id
                        ? null
                        : () => unawaited(viewModel.selectImportedSubtitle()),
                    child: Text(
                      state.selectedTrackId == receipt.track.id
                          ? l.text('contentPackageSelected')
                          : l.text('contentPackageSelectSubtitle'),
                    ),
                  ),
                if (resource.kind == 'word_timeline' && canAct)
                  for (final localId in resource.localIds)
                    TextButton(
                      key: Key('activate-word-timeline-$localId'),
                      onPressed:
                          state.activatedWordTimelineIds.contains(localId)
                          ? null
                          : () => unawaited(
                              viewModel.activateImportedWordTimeline(localId),
                            ),
                      child: Text(
                        state.activatedWordTimelineIds.contains(localId)
                            ? l.text('contentPackageActivated')
                            : l.text('contentPackageActivateWordTimeline'),
                      ),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WireDetailDisclosure extends StatelessWidget {
  const _WireDetailDisclosure({required this.resource});

  final ContentPackageResourceDisposition resource;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        AppLocalizations.of(context).text('contentPackageTechnicalDetails'),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            [
              'kind=${resource.kind}',
              'outcome=${resource.outcome}',
              if (resource.reason case final reason?) 'reason=$reason',
              if (resource.localIds.isNotEmpty)
                'local_ids=${resource.localIds.join(',')}',
            ].join('\n'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _TechnicalTextDisclosure extends StatelessWidget {
  const _TechnicalTextDisclosure({required this.details});

  final String details;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(
        AppLocalizations.of(context).text('contentPackageTechnicalDetails'),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            details,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

String _resourceKindLabel(AppLocalizations l, String kind) => switch (kind) {
  'subtitle_text_track' => l.text('contentPackageKindSubtitle'),
  'word_timeline' => l.text('contentPackageKindWordTimeline'),
  _ => l.text('contentPackageKindOther'),
};

String _resourceOutcomeLabel(AppLocalizations l, String outcome) =>
    switch (outcome) {
      'consumed' => l.text('contentPackageOutcomeImported'),
      'preserved_not_consumed' => l.text('contentPackageOutcomePreserved'),
      _ => l.text('contentPackageOutcomeUnknown'),
    };

String _resourceReasonLabel(AppLocalizations l, String reason) =>
    switch (reason) {
      'already_imported' => l.text('contentPackageReasonAlreadyImported'),
      _ => l.text('contentPackageReasonOther'),
    };

String _reviewStatusLabel(AppLocalizations l, String? status) =>
    switch (status) {
      'unreviewed' => l.text('contentPackageReviewUnreviewed'),
      'machine_checked' => l.text('contentPackageReviewMachineChecked'),
      'human_reviewed' => l.text('contentPackageReviewHumanReviewed'),
      _ => l.text('contentPackageReviewUnknown'),
    };

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Chip(label: Text(label));
}
