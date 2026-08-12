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
      'lib/widgets/composition/composition_audio_player.dart': {
        "import 'dart:io';",
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
                line.contains('services/api_service.dart') ||
                line.contains('package:file_selector/file_selector.dart') ||
                (!isRenderingAdapter &&
                    (line == "import 'dart:io';" ||
                        line.contains('package:desktop_drop/desktop_drop.dart') ||
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

  test('raw transport maps outside services stay at the ratchet baseline', () {
    _expectDebtAtRatchetBaseline(
      files: <File>[
        ..._dartFilesUnder('lib/controllers'),
        ..._dartFilesUnder('lib/data/repositories'),
        ..._presentationFiles(),
      ],
      pattern: RegExp(r'Map<String,\s*(?:dynamic|Object\?)>'),
      baseline: _rawTransportMapBaseline,
      debtName: 'raw transport Map',
    );
  });

  test('model wire-format coupling stays at the ratchet baseline', () {
    _expectDebtAtRatchetBaseline(
      files: _dartFilesUnder('lib/models'),
      pattern: RegExp(
        r'\b(?:fromJson|toJson)\s*\(|Map<String,\s*(?:dynamic|Object\?)>',
      ),
      baseline: _modelWireCouplingBaseline,
      debtName: 'model wire-format coupling',
    );
  });
}

/// Known debt is recorded as an exact count, rather than an allow-list.
///
/// A new occurrence fails. A removed occurrence also fails until its ceiling is
/// lowered here, preventing a later change from silently restoring old debt.
const _rawTransportMapBaseline = <String, int>{
  'lib/controllers/backend_event_coordinator.dart': 1,
  'lib/controllers/core_session_controller.dart': 2,
  'lib/controllers/learning_assets_view_models.dart': 3,
  'lib/controllers/learning_controller.dart': 1,
  'lib/controllers/learning_flow_view_models.dart': 3,
  'lib/controllers/learning_workflow_controller.dart': 6,
  'lib/controllers/manual_review_controller.dart': 1,
  'lib/controllers/media_session_coordinator.dart': 3,
  'lib/controllers/occurrence_media_resolver.dart': 2,
  'lib/controllers/playback_actions_coordinator.dart': 1,
  'lib/controllers/practice_actions_coordinator.dart': 1,
  'lib/controllers/reading_channel_coordinator.dart': 2,
  'lib/controllers/realtime_conversation_controller.dart': 2,
  'lib/controllers/slice_player_controller.dart': 2,
  'lib/controllers/vocabulary_actions_coordinator.dart': 1,
  'lib/controllers/vocabulary_view_model.dart': 2,
  'lib/controllers/writing_channel_coordinator.dart': 2,
  'lib/controllers/writing_task_controller.dart': 1,
  'lib/data/repositories/core_session_repository.dart': 2,
  'lib/data/repositories/external_vocabulary_repository.dart': 2,
  'lib/data/repositories/learning_assets_repository.dart': 2,
  'lib/data/repositories/learning_repository.dart': 6,
  'lib/data/repositories/lexical_repository.dart': 2,
  'lib/data/repositories/manual_review_repository.dart': 2,
  'lib/data/repositories/media_session_repository.dart': 2,
  'lib/data/repositories/playback_repository.dart': 3,
  'lib/data/repositories/reading_task_repository.dart': 2,
  'lib/data/repositories/realtime_conversation_repository.dart': 7,
  'lib/data/repositories/speaking_task_repository.dart': 2,
  'lib/data/repositories/writing_task_repository.dart': 4,
  'lib/screens/vocabulary_screen.dart': 2,
  'lib/widgets/channels/reading_channel.dart': 1,
  'lib/widgets/flows/learning_flows.dart': 2,
  'lib/widgets/layout/side_panel.dart': 1,
  'lib/widgets/panels/reading_word_inspector.dart': 1,
  'lib/widgets/panels/word_learning_panel.dart': 1,
  'lib/widgets/vocabulary/vocabulary_details_view.dart': 4,
};

const _modelWireCouplingBaseline = <String, int>{
  'lib/models/api_failure.dart': 1,
  // 23, down from 27: the whole-media TranscriptionJobChangedEvent wire model
  // is gone. The app prepares transcripts through the pinned listen-gen package
  // journey and no longer parses Core's transcription-job SSE envelopes.
  'lib/models/backend_event.dart': 23,
  'lib/models/coach_dashboard.dart': 32,
  'lib/models/listening.dart': 12,
  'lib/models/llm_provider.dart': 14,
  'lib/models/personal_expression.dart': 33,
  // 138, up from 132: contract 1.1.0 makes `state` and `origin` required
  // fields of ReviewQueueEntry. The card head has to read the scheduler's own
  // state rather than infer one from `interval_days`/`lapse_count`, and the
  // session has to read `origin.has_listening_enhancements` rather than assume
  // every card was born here. That is two parsed types, each costing a
  // `fromJson` declaration plus its call site. Deliberate: the alternative was
  // less wire coupling and two wrong claims on screen.
  'lib/models/practice.dart': 138,
  // The review surfaces contract 1.1.0 added — deck counts, daily budget,
  // interval prediction, custom study and Anki interop. Eleven wire types in
  // their own file rather than piled onto practice.dart, which is why this is
  // a new entry and not another jump in the number above.
  'lib/models/review_deck.dart': 51,
  'lib/models/production_corpus.dart': 26,
  'lib/models/projection_review.dart': 10,
  'lib/models/reading.dart': 2,
  'lib/models/realtime_conversation.dart': 10,
  // 28, down from 30: the whole-media TranscriptionJobView wire model is gone
  // along with the Core transcription-job surface it decoded.
  'lib/models/runtime_resources.dart': 28,
  'lib/models/semantic_embedding.dart': 18,
  'lib/models/semantic_task.dart': 67,
  'lib/models/speech_synthesis.dart': 12,
  'lib/models/syntax_capability.dart': 4,
  'lib/models/timeline/display.dart': 6,
  // 53, up from 51: the LLTimeline document now also projects the active
  // Prosody Analysis (the sole prosodic-chunk source) with its declared
  // token spans; the legacy ChunkTimeline wire fields were removed.
  'lib/models/timeline/document.dart': 53,
  'lib/models/timeline/rhythm.dart': 107,
  'lib/models/timeline/sound.dart': 50,
  'lib/models/timeline/subtitle.dart': 10,
  // 34, down from 44: the legacy ChunkTimeline model family was retired;
  // only the ProsodyAnalysis projection remains as the chunk source.
  'lib/models/timeline/word_chunk.dart': 34,
  'lib/models/types.dart': 1,
  'lib/models/types/diagnosis.dart': 26,
  'lib/models/types/dictionary.dart': 46,
  'lib/models/types/lexical.dart': 91,
  'lib/models/types/media_fit.dart': 56,
  'lib/models/types/pronunciation.dart': 60,
  'lib/models/vocabulary_transfer.dart': 7,
};

void _expectDebtAtRatchetBaseline({
  required Iterable<File> files,
  required RegExp pattern,
  required Map<String, int> baseline,
  required String debtName,
}) {
  final current = <String, int>{};
  for (final file in files) {
    final count = pattern.allMatches(file.readAsStringSync()).length;
    if (count > 0) current[file.path] = count;
  }

  final findings = <String>[];
  for (final entry in current.entries) {
    final ceiling = baseline[entry.key];
    if (ceiling == null) {
      findings.add('${entry.key} → new debt (${entry.value})');
    } else if (entry.value > ceiling) {
      findings.add('${entry.key} → grew from $ceiling to ${entry.value}');
    } else if (entry.value < ceiling) {
      findings.add(
        '${entry.key} → reduced from $ceiling to ${entry.value}; '
        'lower the baseline now',
      );
    }
  }
  for (final entry in baseline.entries) {
    if (!current.containsKey(entry.key)) {
      findings.add(
        '${entry.key} → removed all ${entry.value}; remove the baseline entry',
      );
    }
  }

  expect(
    findings,
    isEmpty,
    reason:
        'The $debtName baseline is a one-way ratchet. New/increased debt is '
        'forbidden; when debt is removed, lower the exact baseline in the same '
        'change so it cannot return:\n${findings.join('\n')}',
  );
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
