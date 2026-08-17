import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/content_generator_setup.dart';

/// Finding the generation toolchain is the app's job, not the user's.
///
/// The real incident: generation was reachable only by exporting
/// `LISTEN_GEN_EXECUTABLE` and `LISTEN_GEN_PROVIDER_ARGUMENTS`, the second of
/// which was a hand-written nested-escaped JSON array carrying a python
/// interpreter, a wrapper script path, a `{media}` placeholder and a provider
/// protocol. All four are `listen-gen` internals. Worse, environment
/// variables exported in a terminal do not exist for an app launched from
/// Finder, so the documented setup only worked under `flutter run`.
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('generator-setup-'));
  tearDown(() => root.deleteSync(recursive: true));

  File touch(String relative, {int bytes = 1}) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List.filled(bytes, 0));
    return file;
  }

  File compatiblePython(String relative) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('/bin/chmod', ['755', file.path]);
    return file;
  }

  const modelDirectory = 'Library/Application Support/listen/models/whisper';

  ContentGeneratorLocator locator({
    String modelPath = '',
  }) => ContentGeneratorLocator(
    modelPath: modelPath,
    pythonPath: compatiblePython('bin/python3').path,
    pythonCompatibilityProbe: (_) async => true,
    // Pinned so a resolution never silently depends on the machine running
    // the suite; the fallbacks under /opt and /usr are unreachable from here.
    whisperPath: touch('bin/whisper-cli').path,
    ffprobePath: touch('bin/ffprobe').path,
    ffmpegPath: touch('bin/ffmpeg').path,
    environment: {'HOME': root.path},
  );

  test(
    'a Finder launch resolves a compatible Python directly instead of using its PATH',
    () async {
      touch('$modelDirectory/ggml-base.bin');
      final python = compatiblePython('runtime/python3');

      final setup = await ContentGeneratorLocator(
        pythonPath: python.path,
        pythonCompatibilityProbe: (candidate) async => candidate == python.path,
        whisperPath: touch('bin/whisper-cli').path,
        ffprobePath: touch('bin/ffprobe').path,
        ffmpegPath: touch('bin/ffmpeg').path,
        environment: {
          'HOME': root.path,
          'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
        },
      ).resolve();

      expect(setup.pythonPath, python.path);
      expect(setup.state, ContentGeneratorState.ready);
    },
  );

  test('Python older than 3.11 is an unavailable prerequisite', () async {
    touch('$modelDirectory/ggml-base.bin');
    final oldPython = compatiblePython('bin/python3');

    final setup = await ContentGeneratorLocator(
      pythonPath: oldPython.path,
      pythonCompatibilityProbe: (_) async => false,
      whisperPath: touch('bin/whisper-cli').path,
      ffprobePath: touch('bin/ffprobe').path,
      ffmpegPath: touch('bin/ffmpeg').path,
      environment: {'HOME': root.path, 'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'},
    ).resolve();

    expect(setup.pythonPath, isEmpty);
    expect(setup.state, ContentGeneratorState.pythonMissing);
  });

  test('the whisper model is found in the shared models directory', () async {
    final model = touch('$modelDirectory/ggml-base.bin');

    final setup = await locator().resolve();

    expect(setup.modelPath, model.path);
  });

  test('the largest installed model wins', () async {
    // Model files grow with capability, so someone who downloaded a bigger one
    // meant to use it. Sizes are deliberately not in directory order.
    touch('$modelDirectory/ggml-base.bin', bytes: 200);
    final large = touch('$modelDirectory/ggml-large.bin', bytes: 900);
    touch('$modelDirectory/ggml-tiny.bin', bytes: 50);

    final setup = await locator().resolve();

    expect(setup.modelPath, large.path);
  });

  test('a configured path overrides the lookup', () async {
    touch('$modelDirectory/ggml-base.bin', bytes: 900);
    final chosen = touch('elsewhere/ggml-small.bin', bytes: 10);

    final setup = await locator(modelPath: chosen.path).resolve();

    // Smaller than the discovered one, and still chosen: an explicit setting
    // is a decision, not a hint.
    expect(setup.modelPath, chosen.path);
  });

  test(
    'a configured path that no longer exists falls back to the lookup',
    () async {
      final present = touch('$modelDirectory/ggml-base.bin');

      final setup = await locator(
        modelPath: '${root.path}/deleted.bin',
      ).resolve();

      // A stale setting must not strand a machine that has a usable model.
      expect(setup.modelPath, present.path);
      expect(setup.state, ContentGeneratorState.ready);
    },
  );

  test('a missing whisper model is reported by the tool locator', () async {
    final noModel = await locator().resolve();
    expect(noModel.state, ContentGeneratorState.modelMissing);
  });

  test(
    'an empty model directory is not mistaken for an installed model',
    () async {
      Directory('${root.path}/$modelDirectory').createSync(recursive: true);

      final setup = await locator().resolve();

      expect(setup.state, ContentGeneratorState.modelMissing);
      expect(setup.modelPath, isEmpty);
    },
  );

  test(
    'the provider argv names whisper-cpp and carries no app internals',
    () async {
      touch('$modelDirectory/ggml-base.bin');

      final arguments = contentGeneratorProviderArguments(
        await locator().resolve(),
      );

      expect(arguments.sublist(0, 2), ['--provider', 'whisper-cpp']);
      expect(arguments, contains('--whisper-model'));
      // The deterministic rich baselines are in-generator stages with no
      // external toolchain, so they are always on.
      expect(arguments, containsAll(['--sense-groups', 'baseline']));
      expect(arguments, containsAll(['--acoustics', 'baseline']));
      expect(arguments, containsAll(['--prosody', 'baseline']));
      // The wrapper protocol this replaced is gone: no placeholder, no script,
      // no interpreter. If any reappears, it belongs in listen-gen instead.
      expect(arguments.any((item) => item.contains('{media}')), isFalse);
      expect(arguments.any((item) => item.endsWith('.py')), isFalse);
    },
  );

  test(
    'the forced-alignment toolchain is discovered in the listen-core checkout',
    () async {
      touch('$modelDirectory/ggml-base.bin');
      final python = touch('LLPlayerNext/.venv/bin/python');
      final aligner = touch('listen-core/scripts/forced-align/align-cli.py');
      touch('listen-core/scripts/wav2vec2-phoneme-cli.py');
      Directory(
        '${root.path}/Library/Application Support/LLPlayerNext/models/'
        'wav2vec2-phoneme',
      ).createSync(recursive: true);

      final setup = await locator().resolve();

      expect(setup.alignerPython, python.path);
      expect(setup.alignerScript, aligner.path);
      expect(setup.phoneSidecar, isNotEmpty);
      expect(setup.phoneModelDir, isNotEmpty);
    },
  );

  test(
    'a partial aligner toolchain resolves but contributes no argv',
    () async {
      touch('$modelDirectory/ggml-base.bin');
      // The venv python exists but no sidecar scripts are checked out.
      touch('LLPlayerNext/.venv/bin/python');

      final setup = await locator().resolve();
      final arguments = contentGeneratorProviderArguments(setup);

      expect(setup.state, ContentGeneratorState.ready);
      expect(arguments, isNot(contains('--aligner')));
      expect(arguments, isNot(contains('--phones')));
    },
  );

  test('a complete toolchain contributes aligner and phoneme argv', () async {
    touch('$modelDirectory/ggml-base.bin');
    touch('LLPlayerNext/.venv/bin/python');
    touch('listen-core/scripts/forced-align/align-cli.py');
    touch('listen-core/scripts/wav2vec2-phoneme-cli.py');
    Directory(
      '${root.path}/Library/Application Support/LLPlayerNext/models/'
      'wav2vec2-phoneme',
    ).createSync(recursive: true);

    final arguments = contentGeneratorProviderArguments(
      await locator().resolve(),
    );

    expect(
      arguments,
      containsAll(['--aligner', 'torchaudio', '--phones', 'wav2vec2']),
    );
    expect(
      arguments[arguments.indexOf('--aligner-python') + 1],
      '${root.path}/LLPlayerNext/.venv/bin/python',
    );
    // Model identity is pinned to the sidecar contract, never guessed.
    expect(arguments, contains('--phones-wav2vec2-model-id'));
    expect(arguments, contains('facebook/wav2vec2-lv-60-espeak-cv-ft'));
  });

  test(
    'the phoneme model directory honors the toolchain env override',
    () async {
      touch('$modelDirectory/ggml-base.bin');
      touch('LLPlayerNext/.venv/bin/python');
      touch('listen-core/scripts/forced-align/align-cli.py');
      touch('listen-core/scripts/wav2vec2-phoneme-cli.py');
      final modelDir = Directory('${root.path}/elsewhere/phoneme-model')
        ..createSync(recursive: true);

      final setup = await ContentGeneratorLocator(
        whisperPath: touch('bin/whisper-cli').path,
        ffprobePath: touch('bin/ffprobe').path,
        ffmpegPath: touch('bin/ffmpeg').path,
        environment: {
          'HOME': root.path,
          'LLPLAYERNEXT_PHONEME_MODEL_DIR': modelDir.path,
        },
      ).resolve();

      expect(setup.phoneModelDir, modelDir.path);
    },
  );
}
