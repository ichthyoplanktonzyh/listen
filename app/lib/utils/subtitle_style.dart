/// Calculate responsive subtitle font size based on viewport width, user scale,
/// preset, and text length.
double responsiveSubtitleSize({
  required double width,
  required double scale,
  required String preset,
  required int textLength,
  bool secondary = false,
}) {
  final presetFactor = switch (preset) {
    'watching' => 0.82,
    'compact' => 0.7,
    _ => 1.0,
  };
  final base = (width * 0.034).clamp(18.0, 34.0);
  final targetLength = secondary ? 84 : 72;
  final minimum = secondary ? 0.78 : 0.72;
  final lengthFactor = (targetLength / textLength.clamp(1, 1000)).clamp(
    minimum,
    1.0,
  );
  return base * (secondary ? 0.72 : 1) * scale * presetFactor * lengthFactor;
}
