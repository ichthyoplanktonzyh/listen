import 'api_failure.dart';

/// A failure a surface can *speak*: the localization key that names what
/// failed, and the transport detail that stays behind a disclosure.
///
/// The shape this replaces is `String? _error = '$error'` — one field holding
/// both the sentence and the exception, which is why the exception ended up
/// rendered. Splitting them makes the leak unrepresentable: [messageKey] is a
/// key, so it cannot carry transport text, and [detail] is typed, so the only
/// way to print it is to reach into a named field.
///
/// [detail] is nullable because not every failure comes from the backend — a
/// local tool or a cancelled future has nothing to disclose, and a surface
/// then shows the sentence alone.
class NamedFailure {
  const NamedFailure(this.messageKey, {this.detail});

  /// Localization key for the sentence naming what failed. A key, never a
  /// sentence: the surface localizes it at render time so the message follows
  /// the UI language.
  final String messageKey;

  /// What the transport carried, when the failure came from a request.
  /// `ApiFailure.raw` is not rendered even when a disclosure is expanded.
  final ApiFailure? detail;
}
