import 'dart:io';

/// Hands a reference URL to the operating system.
///
/// The dictionary's copyright guardrail is that the app links out rather than
/// fetching and re-rendering someone else's page, so "open this link" is the
/// whole feature. It still crosses a process boundary, which is service work:
/// AGENT.md keeps `Process.run` out of the widget layer, and this used to sit
/// inline in `vocabulary_screen.dart`.
///
/// The consumer app is macOS-only, so `open(1)` is sufficient and a
/// `url_launcher` dependency would be one plugin for one link. Failures are
/// swallowed for the same reason the inline version did: nothing on screen
/// depends on the outcome, and the system opener reports its own errors.
class ExternalLinkOpener {
  const ExternalLinkOpener();

  Future<void> open(String url) async {
    await Process.run('open', [url]);
  }
}
