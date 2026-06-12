import 'package:flutter/painting.dart';

/// Move subtitle position by [delta] pixels within [viewport], returning a
/// normalized offset clamped to [0.0, 1.0] in both axes.
Offset moveSubtitlePosition({
  required Offset current,
  required Offset delta,
  required Size viewport,
}) => Offset(
  (current.dx + delta.dx / viewport.width).clamp(0.0, 1.0),
  (current.dy + delta.dy / viewport.height).clamp(0.0, 1.0),
);
