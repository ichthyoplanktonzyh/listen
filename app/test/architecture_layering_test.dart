import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level dependency rules for the layered Flutter architecture.
///
/// These checks cover dependency relationships that must never be crossed.
/// `lib/widgets/flows` is the route-composition boundary: it may own a freshly
/// injected notifier, while reusable views only render state and emit intent.
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

  test('presentation does not import repositories or platform I/O', () {
    const renderingAdapterImports = {
      'lib/widgets/layout/desktop_drop_surface.dart': {
        "import 'package:desktop_drop/desktop_drop.dart';",
      },
      'lib/widgets/panels/slice_playback_window.dart': {
        "import 'package:video_player/video_player.dart';",
      },
      'lib/widgets/vocabulary/dictionary_inline_clip_player.dart': {
        "import 'package:video_player/video_player.dart';",
      },
    };
    final offenders = _presentationFiles()
        .expand((file) {
          final findings = <String>[];
          final lines = file.readAsLinesSync();
          for (var index = 0; index < lines.length; index++) {
            final line = lines[index].trim();
            final isRenderingAdapter =
                renderingAdapterImports[file.path]?.contains(line) ?? false;
            if (line.contains('/data/repositories/') ||
                line == "import 'dart:io';" ||
                line.contains('services/api_service.dart') ||
                line.contains('package:file_selector/file_selector.dart') ||
                (!isRenderingAdapter &&
                    (line.contains('package:desktop_drop/desktop_drop.dart') ||
                        line.contains(
                          'package:video_player/video_player.dart',
                        )))) {
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
          'Keep repositories, transport, file-system access, pickers, and '
          'platform plugins outside presentation. Rendering-only plugin '
          'adapters are narrowly allow-listed:\n'
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

  test(
    'reusable views never construct application ViewModels or Controllers',
    () {
      const uiControllerAllowList = {
        'AnimationController',
        'DefaultTabController',
        'PageController',
        'ScrollController',
        'TabController',
        'TextEditingController',
        'TransformationController',
      };
      final constructor = RegExp(
        r'\b([A-Z][A-Za-z0-9_]*(?:ViewModel|Controller))\s*\(',
      );
      final offenders = <String>[];
      for (final file in _viewFiles()) {
        final lines = file.readAsLinesSync();
        for (var index = 0; index < lines.length; index++) {
          for (final match in constructor.allMatches(lines[index])) {
            if (uiControllerAllowList.contains(match.group(1))) continue;
            offenders.add('${file.path}:${index + 1} → ${lines[index].trim()}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Create application ViewModels/Controllers in main or a route flow, '
            'then inject them into reusable views. Only pure Flutter UI '
            'controllers are locally owned:\n${offenders.join('\n')}',
      );
    },
  );

  test('immutable notifier state defensively wraps collection fields', () {
    final offenders = <String>[];
    for (final file in _dartFilesUnder('lib/controllers')) {
      final source = file.readAsStringSync();
      for (final block in _immutableStateBlocks(source)) {
        for (final kind in const ['List', 'Map', 'Set']) {
          if (!RegExp('final\\s+$kind<').hasMatch(block.source)) {
            continue;
          }
          final wrapped =
              block.source.contains('$kind.unmodifiable(') ||
              block.source.contains('Unmodifiable${kind}View');
          if (!wrapped) {
            offenders.add(
              '${file.path}:${block.line} → ${block.name} exposes $kind',
            );
          }
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'ChangeNotifier state snapshots must not expose mutable collection '
          'aliases. Copy/wrap List, Map, and Set inputs in the state '
          'constructor:\n${offenders.join('\n')}',
    );
  });
}

typedef _StateBlock = ({String name, String source, int line});

Iterable<_StateBlock> _immutableStateBlocks(String source) sync* {
  final declaration = RegExp(
    r'@immutable\s+(?:(?:abstract|base|final|sealed)\s+)*class\s+'
    r'([A-Za-z_][A-Za-z0-9_]*(?:State|Snapshot))\b',
  );
  for (final match in declaration.allMatches(source)) {
    final openBrace = source.indexOf('{', match.end);
    if (openBrace < 0) continue;
    var depth = 0;
    var closeBrace = -1;
    for (var index = openBrace; index < source.length; index++) {
      if (source.codeUnitAt(index) == 123) depth++;
      if (source.codeUnitAt(index) == 125 && --depth == 0) {
        closeBrace = index;
        break;
      }
    }
    if (closeBrace < 0) continue;
    yield (
      name: match.group(1)!,
      source: source.substring(match.start, closeBrace + 1),
      line: '\n'.allMatches(source.substring(0, match.start)).length + 1,
    );
  }
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

Iterable<File> _viewFiles() => _presentationFiles().where(
  (file) => !file.path.startsWith('lib/widgets/flows/'),
);

Iterable<File> _dartFilesUnder(String root) sync* {
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}
