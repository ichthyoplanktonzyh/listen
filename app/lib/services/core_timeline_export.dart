/// Raw wire envelope for one Core LLTimeline export.
///
/// The adopted-composition projection needs candidate resource families that
/// the display-oriented `LLTimelineDocument` model deliberately does not
/// parse. Keeping the raw map behind this service-owned handle stops raw
/// transport maps from leaking into repository interfaces or domain models.
final class CoreTimelineExport {
  CoreTimelineExport(this.json);

  final Map<String, dynamic> json;
}
