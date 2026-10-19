// Read-listen diff reduction (Phase 3.13 Slice 4, PLAN v2.1).
//
// The two sides are facts from two different rubrics over the same source
// segment (reading_comprehension vs l1_retelling). Their judgments are never
// compared point-by-point — `judgments_directly_comparable` rejects
// cross-rubric comparison by design. Each side reduces independently to a
// coarse outcome, and the pairing is presented as possibilities, never as a
// causal detection.

import 'semantic_task.dart';

enum SideOutcome { yes, partial, no, unassessed }

/// Effective verdict for one point: the latest adjudication wins, otherwise
/// the original judgment verdict.
String? effectiveVerdict(
  String pointId,
  SemanticJudgmentView judgment,
  List<JudgmentAdjudicationView> adjudications,
) {
  JudgmentAdjudicationView? latest;
  for (final adjudication in adjudications) {
    if (adjudication.pointId != pointId) continue;
    if (latest == null || adjudication.occurredAtMs >= latest.occurredAtMs) {
      latest = adjudication;
    }
  }
  return latest?.userVerdict ?? judgment.verdictFor(pointId);
}

/// Reduces one side's latest judgment to a coarse outcome. Required points
/// carry the verdict; optional points only count when no required points
/// exist. Abstain or absence is honestly `unassessed`, never a failure.
SideOutcome sideOutcome(
  List<RubricPointView> points,
  SemanticJudgmentView? judgment,
  List<JudgmentAdjudicationView> adjudications,
) {
  if (judgment == null || judgment.isAbstain) return SideOutcome.unassessed;
  final required = points
      .where((point) => point.importance == 'required')
      .toList();
  final basis = required.isEmpty ? points : required;
  if (basis.isEmpty) return SideOutcome.unassessed;
  var covered = 0;
  var missing = 0;
  for (final point in basis) {
    switch (effectiveVerdict(point.pointId, judgment, adjudications)) {
      case 'covered':
        covered++;
      case 'missing':
        missing++;
      case 'partial':
        break;
      default:
        // An uncertain (or unjudged) basis point keeps the side honest:
        // it cannot support a yes.
        break;
    }
  }
  if (covered == basis.length) return SideOutcome.yes;
  if (missing == basis.length) return SideOutcome.no;
  if (missing > 0 && covered == 0) return SideOutcome.no;
  return SideOutcome.partial;
}

/// Localization key for the paired explanation. Possibilities wording only:
/// the diff never claims to have detected a cause.
String diffExplanationKey(SideOutcome read, SideOutcome listen) {
  if (read == SideOutcome.unassessed || listen == SideOutcome.unassessed) {
    return 'diffUnknown';
  }
  if (read == SideOutcome.yes && listen == SideOutcome.yes) {
    return 'diffBothYes';
  }
  if (read == SideOutcome.yes &&
      (listen == SideOutcome.no || listen == SideOutcome.partial)) {
    return 'diffReadYesListenNo';
  }
  if ((read == SideOutcome.no || read == SideOutcome.partial) &&
      listen == SideOutcome.yes) {
    return 'diffReadNoListenYes';
  }
  if (read == SideOutcome.no && listen == SideOutcome.no) {
    return 'diffBothNo';
  }
  return 'diffMixed';
}
