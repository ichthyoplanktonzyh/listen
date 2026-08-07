import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/content_channel.dart';
import '../../models/workbench_study_mode.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../common/menu_rows.dart';
import 'content_channel_availability.dart';

/// Every way of working this material, in one menu on the session header.
///
/// These used to be spread over four places at once: a row of four channel
/// pills in this header, a 2×2 posture grid above the transcript, a popup
/// inside one of its cells, and two more menus down on the transport. Four
/// locations for one question — *how do I want to work this material* — and
/// two of them offered Reading, by two different code paths.
///
/// The grouping is the information. The channels are surfaces, mutually
/// exclusive, so they carry a selection mark; the intensive modes are things
/// you start on the sentence being played, so they do not.
class StudyMenu extends StatelessWidget {
  const StudyMenu({
    super.key,
    required this.selectedChannel,
    required this.channelAvailability,
    required this.onChannelSelected,
    required this.selectedMode,
    required this.onModeSelected,
    required this.hasCue,
    required this.canCloze,
    required this.canChunkDictation,
    required this.onShadow,
    required this.onCloze,
    required this.onChunkDictation,
    required this.onSentenceDictation,
  });

  final ContentChannel selectedChannel;
  final Map<ContentChannel, ContentChannelAvailability> channelAvailability;
  final ValueChanged<ContentChannel> onChannelSelected;

  /// The listening channel is expressed *as* its three display modes — read
  /// through, blind, word select — rather than a single "Listen" item beside a
  /// separate mode switch. Picking one enters listening in that display, so the
  /// menu carries one selection ("how am I working this material") across both
  /// channels and modes.
  final WorkbenchStudyMode selectedMode;
  final ValueChanged<WorkbenchStudyMode> onModeSelected;

  /// The intensive modes work on the sentence being played. Without one they
  /// are listed and disabled rather than hidden, so the menu never changes
  /// shape underfoot.
  final bool hasCue;

  /// Whether cloze and chunk dictation have the timing data they need. Both
  /// stay listed either way; the subtitle says what is missing instead of the
  /// row silently disappearing.
  final bool canCloze;
  final bool canChunkDictation;

  final VoidCallback onShadow;
  final VoidCallback onCloze;
  final VoidCallback onChunkDictation;
  final VoidCallback onSentenceDictation;

  static const _channelValuePrefix = 'channel-';
  static const _modeValuePrefix = 'mode-';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return PopupMenuButton<String>(
      key: const Key('study-menu'),
      tooltip: l.text('studyMode'),
      onSelected: (value) {
        if (value.startsWith(_channelValuePrefix)) {
          final name = value.substring(_channelValuePrefix.length);
          onChannelSelected(
            ContentChannel.values.firstWhere((channel) => channel.name == name),
          );
          return;
        }
        if (value.startsWith(_modeValuePrefix)) {
          final name = value.substring(_modeValuePrefix.length);
          onModeSelected(
            WorkbenchStudyMode.values.firstWhere((mode) => mode.name == name),
          );
          return;
        }
        switch (value) {
          case 'shadow':
            onShadow();
          case 'cloze':
            onCloze();
          case 'chunk':
            onChunkDictation();
          case 'sentence':
            onSentenceDictation();
        }
      },
      itemBuilder: (_) => [
        ListenMenuHeader(label: l.text('studyModeReadingGroup')),
        // The listening channel, as its three displays. Selecting one enters
        // listening in that mode, so these carry listening's selection mark.
        _modeItem(
          l,
          WorkbenchStudyMode.normal,
          Icons.article_outlined,
          'studyModeNormal',
          'studyModeNormalHint',
        ),
        _modeItem(
          l,
          WorkbenchStudyMode.blindListening,
          Icons.hearing_outlined,
          'studyModeBlind',
          'studyModeBlindHint',
        ),
        _modeItem(
          l,
          WorkbenchStudyMode.wordSelection,
          Icons.quiz_outlined,
          'studyModeWordSelect',
          'studyModeWordSelectHint',
        ),
        _channelItem(l, ContentChannel.reading),
        const PopupMenuDivider(),
        ListenMenuHeader(label: l.text('studyModeIntensiveGroup')),
        PopupMenuItem(
          value: 'shadow',
          enabled: hasCue,
          child: ListenMenuRow(
            enabled: hasCue,
            icon: Icons.mic_none,
            title: l.text('postureShadowTitle'),
            subtitle: l.text('postureShadowHint'),
          ),
        ),
        PopupMenuItem(
          value: 'cloze',
          enabled: hasCue && canCloze,
          child: ListenMenuRow(
            enabled: hasCue && canCloze,
            icon: Icons.text_fields,
            title: l.text('clozePractice'),
            subtitle: canCloze
                ? l.text('practiceClozeTooltip')
                : l.text('practiceClozeUnavailable'),
          ),
        ),
        PopupMenuItem(
          value: 'chunk',
          enabled: hasCue,
          child: ListenMenuRow(
            enabled: hasCue,
            icon: Icons.segment,
            title: l.text('chunkDictation'),
            subtitle: canChunkDictation
                ? l.text('practiceChunkTooltip')
                : l.text('practiceChunkFallbackTooltip'),
          ),
        ),
        PopupMenuItem(
          value: 'sentence',
          enabled: hasCue,
          child: ListenMenuRow(
            enabled: hasCue,
            icon: Icons.short_text,
            title: l.text('sentenceDictation'),
          ),
        ),
        const PopupMenuDivider(),
        ListenMenuHeader(label: l.text('studyModeTaskGroup')),
        _channelItem(l, ContentChannel.speaking),
        _channelItem(l, ContentChannel.writing),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              // In listening the trigger shows the active display; elsewhere it
              // shows the channel you are in.
              selectedChannel == ContentChannel.listening
                  ? _modeIcon(selectedMode)
                  : _channelIcon(selectedChannel),
              size: ListenIconSize.chrome,
              color: quiet,
            ),
            const SizedBox(width: ListenSpacing.gap2),
            Icon(
              Icons.arrow_drop_down,
              size: ListenIconSize.control,
              color: quiet,
            ),
          ],
        ),
      ),
    );
  }

  /// One surface. Availability belongs to the loaded source: a channel that
  /// cannot be entered is shown with the reason on its second line, never as
  /// a clickable promise and never silently missing.
  PopupMenuItem<String> _channelItem(
    AppLocalizations l,
    ContentChannel channel,
  ) {
    final state =
        channelAvailability[channel] ??
        ContentChannelAvailability.unavailable(l.text('channelUnavailable'));
    final selected = channel == selectedChannel;
    return PopupMenuItem(
      key: ValueKey('content-channel-${channel.name}'),
      value: '$_channelValuePrefix${channel.name}',
      enabled: state.enabled,
      child: ListenMenuRow(
        enabled: state.enabled,
        icon: selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        title: l.text(switch (channel) {
          ContentChannel.listening => 'channelListening',
          ContentChannel.reading => 'channelReading',
          ContentChannel.speaking => 'channelSpeaking',
          ContentChannel.writing => 'channelWriting',
        }),
        subtitle: state.reason,
      ),
    );
  }

  /// One display of the listening transcript. Mutually exclusive with the
  /// channels and with each other, so it carries a radio mark — lit only while
  /// listening is the channel you are in.
  PopupMenuItem<String> _modeItem(
    AppLocalizations l,
    WorkbenchStudyMode mode,
    IconData icon,
    String titleKey,
    String hintKey,
  ) {
    final selected =
        selectedChannel == ContentChannel.listening && selectedMode == mode;
    return PopupMenuItem(
      key: ValueKey('study-mode-${mode.name}'),
      value: '$_modeValuePrefix${mode.name}',
      child: ListenMenuRow(
        icon: selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        title: l.text(titleKey),
        subtitle: l.text(hintKey),
      ),
    );
  }

  static IconData _modeIcon(WorkbenchStudyMode mode) => switch (mode) {
    WorkbenchStudyMode.normal => Icons.article_outlined,
    WorkbenchStudyMode.blindListening => Icons.hearing_outlined,
    WorkbenchStudyMode.wordSelection => Icons.quiz_outlined,
  };

  static IconData _channelIcon(ContentChannel channel) => switch (channel) {
    ContentChannel.listening => Icons.headphones_outlined,
    ContentChannel.reading => Icons.menu_book_outlined,
    ContentChannel.speaking => Icons.mic_none_outlined,
    ContentChannel.writing => Icons.edit_outlined,
  };
}
