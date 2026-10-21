import 'package:flutter/material.dart';

import '../../models/types.dart';

/// Color used for a listening assessment throughout the vocabulary surfaces.
Color capabilityAssessmentColor(ColorScheme colors, String assessment) =>
    switch (assessment) {
      'acquired' => colors.primary,
      'not_acquired' => colors.secondary,
      _ => colors.onSurfaceVariant.withValues(alpha: 0.45),
    };

/// Effective manual or observed assessment for each learning channel. A
/// missing profile has no evidence in any channel.
Map<String, String> capabilityProfileAssessments(
  LexicalCapabilityProfile? profile,
) => {
  'listening': profile?.listening.effectiveAssessment ?? 'unassessed',
  'reading': profile?.reading.effectiveAssessment ?? 'unassessed',
  'speaking': profile?.speaking.effectiveAssessment ?? 'unassessed',
  'writing': profile?.writing.effectiveAssessment ?? 'unassessed',
};
