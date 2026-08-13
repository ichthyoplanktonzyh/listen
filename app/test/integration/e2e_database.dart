@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Integration tests sharing one scratch database collide: the same fixture
/// media bytes resolve to the same Material identity by design, so one test's
/// installed candidates and adopted editions show up in another test's
/// edition list. Every test therefore drives its own Core database.
///
/// Reserves a unique scratch database path and hands it to
/// [LocalApi.connect] so the Core sidecar runs against it in isolation. The
/// database directory is removed after the test completes.
String scratchDatabasePath(String label) {
  final directory = Directory.systemTemp.createTempSync('e2e-db-$label-');
  final path = '${directory.path}/l.sqlite';
  addTearDown(() {
    try {
      directory.deleteSync(recursive: true);
    } on FileSystemException {
      // The Core process may still hold the file open at teardown; the OS
      // temp directory is cleaned up independently.
    }
  });
  return path;
}
