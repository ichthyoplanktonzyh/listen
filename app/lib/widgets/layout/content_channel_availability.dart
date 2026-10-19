/// Whether a content channel can be entered right now, and if not, why.
///
/// The reason is not decoration: a channel that cannot be entered is listed
/// with its reason on the [StudyMenu], never hidden and never offered as a
/// clickable promise. The row of pills this type was born with is gone — one
/// menu now holds every way of working the material — but the honesty rule it
/// carries outlived the widget.
class ContentChannelAvailability {
  const ContentChannelAvailability.available() : reason = null;
  const ContentChannelAvailability.unavailable(this.reason);

  final String? reason;
  bool get enabled => reason == null;
}
