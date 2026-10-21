import 'package:flutter/material.dart';

/// Color used for a listening assessment throughout the vocabulary surfaces.
Color capabilityAssessmentColor(ColorScheme colors, String assessment) =>
    switch (assessment) {
      'acquired' => colors.primary,
      'not_acquired' => colors.secondary,
      _ => colors.onSurfaceVariant.withValues(alpha: 0.45),
    };
