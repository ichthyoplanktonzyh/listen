import '../../localization.dart';
import '../../models/semantic_task.dart';

/// Fixed communication checkpoints for role reply. They assess whether the
/// learner's response functions in context, never whether it matches a stored
/// sentence word-for-word.
List<RubricPointView> roleReplyTemplate(AppLocalizations l) => [
  RubricPointView(
    pointId: 'responsive',
    importance: 'required',
    statement: l.text('speakingRolePointResponsive'),
  ),
  RubricPointView(
    pointId: 'meaning',
    importance: 'required',
    statement: l.text('speakingRolePointMeaning'),
  ),
  RubricPointView(
    pointId: 'continuation',
    importance: 'optional',
    statement: l.text('speakingRolePointContinuation'),
  ),
];
