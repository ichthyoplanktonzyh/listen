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

  const modelDirectory = 'Library/Application Support/listen/models/whisper';

  ContentGeneratorLocator locator({
    String generatorPath = '',
    String modelPath = '',
  }) => ContentGeneratorLocator(
    generatorPath: generatorPath,
    modelPath: modelPath,
    // Pinned so a resolution never silently depends on the machine running
    // the suite; the fallbacks under /opt and /usr are unreachable from here.
    whisperPath: touch('bin/whisper-cli').path,
    ffprobePath: touch('bin/ffprobe').path,
    ffmpegPath: touch('bin/ffmpeg').path,
    environment: {'HOME': root.path},
  );

  test(
    'a checked-out working copy is found without any configuration',
    () async {
      // How this is actually developed today: the console script lives in the
      // repository's virtualenv, which is on no PATH a GUI launch would see.
      final generator = touch('listen-gen/.venv/bin/listen-gen');
      touch('$modelDirectory/ggml-base.bin');

      final setup = await locator().resolve();

      expect(setup.state, ContentGeneratorState.ready);
      expect(setup.generatorPath, generator.path);
    },
  );

  test('the whisper model is found in the shared models directory', () async {
    touch('listen-gen/.venv/bin/listen-gen');
    final model = touch('$modelDirectory/ggml-base.bin');

    final setup = await locator().resolve();

    expect(setup.modelPath, model.path);
  });

  test('the largest installed model wins', () async {
    // Model files grow with capability, so someone who downloaded a bigger one
    // meant to use it. Sizes are deliberately not in directory order.
    touch('listen-gen/.venv/bin/listen-gen');
    touch('$modelDirectory/ggml-base.bin', bytes: 200);
    final large = touch('$modelDirectory/ggml-large.bin', bytes: 900);
    touch('$modelDirectory/ggml-tiny.bin', bytes: 50);

    final setup = await locator().resolve();

    expect(setup.modelPath, large.path);
  });

  test('a configured path overrides the lookup', () async {
    touch('listen-gen/.venv/bin/listen-gen');
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
      touch('listen-gen/.venv/bin/listen-gen');
      final present = touch('$modelDirectory/ggml-base.bin');

      final setup = await locator(
        modelPath: '${root.path}/deleted.bin',
      ).resolve();

      // A stale setting must not strand a machine that has a usable model.
      expect(setup.modelPath, present.path);
      expect(setup.state, ContentGeneratorState.ready);
    },
  );

  test('a missing generator and a missing model are told apart', () async {
    touch('$modelDirectory/ggml-base.bin');
    final noGenerator = await locator().resolve();
    expect(noGenerator.state, ContentGeneratorState.generatorMissing);

    File('${root.path}/$modelDirectory/ggml-base.bin').deleteSync();
    touch('listen-gen/.venv/bin/listen-gen');
    final noModel = await locator().resolve();
    expect(noModel.state, ContentGeneratorState.modelMissing);
  });

  test(
    'an empty model directory is not mistaken for an installed model',
    () async {
      touch('listen-gen/.venv/bin/listen-gen');
      Directory('${root.path}/$modelDirectory').createSync(recursive: true);

      final setup = await locator().resolve();

      expect(setup.state, ContentGeneratorState.modelMissing);
      expect(setup.modelPath, isEmpty);
    },
  );

  test(
    'the provider argv names whisper-cpp and carries no app internals',
    () async {
      touch('listen-gen/.venv/bin/listen-gen');
      touch('$modelDirectory/ggml-base.bin');

      final arguments = contentGeneratorProviderArguments(
        await locator().resolve(),
      );

      expect(arguments.sublist(0, 2), ['--provider', 'whisper-cpp']);
      expect(arguments, contains('--model'));
      // The wrapper protocol this replaced is gone: no placeholder, no script,
      // no interpreter. If any reappears, it belongs in listen-gen instead.
      expect(arguments.any((item) => item.contains('{media}')), isFalse);
      expect(arguments.any((item) => item.endsWith('.py')), isFalse);
    },
  );
}
