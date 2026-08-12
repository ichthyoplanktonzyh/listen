import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/document_session_controller.dart';
import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../models/document_session.dart';
import '../../models/learning_material.dart';
import '../../services/document_decoding/document_format.dart';
import '../../services/document_decoding/epub_decoder.dart';
import '../../services/document_decoding/html_parser_restricted.dart';
import '../../services/document_decoding/markdown_parser.dart';
import '../../services/document_source_resolver.dart';
import '../../theme/breakpoints.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../common/api_failure_disclosure.dart';
import '../common/listen_error_state.dart';
import '../common/listen_loading.dart';
import 'document_block_view.dart';
import 'document_epub_view.dart';
import 'document_pdf_view.dart';

/// Renders the current [DocumentSessionState]. Reusable and pure: it emits
/// intent through the controller's methods and renders nothing but state.
class DocumentSessionView extends StatelessWidget {
  const DocumentSessionView({super.key, required this.controller});

  final DocumentSessionController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => switch (controller.state) {
        DocumentSessionIdle() => _IdlePane(
          onChooseFile: () => unawaited(controller.openFile()),
          onPaste: (title, body) =>
              unawaited(controller.openPastedText(title: title, body: body)),
        ),
        DocumentSessionOpening() => Center(
          child: ListenLoading(label: l.text('documentOpening')),
        ),
        DocumentSessionChoosingAsset(
          :final details,
          :final documentRenditions,
        ) => _ChoosingAssetPane(
          title: details.currentRevision.title,
          documentRenditions: documentRenditions,
          onChoose: controller.chooseDocumentAsset,
        ),
        DocumentSessionReady(
          :final details,
          :final documentRendition,
          :final sourceAsset,
          :final capabilities,
          :final format,
          :final isRetained,
          :final retentionInFlight,
          :final retentionFailure,
        ) => _ReadyPane(
          title: details.currentRevision.title,
          text: documentRendition?.text,
          format: format,
          sourceAsset: sourceAsset,
          capabilities: capabilities,
          resolveBytes: controller.resolveSourceBytes,
          isRetained: isRetained,
          retentionInFlight: retentionInFlight,
          retentionFailure: retentionFailure,
          onKeep: () => unawaited(controller.retain()),
          onUnkeep: () => unawaited(controller.unretain()),
        ),
        DocumentSessionFailed(:final failure) => _FailedPane(
          failure: failure,
          onRetry: () => unawaited(controller.retry()),
          onBack: controller.close,
        ),
      },
    );
  }
}

class _IdlePane extends StatefulWidget {
  const _IdlePane({required this.onChooseFile, required this.onPaste});

  final VoidCallback onChooseFile;
  final void Function(String title, String body) onPaste;

  @override
  State<_IdlePane> createState() => _IdlePaneState();
}

class _IdlePaneState extends State<_IdlePane> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _showPasteForm = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: ListenPadding.pageCompact,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.wideColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.text('documentSessionIdleTitle'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                l.text('documentSessionIdleBody'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap16),
              FilledButton.icon(
                onPressed: widget.onChooseFile,
                icon: const Icon(Icons.description_outlined),
                label: Text(l.text('chooseTextFile')),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _showPasteForm = !_showPasteForm),
                icon: Icon(
                  _showPasteForm
                      ? Icons.expand_less
                      : Icons.content_paste_outlined,
                  size: ListenIconSize.control,
                ),
                label: Text(l.text('pasteText')),
              ),
              if (_showPasteForm) ...[
                const SizedBox(height: ListenSpacing.gap16),
                TextField(
                  controller: _title,
                  decoration: InputDecoration(
                    labelText: l.text('pasteTextTitle'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap8),
                TextField(
                  controller: _body,
                  minLines: 6,
                  maxLines: 14,
                  keyboardType: TextInputType.multiline,
                  decoration: InputDecoration(
                    labelText: l.text('pasteTextBody'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: ListenSpacing.gap12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () {
                      widget.onPaste(_title.text, _body.text);
                    },
                    child: Text(l.text('pasteTextOpen')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoosingAssetPane extends StatelessWidget {
  const _ChoosingAssetPane({
    required this.title,
    required this.documentRenditions,
    required this.onChoose,
  });

  final String title;
  final List<DocumentRendition> documentRenditions;
  final void Function(String assetId) onChoose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: ListenPadding.pageCompact,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.wideColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: ListenSpacing.gap8),
              Text(
                l.text('documentChooseAssetHint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: ListenSpacing.gap12),
              for (final rendition in documentRenditions) ...[
                _DocumentAssetTile(
                  rendition: rendition,
                  onChoose: () => onChoose(rendition.id),
                ),
                const SizedBox(height: ListenSpacing.gap6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One selectable document rendition. [ListTile]'s focus traversal makes the
/// choice keyboard-operable; the internal rendition id is never shown.
class _DocumentAssetTile extends StatelessWidget {
  const _DocumentAssetTile({required this.rendition, required this.onChoose});

  final DocumentRendition rendition;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final language = rendition.language;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: ListenRadii.controlBorder,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onChoose,
        leading: Icon(
          Icons.description_outlined,
          color: colors.onSurfaceVariant,
        ),
        title: Text(
          language == null
              ? l.text('documentAssetUntagged')
              : l
                    .text('documentAssetLanguage')
                    .replaceAll('{language}', language),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_formatBytes(rendition.textByteSize, l)} · ${_preview(rendition.text)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(
          Icons.chevron_right,
          size: ListenIconSize.control,
          color: colors.onSurfaceVariant,
        ),
      ),
    );
  }

  String _preview(String text) {
    const limit = 120;
    final flat = text.replaceAll('\n', ' ');
    if (flat.length <= limit) return flat;
    return '${flat.substring(0, limit)}…';
  }
}

class _ReadyPane extends StatefulWidget {
  const _ReadyPane({
    required this.title,
    required this.text,
    required this.format,
    required this.sourceAsset,
    required this.capabilities,
    required this.resolveBytes,
    required this.isRetained,
    required this.retentionInFlight,
    required this.retentionFailure,
    required this.onKeep,
    required this.onUnkeep,
  });

  final String title;

  /// The inline rendition text, or null when the source carries no text layer.
  final String? text;
  final DocumentFormat format;

  /// The Source Asset backing the direct view; null only when the revision
  /// carries none (defensive: every session-created material has one).
  final SourceAsset? sourceAsset;

  /// The durable capability projection, or null while loading/absent.
  final List<MaterialCapabilityProjection>? capabilities;
  final Future<DocumentSourceBytes> Function(SourceAsset asset) resolveBytes;

  final bool isRetained;
  final bool retentionInFlight;
  final ApiFailure? retentionFailure;
  final VoidCallback onKeep;
  final VoidCallback onUnkeep;

  @override
  State<_ReadyPane> createState() => _ReadyPaneState();
}

class _ReadyPaneState extends State<_ReadyPane> {
  DocumentSourceBytes? _bytes;
  bool _bytesLoading = false;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(_ReadyPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceAsset != widget.sourceAsset ||
        oldWidget.format != widget.format) {
      _resolveIfNeeded();
    }
  }

  bool get _needsBytes => switch (widget.format) {
    DocumentFormat.epub || DocumentFormat.pdf => true,
    _ => false,
  };

  void _resolveIfNeeded() {
    if (!_needsBytes) return;
    final asset = widget.sourceAsset;
    if (asset == null) {
      setState(() => _bytes = const DocumentSourceUnavailable());
      return;
    }
    if (_bytesLoading) return;
    _bytesLoading = true;
    setState(() => _bytes = null);
    unawaited(_resolve(asset));
  }

  Future<void> _resolve(SourceAsset asset) async {
    final result = await widget.resolveBytes(asset);
    if (!mounted) return;
    setState(() {
      _bytes = result;
      _bytesLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final failure = widget.retentionFailure;
    return SingleChildScrollView(
      padding: ListenPadding.pageCompact,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          // A reading measure, not a media column: the cap is `contentColumnMax`
          // so lines stay legible on a wide window (charter principle 5).
          constraints: const BoxConstraints(
            maxWidth: ListenBreakpoints.contentColumnMax,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: ListenSpacing.gap4),
                        Text(
                          widget.isRetained
                              ? l.text('retentionRetainedLabel')
                              : l.text('documentTemporary'),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: ListenSpacing.gap12),
                  if (widget.retentionInFlight)
                    const ListenLoading.inline()
                  else if (widget.isRetained)
                    OutlinedButton(
                      onPressed: widget.onUnkeep,
                      child: Text(l.text('retentionUnkeepAction')),
                    )
                  else
                    FilledButton(
                      onPressed: widget.onKeep,
                      child: Text(l.text('retentionKeepAction')),
                    ),
                ],
              ),
              if (failure != null) ...[
                const SizedBox(height: ListenSpacing.gap8),
                ListenErrorNotice(message: l.text('documentRetentionFailed')),
                ApiFailureDisclosure(failure: failure),
              ],
              if (widget.capabilities != null) ...[
                const SizedBox(height: ListenSpacing.gap12),
                _CapabilityStrip(
                  capabilities: widget.capabilities!,
                ),
              ],
              const SizedBox(height: ListenSpacing.gap16),
              ..._body(l),
            ],
          ),
        ),
      ),
    );
  }

  /// The direct document view, dispatched by format. Text-family formats
  /// render the rendition's exact text; container formats render the exact
  /// source bytes (missing referenced location = honest unavailable fact).
  List<Widget> _body(AppLocalizations l) {
    if (!_needsBytes) {
      return switch (widget.format) {
        DocumentFormat.plainText => [
          // The exact source text, selectable, line breaks and trailing
          // spaces preserved. No fabricated cues or paragraphs.
          SelectionArea(child: SelectableText(widget.text ?? '')),
        ],
        DocumentFormat.markdown => [
          DocumentBlockView(
            document: const MarkdownParser().parse(widget.text ?? ''),
          ),
        ],
        DocumentFormat.html => [
          DocumentBlockView(
            document: RestrictedHtmlParser().parse(widget.text ?? ''),
          ),
        ],
        _ => throw StateError('unreachable: non-byte formats handled above'),
      };
    }
    if (_bytesLoading) return const [Center(child: ListenLoading.inline())];
    final bytes = _bytes;
    if (bytes is! DocumentSourceAvailable || bytes.bytes.isEmpty) {
      return [ListenErrorNotice(message: l.text('documentSourceUnavailable'))];
    }
    return switch (widget.format) {
      DocumentFormat.epub => [
        DocumentEpubView(epub: EpubDecoder().decode(bytes.bytes)),
      ],
      DocumentFormat.pdf => [DocumentPdfView(bytes: bytes.bytes)],
      _ => throw StateError('unreachable: byte formats handled above'),
    };
  }
}

/// The capability summary of the open material: one honest status per
/// capability, read off the Core projection. A failed attempt is shown as
/// evidence, never as a broken document.
class _CapabilityStrip extends StatelessWidget {
  const _CapabilityStrip({required this.capabilities});

  final List<MaterialCapabilityProjection> capabilities;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final ordered = [
      for (final capability in [
        MaterialCapability.read,
        MaterialCapability.listen,
        MaterialCapability.watch,
      ])
        for (final projection in capabilities)
          if (projection.capability == capability) projection,
    ];
    if (ordered.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: ListenSpacing.gap8,
      runSpacing: ListenSpacing.gap8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final projection in ordered)
          _CapabilityChip(
            label: l.text('capability${_capabilityName(projection.capability)}'),
            status: l.text('capabilityStatus${_statusName(projection.status)}'),
            failed: projection.status == MaterialCapabilityStatus.failedAttempt,
            colors: colors,
          ),
      ],
    );
  }

  static String _capabilityName(MaterialCapability capability) =>
      switch (capability) {
        MaterialCapability.read => 'Read',
        MaterialCapability.listen => 'Listen',
        MaterialCapability.watch => 'Watch',
        MaterialCapability.synchronizedReadListen => 'SynchronizedReadListen',
      };

  static String _statusName(MaterialCapabilityStatus status) => switch (status) {
    MaterialCapabilityStatus.available => 'Available',
    MaterialCapabilityStatus.derivable => 'Derivable',
    MaterialCapabilityStatus.generating => 'Generating',
    MaterialCapabilityStatus.unavailable => 'Unavailable',
    MaterialCapabilityStatus.failedAttempt => 'FailedAttempt',
  };
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.label,
    required this.status,
    required this.failed,
    required this.colors,
  });

  final String label;
  final String status;
  final bool failed;
  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ListenSpacing.gap12,
        vertical: ListenSpacing.gap4,
      ),
      decoration: BoxDecoration(
        color: failed ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: ListenRadii.pillBorder,
      ),
      child: Text(
        '$label · $status',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: failed ? colors.onErrorContainer : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _FailedPane extends StatelessWidget {
  const _FailedPane({
    required this.failure,
    required this.onRetry,
    required this.onBack,
  });

  final DocumentSessionFailure failure;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final message = switch (failure.kind) {
      DocumentSessionFailureKind.coreUnavailable => l.text(
        'documentFailedCoreUnavailable',
      ),
      DocumentSessionFailureKind.tooLarge => l.text('documentFailedTooLarge'),
      DocumentSessionFailureKind.invalidUtf8 => l.text(
        'documentFailedInvalidUtf8',
      ),
      DocumentSessionFailureKind.emptyDocument => l.text('documentFailedEmpty'),
      DocumentSessionFailureKind.unreadable => l.text(
        'documentFailedUnreadable',
      ),
      DocumentSessionFailureKind.unsupported => l.text(
        'documentFailedUnsupported',
      ),
      DocumentSessionFailureKind.corrupt => l.text('documentFailedCorrupt'),
      DocumentSessionFailureKind.encrypted => l.text(
        'documentFailedEncrypted',
      ),
      DocumentSessionFailureKind.missingTitle => l.text(
        'documentFailedMissingTitle',
      ),
      DocumentSessionFailureKind.apiFailure => l.text('documentFailedApi'),
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.noticeColumnMax,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: ListenIconSize.illustration,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: ListenSpacing.gap12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: ListenSpacing.gap16),
            Wrap(
              spacing: ListenSpacing.gap8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onBack,
                  child: Text(l.text('documentBack')),
                ),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(l.text('documentRetry')),
                ),
              ],
            ),
            if (failure.apiFailure != null)
              ApiFailureDisclosure(failure: failure.apiFailure!),
          ],
        ),
      ),
    );
  }
}

/// Compact byte-size label for a document asset (≤ 1 MiB by intake policy).
String _formatBytes(int size, AppLocalizations l) {
  if (size >= 1024 * 1024) {
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} ${l.text('unitMegabytes')}';
  }
  if (size >= 1024) {
    return '${(size / 1024).toStringAsFixed(1)} ${l.text('unitKilobytes')}';
  }
  return '$size ${l.text('unitBytes')}';
}
