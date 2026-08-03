import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../theme/listen_theme.dart';

/// Shared preview shell: theme + localization so a widget preview renders the
/// same chrome the running app would, without a full app entrypoint.
Widget discoveryPreviewShell(
  Widget child, {
  double width = 900,
  double height = 640,
}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [AppLocalizations.delegate],
    theme: ListenTheme.light(),
    darkTheme: ListenTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SizedBox(width: width, height: height, child: child),
    ),
  );
}
