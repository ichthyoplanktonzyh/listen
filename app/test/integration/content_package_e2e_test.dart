@Tags(['e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/document_session_controller.dart';
import 'package:llplayer_next/controllers/material_capability_coordinator.dart';
import 'package:llplayer_next/data/repositories/capability_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/composition.dart';
import 'package:llplayer_next/models/document_session.dart';
import 'package:llplayer_next/models/learning_edition.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/material_capability.dart';
import 'package:llplayer_next/models/personal_library.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/capability_file_resolver.dart';
import 'package:llplayer_next/services/composition_session_service.dart';
import 'package:llplayer_next/services/document_intake_flow.dart';
import 'package:llplayer_next/services/document_intake_service.dart';
import 'package:llplayer_next/services/listen_gen_process_service.dart';
import 'package:llplayer_next/services/listen_gen_release_service.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/layout/document_material_surface.dart';
import 'package:llplayer_next/widgets/layout/material_workbench.dart';

import '../support/document_session_test_fakes.dart';
import 'e2e_database.dart';

const _matrixName =
    'the Gen/Core/App matrix keeps one adopted package shape across document and media families';
const _richName =
    'a video subtitle with fragmented cues lands as one complete sentence with every rich timeline';
const _renderName =
    'Core-adopted compositions render honest audio and text surfaces for document, audio, and video';
const _e2eStageTimeout = Duration(seconds: 90);

/// Real Core/Gen I/O must fail with the stage that is stuck, rather than
/// waiting for the widget test's global timeout. The timeout is deliberately
/// long for a real release/package round trip, but finite so teardown can run.
Future<T> _e2eStage<T>(String label, Future<T> operation) async {
  try {
    return await operation.timeout(_e2eStageTimeout);
  } on TimeoutException {
    throw StateError(
      'content-package E2E stage timed out after '
      '${_e2eStageTimeout.inSeconds}s: $label',
    );
  }
}

String _fixtureRoot() =>
    Platform.environment['LISTEN_E2E_FIXTURE_ROOT'] ??
    'test/fixtures/content-package-roundtrip';

File _fixture(String name) => File('${_fixtureRoot()}/$name');

String? _probePythonExecutable(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final result = Process.runSync(path, const [
      '--version',
    ], runInShell: false);
    final version = '${result.stdout}${result.stderr}';
    if (result.exitCode == 0 && version.contains('Python')) {
      return file.absolute.path;
    }
  } on Object {
    // A PATH entry can point at a stale or non-executable file. Continue
    // looking for another candidate rather than masking the fallback.
  }
  return null;
}

String _python3Executable({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final configured = env['LISTEN_E2E_GEN_PYTHON'];
  if (configured != null) {
    if (!Uri.file(configured).isAbsolute) {
      throw StateError(
        'LISTEN_E2E_GEN_PYTHON must be an absolute executable path: '
        '$configured',
      );
    }
    final executable = _probePythonExecutable(configured);
    if (executable != null) return executable;
    throw StateError(
      'LISTEN_E2E_GEN_PYTHON is not an executable Python runtime: '
      '$configured',
    );
  }

  final pathSeparator = Platform.isWindows ? ';' : ':';
  for (final directory in (env['PATH'] ?? '').split(pathSeparator)) {
    if (directory.isEmpty) continue;
    final candidate = File(
      '$directory${Platform.pathSeparator}python3',
    ).absolute.path;
    final executable = _probePythonExecutable(candidate);
    if (executable != null) return executable;
  }
  throw StateError('python3 is required for the Gen integration tests');
}

Future<LocalListenGenReleaseService> _releaseForProbeManifest() async {
  final manifestPath = Platform.environment['LISTEN_GEN_RELEASE_MANIFEST'];
  expect(
    manifestPath,
    isNotNull,
    reason: 'LISTEN_GEN_RELEASE_MANIFEST must point at the probe manifest',
  );
  final manifestFile = File(manifestPath!);
  final manifestBytes = await manifestFile.readAsBytes();
  final manifest =
      jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  final artifact = manifest['artifact'] as Map<String, dynamic>;
  final source = manifest['source'] as Map<String, dynamic>;
  final tool = manifest['tool'] as Map<String, dynamic>;
  final machineProtocol = manifest['machine_protocol'] as Map<String, dynamic>;
  final contract = manifest['content_package_contract'] as Map<String, dynamic>;
  final runtime = manifest['runtime'] as Map<String, dynamic>;
  final lock = <String, dynamic>{
    'manifest_version': 1,
    'repository': 'ichthyoplanktonzyh/listen-gen',
    'source_git_sha': source['commit'],
    'release_manifest': {
      'schema': manifest['schema'],
      'filename': manifestFile.uri.pathSegments.last,
      'sha256': 'sha256:${sha256.convert(manifestBytes)}',
    },
    'tool': tool,
    'machine_protocol': machineProtocol,
    'content_package_contract': contract,
    'runtime': {'python_requires': runtime['python_requires']},
    'runtime_identity': manifest['runtime_identity'],
    'artifact': artifact,
  };
  return LocalListenGenReleaseService(
    manifestPath: manifestPath,
    loadLockBytes: () async => utf8.encode(jsonEncode(lock)),
  );
}

Future<void> _assertFixtures() async {
  final manifest =
      jsonDecode(await _fixture('manifest.json').readAsString())
          as Map<String, dynamic>;
  expect(manifest['schema'], 'listen_app.content-package-roundtrip-fixture.v3');
  final files = manifest['files'] as Map<String, dynamic>;
  expect(files, isNotEmpty);
  for (final entry in files.entries) {
    final bytes = await _fixture(entry.key).readAsBytes();
    expect(
      sha256.convert(bytes).toString(),
      entry.value,
      reason: 'fixture ${entry.key} does not match its pinned hash',
    );
  }
  final streams = manifest['media_streams'] as Map<String, dynamic>;
  expect(streams['sample-media.wav'], ['audio']);
  expect(streams['sample-video.mp4'], ['video', 'audio']);
}

List<String> _asrArgs() => [
  '--provider',
  'fixture',
  '--fixture',
  _fixture('sample.asr.json').path,
  ..._simpleRichArgs(alignmentFile: 'simple.alignment.json'),
];

List<String> _documentTtsArgs() => [
  '--tts-provider',
  'fake',
  ..._simpleRichArgs(
    alignmentFile: 'document.alignment.json',
    fixturePrefix: 'document',
  ),
];

List<String> _subtitleArgs(String alignment) =>
    _simpleRichArgs(alignmentFile: alignment);

List<String> _simpleRichArgs({
  required String alignmentFile,
  String fixturePrefix = 'simple',
}) => [
  '--sense-groups',
  'fixture',
  '--sense-groups-fixture',
  _fixture('$fixturePrefix.sense-groups.json').path,
  '--acoustics',
  'fixture',
  '--acoustics-fixture',
  _fixture('$fixturePrefix.acoustics.json').path,
  '--prosody',
  'fixture',
  '--prosody-fixture',
  _fixture('$fixturePrefix.prosody.json').path,
  '--phones',
  'fixture',
  '--phones-fixture',
  _fixture('$fixturePrefix.phones.json').path,
  '--aligner',
  'fixture',
  '--aligner-fixture',
  _fixture(alignmentFile).path,
];

List<String> _fullRichArgs() => [
  '--aligner',
  'fixture',
  '--aligner-fixture',
  _fixture('full.alignment.json').path,
  '--sense-groups',
  'fixture',
  '--sense-groups-fixture',
  _fixture('full.sense-groups.json').path,
  '--acoustics',
  'fixture',
  '--acoustics-fixture',
  _fixture('full.acoustics.json').path,
  '--prosody',
  'fixture',
  '--prosody-fixture',
  _fixture('full.prosody.json').path,
  '--phones',
  'fixture',
  '--phones-fixture',
  _fixture('full.phones.json').path,
];

SubtitleTrack _subtitleTrack({
  required bool full,
  bool threeFragments = false,
}) {
  if (full) {
    if (threeFragments) {
      return const SubtitleTrack(
        id: 'fixture-three-fragment-subtitle',
        language: 'en',
        cues: [
          Cue(
            id: 'cue-0',
            index: 0,
            start: Duration(milliseconds: 100),
            end: Duration(milliseconds: 1450),
            text: 'Send us their name, photo, and a couple lines',
            tokens: [],
          ),
          Cue(
            id: 'cue-1',
            index: 1,
            start: Duration(milliseconds: 1460),
            end: Duration(milliseconds: 2750),
            text: 'about what they mean to you,',
            tokens: [],
          ),
          Cue(
            id: 'cue-2',
            index: 2,
            start: Duration(milliseconds: 2760),
            end: Duration(milliseconds: 3900),
            text: 'CNN10@cnn.com.',
            tokens: [],
          ),
        ],
      );
    }
    return const SubtitleTrack(
      id: 'fixture-full-subtitle',
      language: 'en',
      cues: [
        Cue(
          id: 'cue-0',
          index: 0,
          start: Duration(milliseconds: 100),
          end: Duration(milliseconds: 1850),
          text: 'Send us their name, photo, and a couple lines',
          tokens: [],
        ),
        Cue(
          id: 'cue-1',
          index: 1,
          start: Duration(milliseconds: 1860),
          end: Duration(milliseconds: 3900),
          text: 'about what they mean to you, CNN10@cnn.com.',
          tokens: [],
        ),
      ],
    );
  }
  return const SubtitleTrack(
    id: 'fixture-simple-subtitle',
    language: 'en',
    cues: [
      Cue(
        id: 'cue-0',
        index: 0,
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 1200),
        text: 'Listen, carefully!',
        tokens: [],
      ),
      Cue(
        id: 'cue-1',
        index: 1,
        start: Duration(milliseconds: 1300),
        end: Duration(milliseconds: 2100),
        text: 'Words matter.',
        tokens: [],
      ),
    ],
  );
}

Future<MaterialDetails> _createDocument(
  LocalApi api,
  String fileName,
  Directory managedRoot,
) async {
  final source = await _fixture(fileName).readAsBytes();
  final digest = sha256.convert(source).toString();
  await File('${managedRoot.path}/$digest').writeAsBytes(source, flush: true);
  final mediaType = switch (fileName) {
    'lesson.txt' => 'text/plain',
    'lesson.md' => 'text/markdown',
    'lesson.html' => 'text/html',
    'lesson.epub' => 'application/epub+zip',
    'lesson-text.pdf' || 'lesson-scanned.pdf' => 'application/pdf',
    _ => throw ArgumentError.value(fileName),
  };
  return _e2eStage(
    'register document fixture $fileName',
    api.createLearningMaterial(
      CreateLearningMaterialInput(
        title: fileName,
        sourceAssets: [
          SourceAssetInput(
            mediaType: mediaType,
            byteLength: source.length,
            sha256Digest: digest,
            binding: const SourceAssetBinding(
              type: SourceAssetBindingType.managed,
            ),
          ),
        ],
        documentRenditions: [
          DocumentRenditionInput(
            mediaType: mediaType,
            digest: digest,
            byteSize: source.length,
            language: 'en',
            sourceAssetIndex: 0,
          ),
        ],
        mediaRenditions: const [],
      ),
    ),
  );
}

Future<({MaterialDetails material, MediaItem media, String path})> _media(
  LocalApi api,
  String fileName,
  bool video,
) async {
  final path = _fixture(fileName).absolute.path;
  final media = await _e2eStage(
    'register ${video ? 'video' : 'audio'} fixture $fileName',
    api.registerMedia(path, retain: false, kind: video ? 'video' : 'audio'),
  );
  final material = await _e2eStage(
    'resolve ${video ? 'video' : 'audio'} fixture $fileName',
    api.resolveMaterialForMedia(media.id),
  );
  return (material: material, media: media, path: path);
}

Future<({LearningEdition edition, ResolvedComposition composition})> _produce(
  LocalApi api,
  MaterialDetails material, {
  required List<String> providerArguments,
  Future<String?> Function(MediaRendition rendition)? mediaFilePath,
  String? managedStoreRoot,
  SubtitleTrack? subtitleTrack,
  required MaterialCapability capability,
  required String label,
}) async {
  final release = await _e2eStage(
    '$label release manifest load',
    _releaseForProbeManifest(),
  );
  final verified = await _e2eStage(
    '$label release verification',
    release.verify(),
  );
  final generator = LocalListenGenProcessService(
    pythonExecutable: _python3Executable,
    releaseService: release,
  );
  final coordinator = MaterialCapabilityCoordinator(
    repository: LocalCapabilityRepository(() => api),
    generator: generator,
    mediaFilePath: mediaFilePath,
    fileResolver: LocalCapabilityFileResolver(
      managedStorePath: managedStoreRoot == null
          ? null
          : (asset) => '$managedStoreRoot/${asset.sha256Digest}',
      mediaFilePath: mediaFilePath,
    ),
    subtitleTrackForMedia: subtitleTrack == null ? null : (_) => subtitleTrack,
    providerArguments: () => providerArguments,
  );
  try {
    final outcome = await _e2eStage(
      '$label Gen/Core production, install, and adoption',
      coordinator.requestCapability(material, capability),
    );
    if (outcome is CapabilityFailed) {
      final error = outcome.error;
      if (error is ListenGenProcessFailure) {
        fail('$label failed: ${error.code} ${error.message}');
      }
      fail('$label failed: $error');
    }
    expect(outcome, isA<CapabilityAvailable>(), reason: label);
    final edition = (outcome as CapabilityAvailable).edition;
    expect(edition, isNotNull, reason: '$label must adopt a package edition');
    expect(edition!.adopted, isTrue);
    expect(edition.releaseId, isNotEmpty, reason: '$label release identity');
    final projection = (await _e2eStage(
      '$label Core attempt readback',
      api.listMaterialCapabilities(material.material.id),
    )).singleWhere((entry) => entry.capability == capability);
    final attempt = projection.latestAttempt;
    expect(attempt, isNotNull, reason: '$label must record a durable attempt');
    expect(attempt!.status, 'succeeded', reason: '$label attempt');
    expect(attempt.producerToolId, 'listen-gen', reason: '$label producer');
    expect(
      attempt.producerToolVersion,
      verified.toolVersion,
      reason: '$label dynamic Gen release version',
    );
    final composition = await _e2eStage(
      '$label Core composition resolution',
      CompositionSessionService(
        repository: LocalCapabilityRepository(() => api),
        resources: LocalResourceRepository(() => api),
      ).resolveComposition(material.material.id),
    );
    expect(
      composition,
      isNotNull,
      reason: '$label must resolve its adopted composition through Core',
    );
    return (edition: edition, composition: composition!);
  } finally {
    coordinator.dispose();
  }
}

void _assertCommonComposition(
  ResolvedComposition composition, {
  required String label,
  required String expectedText,
}) {
  String normalized(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();
  expect(
    normalized(composition.logicalText),
    contains(normalized(expectedText)),
    reason: label,
  );
  expect(composition.sentences, isNotEmpty, reason: label);
  final transcript = composition.transcript;
  expect(transcript, isNotNull, reason: '$label must expose Core text');
  expect(transcript!.cues, isNotEmpty, reason: label);
  expect(
    transcript.cues.every(
      (cue) => cue.tokens.any((token) => token.kind == 'word'),
    ),
    isTrue,
    reason: '$label must expose interactive word tokens',
  );
  final enhancements = composition.enhancements;
  expect(
    enhancements.timingsBySentence.values.expand((values) => values),
    isNotEmpty,
    reason: '$label must expose word timings',
  );
  expect(
    enhancements.senseGroupsBySentence.values.expand((values) => values),
    isNotEmpty,
    reason: '$label must expose sense groups',
  );
  expect(
    enhancements.chunkPartitionsBySentence.values.expand(
      (partition) => partition.chunks,
    ),
    isNotEmpty,
    reason: '$label must expose prosodic chunks',
  );
  expect(
    enhancements.acousticsBySentence.values.expand((values) => values),
    isNotEmpty,
    reason: '$label must expose word acoustics',
  );
  expect(
    enhancements.prosodyAnchorsBySentence.values.expand((values) => values),
    isNotEmpty,
    reason: '$label must expose prosody anchors',
  );
  expect(
    enhancements.phonesBySentence.values.expand((values) => values),
    isNotEmpty,
    reason: '$label must expose phone timings',
  );
}

void _assertPackageShape(
  LearningEdition edition,
  MaterialDetails material, {
  required String label,
}) {
  final resourceKinds = edition.resources
      .map((resource) => resource.kind)
      .toSet();
  expect(
    resourceKinds,
    containsAll(const [
      'structured_reading',
      'anchor_time_alignment',
      'subtitle_text_track',
      'word_timeline',
      'sense_group_analysis',
      'word_acoustics',
      'prosody_analysis',
      'phone_timeline',
    ]),
    reason: '$label must land the common reading/alignment package shape',
  );
  expect(
    edition.renditions.any(
      (rendition) => rendition.kind == 'media' && rendition.available,
    ),
    isTrue,
    reason: '$label must land a playable audio/media rendition',
  );
  final sourceIsVideo = material.currentRevision.mediaRenditions.any(
    (rendition) => rendition.kind == MediaRenditionKind.video,
  );
  final sourceKinds = material.currentRevision.mediaRenditions
      .map((rendition) => rendition.kind)
      .toSet();
  expect(sourceIsVideo, sourceKinds.contains(MediaRenditionKind.video));
  if (sourceIsVideo) {
    expect(
      sourceKinds,
      contains(MediaRenditionKind.video),
      reason: '$label video pane must be backed by a video source fact',
    );
  } else {
    expect(
      sourceKinds,
      isNot(contains(MediaRenditionKind.video)),
      reason: '$label must not invent a video stream',
    );
  }
}

String _transcriptText(ResolvedComposition composition) =>
    composition.transcript!.cues.map((cue) => cue.text).join(' ');

Future<bool> _showVideoPaneFromCore(
  LocalApi api,
  MaterialDetails material,
) async {
  final current = await _e2eStage(
    'read source rendition facts for ${material.material.id}',
    api.readLearningMaterial(material.material.id),
  );
  final adopted = await _e2eStage(
    'read adopted composition for ${material.material.id}',
    api.readAdoptedComposition(material.material.id),
  );
  final sourceIsVideo = current.currentRevision.mediaRenditions.any(
    (rendition) => rendition.kind == MediaRenditionKind.video,
  );
  // A derived document audio rendition is not a source video. The pane is
  // therefore enabled only when Core's adopted composition still carries a
  // source media binding and the material's source facts identify a video.
  return sourceIsVideo && adopted.workbenchMediaId != null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final runE2e = Platform.environment['LISTEN_PACKAGE_E2E'] == '1';

  test(
    'Gen E2E Python runtime validates the override before PATH fallback',
    () {
      final root = Directory.systemTemp.createTempSync(
        'content-package-python-runtime-',
      );
      addTearDown(() => root.deleteSync(recursive: true));

      File writePythonShim(String name) {
        final file = File('${root.path}/$name')
          ..writeAsStringSync('#!/bin/sh\necho Python 3.11.0\n');
        Process.runSync('/bin/chmod', ['755', file.path]);
        return file;
      }

      final configured = writePythonShim('gen-python');
      final fallbackDirectory = Directory('${root.path}/fallback')
        ..createSync();
      final fallback = File('${fallbackDirectory.path}/python3')
        ..writeAsStringSync('#!/bin/sh\necho Python 3.11.0\n');
      Process.runSync('/bin/chmod', ['755', fallback.path]);

      expect(
        _python3Executable(
          environment: {
            'LISTEN_E2E_GEN_PYTHON': configured.path,
            'PATH': fallbackDirectory.path,
          },
        ),
        configured.absolute.path,
      );
      expect(
        () => _python3Executable(
          environment: {
            'LISTEN_E2E_GEN_PYTHON': '${root.path}/missing-python',
            'PATH': fallbackDirectory.path,
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('LISTEN_E2E_GEN_PYTHON'),
          ),
        ),
      );
      expect(
        _python3Executable(environment: {'PATH': fallbackDirectory.path}),
        fallback.absolute.path,
      );
    },
    skip: !runE2e || Platform.isWindows
        ? 'Set LISTEN_PACKAGE_E2E=1 on a Unix runner for the runtime test'
        : false,
  );

  test(
    _matrixName,
    () async {
      HttpOverrides.global = null;
      await _assertFixtures();
      final documents = <({String file, bool ocr})>[
        (file: 'lesson.txt', ocr: false),
        (file: 'lesson.md', ocr: false),
        (file: 'lesson.html', ocr: false),
        (file: 'lesson.epub', ocr: false),
        (file: 'lesson-text.pdf', ocr: false),
        (file: 'lesson-scanned.pdf', ocr: true),
      ];
      for (final item in documents) {
        // Each material family gets a clean Core database. This is important
        // for the two subtitle branches: Core identity convergence must not
        // let a prior adopted package satisfy a later case.
        final api = await LocalApi.connect(
          databasePath: scratchDatabasePath('content-matrix-${item.file}'),
        );
        final root = await Directory.systemTemp.createTemp('e2e-doc-');
        try {
          final material = await _createDocument(api, item.file, root);
          final args = _documentTtsArgs();
          if (item.ocr) {
            args.addAll([
              '--ocr-provider',
              'fixture',
              '--ocr-fixture',
              _fixture('ocr.txt').path,
            ]);
          }
          final result = await _produce(
            api,
            material,
            managedStoreRoot: root.path,
            providerArguments: args,
            capability: MaterialCapability.listen,
            label: item.file,
          );
          _assertPackageShape(result.edition, material, label: item.file);
          expect(result.edition.providesSynchronizedReadListen, isTrue);
          expect(result.composition.derivedMediaPath, isNotNull);
          _assertCommonComposition(
            result.composition,
            label: item.file,
            expectedText: 'Listen, carefully! Words matter.',
          );
        } finally {
          await api.close();
          await root.delete(recursive: true);
        }
      }

      final noOcrApi = await LocalApi.connect(
        databasePath: scratchDatabasePath('content-matrix-no-ocr'),
      );
      final noOcrRoot = await Directory.systemTemp.createTemp(
        'e2e-doc-no-ocr-',
      );
      try {
        final noOcr = await _createDocument(
          noOcrApi,
          'lesson-scanned.pdf',
          noOcrRoot,
        );
        final failed = await _produceExpectingFailure(
          noOcrApi,
          noOcr,
          managedStoreRoot: noOcrRoot.path,
          providerArguments: _documentTtsArgs(),
          capability: MaterialCapability.listen,
        );
        final error = failed.error;
        expect(error, isA<ListenGenProcessFailure>());
        expect(
          (error as ListenGenProcessFailure).code,
          'document_text_unavailable',
          reason: 'scanned PDF without OCR must abstain honestly',
        );
        final projection =
            (await noOcrApi.listMaterialCapabilities(
              noOcr.material.id,
            )).singleWhere(
              (entry) => entry.capability == MaterialCapability.listen,
            );
        expect(projection.latestAttempt?.status, 'failed');
      } finally {
        await noOcrApi.close();
        await noOcrRoot.delete(recursive: true);
      }

      final mediaCases =
          <
            ({
              String file,
              bool video,
              SubtitleTrack? subtitle,
              List<String> args,
            })
          >[
            (
              file: 'sample-media.wav',
              video: false,
              subtitle: null,
              args: _asrArgs(),
            ),
            (
              file: 'sample-media.wav',
              video: false,
              subtitle: _subtitleTrack(full: false),
              args: _subtitleArgs('simple.alignment.json'),
            ),
            (
              file: 'sample-video.mp4',
              video: true,
              subtitle: null,
              args: _asrArgs(),
            ),
            (
              file: 'sample-video.mp4',
              video: true,
              subtitle: _subtitleTrack(full: false),
              args: _subtitleArgs('simple.alignment.json'),
            ),
          ];
      for (var index = 0; index < mediaCases.length; index += 1) {
        final item = mediaCases[index];
        final api = await LocalApi.connect(
          databasePath: scratchDatabasePath('content-matrix-media-$index'),
        );
        try {
          final value = await _media(api, item.file, item.video);
          final result = await _produce(
            api,
            value.material,
            providerArguments: item.args,
            mediaFilePath: (rendition) async =>
                rendition.mediaId == value.media.id ? value.path : null,
            subtitleTrack: item.subtitle,
            // Watch is deliberately not used as the production gate: source
            // video can satisfy Watch without invoking Gen. Synchronized
            // Read+Listen requires the generated text/alignment package while
            // retaining the source audio/video rendition.
            capability: MaterialCapability.synchronizedReadListen,
            label: '${item.file}:${item.subtitle == null ? 'asr' : 'subtitle'}',
          );
          _assertPackageShape(
            result.edition,
            value.material,
            label: '${item.file}:${item.subtitle == null ? 'asr' : 'subtitle'}',
          );
          expect(result.edition.hasAvailableMediaRendition, isTrue);
          expect(result.edition.providesSynchronizedReadListen, isTrue);
          _assertCommonComposition(
            result.composition,
            label: item.file,
            expectedText: 'Listen, carefully! Words matter.',
          );
        } finally {
          await api.close();
        }
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the real content-family matrix',
  );

  test(
    _richName,
    () async {
      HttpOverrides.global = null;
      await _assertFixtures();
      final api = await LocalApi.connect(
        databasePath: scratchDatabasePath('content-rich'),
      );
      try {
        final value = await _media(api, 'sample-video.mp4', true);
        final result = await _produce(
          api,
          value.material,
          providerArguments: _fullRichArgs(),
          mediaFilePath: (rendition) async =>
              rendition.mediaId == value.media.id ? value.path : null,
          subtitleTrack: _subtitleTrack(full: true, threeFragments: true),
          capability: MaterialCapability.synchronizedReadListen,
          label: 'fragmented video subtitle',
        );
        final composition = result.composition;
        _assertPackageShape(
          result.edition,
          value.material,
          label: 'fragmented video subtitle',
        );
        _assertCommonComposition(
          composition,
          label: 'fragmented video subtitle',
          expectedText:
              'Send us their name, photo, and a couple lines about what they mean to you, CNN10@cnn.com.',
        );
        final transcript = composition.transcript!;
        expect(transcript.cues, hasLength(1));
        expect(_transcriptText(composition), contains('a couple lines about'));
        expect(composition.enhancements.timingsBySentence.keys, hasLength(1));
        final sentenceId = transcript.cues.single.id;
        expect(
          composition.enhancements.timingsBySentence.keys,
          contains(sentenceId),
        );
        expect(
          composition.enhancements.senseGroupsBySentence.keys,
          contains(sentenceId),
        );
        expect(
          composition.enhancements.acousticsBySentence.keys,
          contains(sentenceId),
        );
        expect(
          composition.enhancements.prosodyAnchorsBySentence.keys,
          contains(sentenceId),
        );
        expect(
          composition.enhancements.phonesBySentence.keys,
          contains(sentenceId),
        );
        final timings = composition.enhancements.timingsBySentence[sentenceId]!;
        expect(timings.first.start.inMilliseconds, 100);
        expect(timings.last.end.inMilliseconds, 3104);
        expect(
          timings.every(
            (timing) =>
                timing.start >= transcript.cues.first.start &&
                timing.end <= transcript.cues.last.end,
          ),
          isTrue,
        );
        final phones = composition.enhancements.phonesBySentence[sentenceId]!;
        expect(phones, isNotEmpty);
        expect(phones.every((phone) => phone.tokenIndex != null), isTrue);
        expect(
          phones.every(
            (phone) =>
                phone.start >= transcript.cues.first.start &&
                phone.end <= transcript.cues.last.end,
          ),
          isTrue,
          reason: 'phone times must remain absolute after Core re-keying',
        );
      } finally {
        await api.close();
      }
    },
    skip: runE2e
        ? false
        : 'Set LISTEN_PACKAGE_E2E=1 for the full rich package gate',
  );

  testWidgets(_renderName, (tester) async {
    // Widget tests run in FakeAsync. Keep all real Core/Gen process and HTTP
    // work on the real event loop, then mount only immutable adopted results
    // in the widget zone. This avoids a sidecar close or process handoff being
    // held by fake timers after the final pumpWidget.
    final render = await tester.runAsync(() async {
      HttpOverrides.global = null;
      await _e2eStage('render fixture verification', _assertFixtures());
      final api = await _e2eStage(
        'render Core sidecar connect',
        LocalApi.connect(databasePath: scratchDatabasePath('content-render')),
      );
      final managed = <Directory>[];
      try {
        final documentRoot = await _e2eStage(
          'render document temporary store setup',
          Directory.systemTemp.createTemp('e2e-render-doc-'),
        );
        managed.add(documentRoot);
        final document = await _createDocument(api, 'lesson.txt', documentRoot);
        final documentResult = await _produce(
          api,
          document,
          managedStoreRoot: documentRoot.path,
          providerArguments: _documentTtsArgs(),
          capability: MaterialCapability.listen,
          label: 'document render',
        );
        _assertPackageShape(
          documentResult.edition,
          document,
          label: 'document render',
        );
        expect(documentResult.composition.derivedMediaPath, isNotNull);

        final audio = await _media(api, 'sample-media.wav', false);
        final audioResult = await _produce(
          api,
          audio.material,
          providerArguments: _asrArgs(),
          mediaFilePath: (rendition) async =>
              rendition.mediaId == audio.media.id ? audio.path : null,
          capability: MaterialCapability.synchronizedReadListen,
          label: 'audio render',
        );
        _assertPackageShape(
          audioResult.edition,
          audio.material,
          label: 'audio render',
        );
        expect(File(audio.path).existsSync(), isTrue);
        expect(audioResult.composition.transcript, isNotNull);
        final audioShowVideoPane = await _e2eStage(
          'audio render source-video projection',
          _showVideoPaneFromCore(api, audio.material),
        );
        expect(audioShowVideoPane, isFalse);

        final video = await _media(api, 'sample-video.mp4', true);
        final videoResult = await _produce(
          api,
          video.material,
          providerArguments: _asrArgs(),
          mediaFilePath: (rendition) async =>
              rendition.mediaId == video.media.id ? video.path : null,
          capability: MaterialCapability.synchronizedReadListen,
          label: 'video render',
        );
        _assertPackageShape(
          videoResult.edition,
          video.material,
          label: 'video render',
        );
        expect(File(video.path).existsSync(), isTrue);
        expect(videoResult.composition.transcript, isNotNull);
        final videoShowVideoPane = await _e2eStage(
          'video render source-video projection',
          _showVideoPaneFromCore(api, video.material),
        );
        expect(videoShowVideoPane, isTrue);

        return (
          document: (material: document, result: documentResult),
          audio: (result: audioResult, showVideoPane: audioShowVideoPane),
          video: (result: videoResult, showVideoPane: videoShowVideoPane),
        );
      } finally {
        try {
          await _e2eStage('render Core sidecar shutdown', api.close());
        } finally {
          for (final directory in managed) {
            await _e2eStage(
              'render temporary store cleanup',
              directory.delete(recursive: true),
            );
          }
        }
      }
    });
    expect(render, isNotNull, reason: 'render setup must return adopted data');
    final data = render!;
    final documentResult = data.document.result;
    await _pumpDocumentMaterialSurface(
      tester,
      data.document.material,
      documentResult.composition,
    );
    expect(find.byType(MaterialWorkbench), findsOneWidget);
    _assertCommonWorkbenchControls(tester);
    expect(find.byKey(const Key('media-workbench-splitter')), findsNothing);
    expect(find.byKey(const Key('workbench-media-title')), findsNothing);
    expect(
      find.text(_transcriptText(documentResult.composition)),
      findsOneWidget,
    );

    final audioResult = data.audio.result;
    expect(data.audio.showVideoPane, isFalse);
    await tester.pumpWidget(
      _workbenchHost(
        MaterialWorkbench(
          materialTitle: 'fixture-audio',
          videoPane: data.audio.showVideoPane
              ? const SizedBox(key: Key('audio-player'))
              : null,
          learningPanel: Text(_transcriptText(audioResult.composition)),
          studyMenu: _renderControl('common-study'),
          translationMenu: _renderControl('common-translation'),
          listeningMenu: _renderControl('common-listening'),
          mediaFraction: MaterialWorkbench.defaultMediaFraction,
          onMediaFractionChanged: (_) {},
        ),
      ),
    );
    await _pumpWorkbenchFrames(tester);
    expect(find.byType(MaterialWorkbench), findsOneWidget);
    _assertCommonWorkbenchControls(tester);
    expect(find.byKey(const Key('media-workbench-splitter')), findsNothing);
    expect(find.byKey(const Key('workbench-media-title')), findsNothing);
    expect(find.textContaining('Listen, carefully!'), findsOneWidget);

    final videoResult = data.video.result;
    expect(data.video.showVideoPane, isTrue);
    await tester.pumpWidget(
      _workbenchHost(
        MaterialWorkbench(
          materialTitle: 'fixture-video',
          videoPane: data.video.showVideoPane
              ? const SizedBox(key: Key('video-player'))
              : null,
          learningPanel: Text(_transcriptText(videoResult.composition)),
          studyMenu: _renderControl('common-study'),
          translationMenu: _renderControl('common-translation'),
          listeningMenu: _renderControl('common-listening'),
          mediaFraction: MaterialWorkbench.defaultMediaFraction,
          onMediaFractionChanged: (_) {},
        ),
      ),
    );
    await _pumpWorkbenchFrames(tester);
    expect(find.byType(MaterialWorkbench), findsOneWidget);
    _assertCommonWorkbenchControls(tester);
    expect(find.byKey(const Key('workbench-media-title')), findsOneWidget);
    expect(find.byKey(const Key('media-workbench-splitter')), findsOneWidget);
    expect(find.byKey(const Key('video-player')), findsOneWidget);
    expect(find.textContaining('Listen, carefully!'), findsOneWidget);
  }, skip: !runE2e);
}

Future<CapabilityFailed> _produceExpectingFailure(
  LocalApi api,
  MaterialDetails material, {
  required List<String> providerArguments,
  String? managedStoreRoot,
  required MaterialCapability capability,
}) async {
  final release = await _e2eStage(
    'negative ${capability.name} release manifest load',
    _releaseForProbeManifest(),
  );
  final coordinator = MaterialCapabilityCoordinator(
    repository: LocalCapabilityRepository(() => api),
    generator: LocalListenGenProcessService(
      pythonExecutable: _python3Executable,
      releaseService: release,
    ),
    fileResolver: LocalCapabilityFileResolver(
      managedStorePath: managedStoreRoot == null
          ? null
          : (asset) => '$managedStoreRoot/${asset.sha256Digest}',
    ),
    providerArguments: () => providerArguments,
  );
  try {
    final outcome = await _e2eStage(
      'negative ${capability.name} generation failure',
      coordinator.requestCapability(material, capability),
    );
    expect(outcome, isA<CapabilityFailed>());
    return outcome as CapabilityFailed;
  } finally {
    coordinator.dispose();
  }
}

Future<void> _pumpDocumentMaterialSurface(
  WidgetTester tester,
  MaterialDetails details,
  ResolvedComposition composition,
) async {
  final fakeRepository = FakeLearningMaterialRepository();
  final controller = DocumentSessionController(
    materialRepository: fakeRepository,
    fileService: FakeDocumentIntakeFileService(),
    intakeFlow: DocumentIntakeFlow(
      materialRepository: fakeRepository,
      codec: LocalDocumentIntakeCodec(),
      store: FakeManagedAssetStoreService(),
      referenceStore: FakeDocumentReferenceStore(),
    ),
    sourceResolver: FakeDocumentSourceResolver(),
    resolveComposition: (_) async => composition,
  );
  try {
    controller.openLibraryEntry(
      PersonalLibraryEntry(details: details, mediaEntries: const []),
    );
    await _e2eStage(
      'document render composition projection',
      controller.refreshComposition(),
    );
    final resolved = controller.state;
    expect(resolved, isA<DocumentSessionReady>());
    final ready = resolved as DocumentSessionReady;
    expect(ready.composition, isNotNull);
    await tester.pumpWidget(
      _workbenchHost(
        DocumentMaterialSurface(
          controller: controller,
          mediaFraction: MaterialWorkbench.defaultMediaFraction,
          onMediaFractionChanged: (_) {},
          timedLearningPanel: Text(_transcriptText(ready.composition!)),
          studyMenu: _renderControl('common-study'),
          translationMenu: _renderControl('common-translation'),
          listeningMenu: _renderControl('common-listening'),
        ),
      ),
    );
    await _pumpWorkbenchFrames(tester);
  } finally {
    // The helper is called before the audio/video pumpWidget calls. Dispose
    // this controller here so no document listener survives that transition.
    controller.dispose();
  }
}

Widget _renderControl(String key) => IconButton(
  key: Key(key),
  onPressed: () {},
  icon: const Icon(Icons.circle_outlined),
);

void _assertCommonWorkbenchControls(WidgetTester tester) {
  expect(find.byKey(const Key('common-study')), findsOneWidget);
  expect(find.byKey(const Key('common-translation')), findsOneWidget);
  expect(find.byKey(const Key('common-listening')), findsOneWidget);
}

/// The workbench owns an intentional settle animation, so this gate must not
/// wait for global quiescence: the app may keep a player/overlay ticker alive.
Future<void> _pumpWorkbenchFrames(WidgetTester tester) async {
  for (var index = 0; index < 8; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _workbenchHost(Widget child) => MaterialApp(
  theme: ListenTheme.light(),
  locale: const Locale('en'),
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: Scaffold(body: child),
);
