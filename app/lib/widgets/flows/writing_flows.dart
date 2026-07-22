import '../../controllers/writing_task_controller.dart';
import '../../localization.dart';
import '../../models/semantic_task.dart';

List<RubricPointView> writingTaskTemplate(AppLocalizations l) => [
  RubricPointView(
    pointId: 'task_fulfillment',
    importance: 'required',
    statement: l.text('writingRubricTask'),
  ),
  RubricPointView(
    pointId: 'content',
    importance: 'required',
    statement: l.text('writingRubricContent'),
  ),
  RubricPointView(
    pointId: 'organization',
    importance: 'optional',
    statement: l.text('writingRubricOrganization'),
  ),
];

String writingPrompt(AppLocalizations l, String kind) => switch (kind) {
  WritingTaskController.oneSentenceSummaryKind => l.text(
    'writingPromptOneSentenceSummary',
  ),
  WritingTaskController.opinionKind => l.text('writingPromptOpinion'),
  WritingTaskController.dictoglossKind => l.text('writingPromptDictogloss'),
  _ => l.text('writingPromptSummary'),
};
