import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../models/discovery.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'cover_tone.dart';
import 'discovery_preview_shell.dart';

/// One selectable media source.
class DiscoverySourceTile extends StatelessWidget {
  const DiscoverySourceTile({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final MediaSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tileColor = selected
        ? scheme.surfaceContainerHigh
        : Colors.transparent;
    return Material(
      color: tileColor,
      borderRadius: ListenRadii.controlBorder,
      child: InkWell(
        borderRadius: ListenRadii.controlBorder,
        onTap: onTap,
        child: Padding(
          padding: ListenPadding.row,
          child: Row(
            children: [
              _SourceMark(source: source),
              const SizedBox(width: ListenSpacing.gap8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      source.language,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _coverInitial(String text) {
  if (text.isEmpty) return '?';
  return text.characters.first.toUpperCase();
}

class _SourceMark extends StatelessWidget {
  const _SourceMark({required this.source});

  final MediaSource source;

  @override
  Widget build(BuildContext context) {
    final background = discoveryCoverTone(context, source.cover);
    final ink = discoveryCoverInk(context, source.cover);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: ListenRadii.controlBorder,
      ),
      child: Text(
        _coverInitial(source.name),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

@Preview(name: 'Source tile', group: 'Discovery', size: Size(240, 64))
Widget discoverySourceTilePreview() => discoveryPreviewShell(
  const Padding(
    padding: EdgeInsets.all(12),
    child: DiscoverySourceTile(
      source: MediaSource(
        id: 'c-preview',
        name: 'BBC Learning English',
        language: 'English',
        description: '',
        cover: ChannelCoverTone.blue,
        type: MediaSourceType.youtube,
        avatarUrl: null,
      ),
      selected: true,
      onTap: _noop,
    ),
  ),
  width: 240,
  height: 64,
);

void _noop() {}
