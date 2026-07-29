import 'package:flutter/material.dart';
import 'package:llplayer_next/models/coach_dashboard.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/common/capability_viz.dart';

import 'support/golden.dart';

/// Baselines for the capability portrait (#47 / #81, repaired in S3).
///
/// This is the graphic the whole net was built for. §0 of the 2026-07 design
/// spec names it as the proof that value-level gates are not enough: the echo
/// bars had decayed into two flat grey blocks — the `unassessed` count was
/// filling the scale, so the bar's entire visual mass was drawing *what we do
/// not know* — and every color, radius and spacing literal in it was still
/// perfectly legal. Nobody noticed until a screenshot was read by hand.
///
/// The fixture is the design doc's own mock: a library that recognizes far
/// more than it produces, and that is mostly unassessed. That last property is
/// the load-bearing one — with these numbers the pre-S3 rendering and the
/// repaired one look nothing alike, so this baseline would have failed on the
/// day the regression landed.
///
/// Both folds of [ListenBreakpoints.capabilityPortraitSideBySide] are pinned:
/// the compass beside the bars, and the compass stacked over them. A fold is
/// where layout regressions hide, and the narrow form is the one nobody opens
/// a window small enough to see.
void main() {
  goldenScene(
    'coach_capability_portrait_wide',
    size: GoldenSurface.abovePortraitFold,
    builder: (context) => _portrait(_portraitChannels),
  );

  goldenScene(
    'coach_capability_portrait_narrow',
    size: GoldenSurface.belowPortraitFold,
    builder: (context) => _portrait(_portraitChannels),
  );

  // A learner on their first day: nothing assessed at all. The honest frame
  // here is an empty gauge with the scale line saying so — not a full-looking
  // graphic, and not a blank rectangle either.
  goldenScene(
    'coach_capability_portrait_unassessed',
    size: GoldenSurface.abovePortraitFold,
    builder: (context) => _portrait(_unassessedChannels),
  );
}

Widget _portrait(List<CoachChannelSummary> channels) => Padding(
  padding: ListenPadding.page,
  child: Align(
    alignment: Alignment.topCenter,
    child: CapabilityPortrait(channels: channels, gapCount: 34),
  ),
);

CoachChannelSummary _channel(
  String name, {
  int acquired = 0,
  int notAcquired = 0,
  int unassessed = 0,
}) => CoachChannelSummary(
  channel: name,
  status: 'active',
  metrics: const [],
  effectiveAssessments: CoachAssessmentSummary(
    acquired: acquired,
    notAcquired: notAcquired,
    unassessed: unassessed,
  ),
);

/// The design-doc mock, reused verbatim from `capability_viz_test.dart` so the
/// picture and the arithmetic assertions describe the same learner.
final _portraitChannels = [
  _channel('listening', acquired: 46, notAcquired: 18, unassessed: 96),
  _channel('reading', acquired: 88, notAcquired: 10, unassessed: 62),
  _channel('speaking', acquired: 12, notAcquired: 30, unassessed: 118),
  _channel('writing', acquired: 8, notAcquired: 22, unassessed: 130),
];

final _unassessedChannels = [
  for (final name in const ['listening', 'reading', 'speaking', 'writing'])
    _channel(name, unassessed: 208),
];
