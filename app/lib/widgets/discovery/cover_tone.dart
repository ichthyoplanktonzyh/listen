import 'package:flutter/material.dart';

import '../../models/discovery.dart';

/// Maps a channel cover tone onto the active color scheme so cover artwork
/// follows the app's brightness without owning new palette colors.
Color discoveryCoverTone(BuildContext context, ChannelCoverTone tone) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    ChannelCoverTone.green => scheme.primaryContainer,
    ChannelCoverTone.amber => scheme.secondaryContainer,
    ChannelCoverTone.blue => scheme.tertiaryContainer,
    ChannelCoverTone.slate => scheme.surfaceContainerHighest,
    ChannelCoverTone.rose => scheme.errorContainer,
  };
}

/// Readable foreground for text drawn on [discoveryCoverTone].
Color discoveryCoverInk(BuildContext context, ChannelCoverTone tone) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    ChannelCoverTone.green => scheme.onPrimaryContainer,
    ChannelCoverTone.amber => scheme.onSecondaryContainer,
    ChannelCoverTone.blue => scheme.onTertiaryContainer,
    ChannelCoverTone.slate => scheme.onSurface,
    ChannelCoverTone.rose => scheme.onErrorContainer,
  };
}
