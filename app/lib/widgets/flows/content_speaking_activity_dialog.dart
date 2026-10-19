import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/content_activity.dart';
import '../../theme/breakpoints.dart';

Future<ContentSpeakingActivity?> showContentSpeakingActivityDialog(
  BuildContext context,
) => showDialog<ContentSpeakingActivity>(
  context: context,
  builder: (context) => const _ContentSpeakingActivityDialog(),
);

class _ContentSpeakingActivityDialog extends StatelessWidget {
  const _ContentSpeakingActivityDialog();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.text('contentSpeakingActivityTitle')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ListenBreakpoints.formColumnMax,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ActivityTile(
              key: const ValueKey('content-activity-retelling'),
              icon: Icons.record_voice_over_outlined,
              title: l.text('contentActivityRetelling'),
              subtitle: l.text('contentActivityRetellingSummary'),
              value: ContentSpeakingActivity.retelling,
            ),
            _ActivityTile(
              key: const ValueKey('content-activity-shadowing'),
              icon: Icons.graphic_eq,
              title: l.text('contentActivityShadowing'),
              subtitle: l.text('contentActivityShadowingSummary'),
              value: ContentSpeakingActivity.shadowing,
            ),
            _ActivityTile(
              key: const ValueKey('content-activity-conversation'),
              icon: Icons.forum_outlined,
              title: l.text('contentActivityConversation'),
              subtitle: l.text('contentActivityConversationSummary'),
              value: ContentSpeakingActivity.conversation,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.text('cancel')),
        ),
      ],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final ContentSpeakingActivity value;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    onTap: () => Navigator.pop(context, value),
  );
}
