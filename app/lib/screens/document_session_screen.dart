import 'package:flutter/material.dart';

import '../controllers/document_session_controller.dart';
import '../localization.dart';
import '../widgets/document/document_session_view.dart';

/// The direct document session surface: one full route hosting the session
/// state machine. It is deliberately named a session, not a reader — there is
/// no structured reading, no fabricated anchor, no reading position here.
class DocumentSessionScreen extends StatelessWidget {
  const DocumentSessionScreen({super.key, required this.controller});

  final DocumentSessionController controller;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.text('documentTitle'))),
      body: DocumentSessionView(controller: controller),
    );
  }
}
