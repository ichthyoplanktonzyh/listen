import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/content_channel.dart';
import '../../theme/icon_size.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

class ContentChannelAvailability {
  const ContentChannelAvailability.available() : reason = null;
  const ContentChannelAvailability.unavailable(this.reason);

  final String? reason;
  bool get enabled => reason == null;
}

/// Switches learning modes inside one content session. Availability belongs
/// to the loaded source: a future channel is shown honestly, never as a
/// clickable promise.
class ContentChannelSwitcher extends StatelessWidget {
  const ContentChannelSwitcher({
    super.key,
    required this.selected,
    required this.availability,
    required this.onSelected,
  });

  final ContentChannel selected;
  final Map<ContentChannel, ContentChannelAvailability> availability;
  final ValueChanged<ContentChannel> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: l.text('contentChannels'),
      child: Wrap(
        key: const ValueKey('content-channel-switcher'),
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final channel in ContentChannel.values)
            _channelButton(context, l, colors, channel),
        ],
      ),
    );
  }

  Widget _channelButton(
    BuildContext context,
    AppLocalizations l,
    ColorScheme colors,
    ContentChannel channel,
  ) {
    final state =
        availability[channel] ??
        ContentChannelAvailability.unavailable(l.text('channelUnavailable'));
    final active = channel == selected;
    final label = l.text(switch (channel) {
      ContentChannel.listening => 'channelListening',
      ContentChannel.reading => 'channelReading',
      ContentChannel.speaking => 'channelSpeaking',
      ContentChannel.writing => 'channelWriting',
    });
    final icon = switch (channel) {
      ContentChannel.listening => Icons.headphones_outlined,
      ContentChannel.reading => Icons.menu_book_outlined,
      ContentChannel.speaking => Icons.mic_none_outlined,
      ContentChannel.writing => Icons.edit_outlined,
    };
    final button = TextButton.icon(
      key: ValueKey('content-channel-${channel.name}'),
      onPressed: state.enabled && !active ? () => onSelected(channel) : null,
      style: TextButton.styleFrom(
        foregroundColor: active ? colors.onPrimary : colors.onSurfaceVariant,
        backgroundColor: active ? colors.primary : Colors.transparent,
        disabledForegroundColor: active
            ? colors.onPrimary
            : colors.onSurfaceVariant.withValues(alpha: 0.45),
        padding: ListenPadding.row,
        shape: RoundedRectangleBorder(borderRadius: ListenRadii.controlBorder),
      ),
      icon: Icon(icon, size: ListenIconSize.control),
      label: Text(label),
    );
    if (state.enabled) return button;
    return Tooltip(
      message: state.reason!,
      child: Semantics(
        label: '$label: ${state.reason}',
        enabled: false,
        child: button,
      ),
    );
  }
}
