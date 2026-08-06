import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../utils/transcript_translation.dart';
import '../common/menu_rows.dart';

/// Switches the transcript between original, bilingual and translation.
///
/// It sits on the session header beside the other actions on this media. The
/// second subtitle track used to be reachable only as an overlay toggle down
/// on the transport, which meant the transcript — where the reading actually
/// happens — had no translation at all, and the one control that existed was
/// nowhere near the text it affected.
class TranslationModeButton extends StatelessWidget {
  const TranslationModeButton({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final TranscriptTranslation mode;
  final ValueChanged<TranscriptTranslation> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    // Only a non-default state lights up: showing both tracks is the resting
    // arrangement, so it does not need to announce itself.
    final active = mode != TranscriptTranslation.bilingual;
    return PopupMenuButton<TranscriptTranslation>(
      key: const Key('translation-mode-button'),
      tooltip: l.text('translationDisplay'),
      initialValue: mode,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final value in TranscriptTranslation.values)
          PopupMenuItem(
            value: value,
            child: ListenMenuRow(
              icon: value == mode
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              title: l.text(switch (value) {
                TranscriptTranslation.source => 'translationSourceOnly',
                TranscriptTranslation.bilingual => 'translationBilingual',
                TranscriptTranslation.translation => 'translationOnly',
              }),
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ListenSpacing.gap8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.translate_outlined,
              size: ListenIconSize.chrome,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: ListenSpacing.gap2),
            Icon(
              Icons.arrow_drop_down,
              size: ListenIconSize.control,
              color: active ? colors.primary : colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
