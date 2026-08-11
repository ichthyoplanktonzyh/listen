import 'package:flutter/material.dart';

import '../../controllers/document_session_controller.dart';
import '../../screens/document_session_screen.dart';

/// Opens the direct document session as a full route.
///
/// [pausePlayback] is called before the route appears: a document must not
/// keep unrelated media playing behind it, and the media keeps its state —
/// nothing is closed, no progress or membership is touched.
Future<void> openDocumentSessionFlow({
  required BuildContext context,
  required DocumentSessionController controller,
  Future<void> Function()? pausePlayback,
}) async {
  await pausePlayback?.call();
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => DocumentSessionScreen(controller: controller),
    ),
  );
}
