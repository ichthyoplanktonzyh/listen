import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level dependency rules for the layered Flutter architecture.
///
/// These checks intentionally cover only relationships that must never be
/// crossed. Feature-specific Repository adoption is verified by its own tests
/// because a textual import alone cannot distinguish a transport service from
/// an injected data boundary.
void main() {
  test('controllers never depend on widgets or screens', () {
    final offenders = _importsFrom(
      root: 'lib/controllers',
      forbiddenSegments: const ['/widgets/', '/screens/'],
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'Presentation state belongs in controllers/models; move shared '
          'types out of widgets so dependencies point toward the ViewModel:\n'
          '${offenders.join('\n')}',
    );
  });

  test('controllers depend on repositories and service abstractions', () {
    final offenders = _forbiddenImportsUnder('lib/controllers', const {
      "import 'dart:io';",
      "import '../services/api_service.dart';",
      "import 'package:file_selector/file_selector.dart';",
      "import 'package:video_player/video_player.dart';",
    });

    expect(
      offenders,
      isEmpty,
      reason:
          'Controllers must not own transport, file-system, picker, or media '
          'plugin implementations. Inject a repository/service boundary:\n'
          '${offenders.join('\n')}',
    );
  });

  test('data and service layers never depend on presentation', () {
    final offenders = <String>[
      ..._importsFrom(
        root: 'lib/data',
        forbiddenSegments: const ['/widgets/', '/screens/', '/controllers/'],
      ),
      ..._importsFrom(
        root: 'lib/services',
        forbiddenSegments: const ['/widgets/', '/screens/', '/controllers/'],
      ),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Repositories and services are lower layers and cannot import UI or '
          'UI lifecycle types:\n${offenders.join('\n')}',
    );
  });

  test('domain models have no outward layer dependencies', () {
    final offenders = _importsFrom(
      root: 'lib/models',
      forbiddenSegments: const [
        '/controllers/',
        '/data/',
        '/screens/',
        '/services/',
        '/widgets/',
      ],
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'Domain models must remain portable and independent of transport, '
          'state management, and presentation:\n${offenders.join('\n')}',
    );
  });

  test('views do not depend on transport or platform file APIs', () {
    final offenders = _presentationFiles()
        .expand((file) {
          final findings = <String>[];
          final lines = file.readAsLinesSync();
          for (var index = 0; index < lines.length; index++) {
            final line = lines[index].trim();
            if (line == "import 'dart:io';" ||
                line.contains('services/api_service.dart') ||
                line.contains('package:file_selector/file_selector.dart')) {
              findings.add('${file.path}:${index + 1} → $line');
            }
          }
          return findings;
        })
        .toList(growable: false);

    expect(
      offenders,
      isEmpty,
      reason:
          'Keep transport, file-system access, and pickers behind injected '
          'repositories/services; views render state and emit intent:\n'
          '${offenders.join('\n')}',
    );
  });

  test('views never construct LocalApi-backed repositories', () {
    final pattern = RegExp(r'Local[A-Z][A-Za-z]+Repository\s*\(');
    final offenders = <String>[];
    for (final file in _presentationFiles()) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (pattern.hasMatch(lines[index])) {
          offenders.add('${file.path}:${index + 1} → ${lines[index].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Concrete repositories belong in the composition root; inject the '
          'interface into presentation:\n${offenders.join('\n')}',
    );
  });
}

List<String> _importsFrom({
  required String root,
  required List<String> forbiddenSegments,
}) {
  final offenders = <String>[];
  for (final file in _dartFilesUnder(root)) {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (!line.startsWith('import ')) continue;
      final normalized = '/${file.path}/$line';
      if (forbiddenSegments.any(normalized.contains)) {
        offenders.add('${file.path}:${index + 1} → $line');
      }
    }
  }
  return offenders;
}

List<String> _forbiddenImportsUnder(String root, Set<String> forbidden) {
  final offenders = <String>[];
  for (final file in _dartFilesUnder(root)) {
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      if (forbidden.contains(lines[index].trim())) {
        offenders.add('${file.path}:${index + 1} → ${lines[index].trim()}');
      }
    }
  }
  return offenders;
}

Iterable<File> _presentationFiles() sync* {
  yield* _dartFilesUnder('lib/screens');
  yield* _dartFilesUnder('lib/widgets');
  yield* _dartFilesUnder('lib/ui');
  for (final entity in Directory('lib').listSync()) {
    if (entity is File && entity.path.endsWith('_ui.dart')) yield entity;
  }
}

Iterable<File> _dartFilesUnder(String root) sync* {
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}
