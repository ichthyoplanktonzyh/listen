import 'dart:io';

/// Why generation is or is not possible on this machine.
///
/// Every value is something a person can act on. `ready` is the only one that
/// permits a generation attempt, and the others each name the single missing
/// piece rather than collapsing into "not configured".
enum ContentGeneratorState {
  ready,

  /// The separately verified `listen-gen` release bundle is unavailable.
  /// This state is reported by the Gen process service, not the tool locator.
  generatorMissing,

  /// The pinned Gen zipapp is installed, but this machine has no compatible
  /// Python runtime. Gen 0.5.0 requires Python 3.11 or newer.
  pythonMissing,

  /// The generator is present but no whisper model is installed, so it has
  /// nothing to transcribe with.
  modelMissing,

  /// `whisper-cli` was not found; the model cannot be run.
  whisperMissing,

  /// `ffprobe` was not found; Gen cannot inspect the source media.
  ffprobeMissing,

  /// `ffmpeg` was not found; Gen cannot prepare source audio.
  ffmpegMissing,
}

/// Everything needed to launch a generation, resolved together.
///
/// The paths and the verdict travel as one value so no surface can pair a
/// fresh verdict with a stale path — the same reason
/// [ManagedStoreLocation] is shaped this way in `settings.dart`.
///
/// The aligner and phoneme paths are enhancements, not gates: an empty value
/// simply drops the corresponding argv from the provider arguments, and the
/// generator honestly degrades (whisper word timings, no phone timeline)
/// rather than refusing to run.
typedef ContentGeneratorSetup = ({
  String pythonPath,
  String modelPath,
  String whisperPath,
  String ffprobePath,
  String ffmpegPath,
  String alignerPython,
  String alignerScript,
  String phoneSidecar,
  String phoneModelDir,
  ContentGeneratorState state,
});

const ContentGeneratorSetup unresolvedContentGeneratorSetup = (
  pythonPath: '',
  modelPath: '',
  whisperPath: '',
  ffprobePath: '',
  ffmpegPath: '',
  alignerPython: '',
  alignerScript: '',
  phoneSidecar: '',
  phoneModelDir: '',
  state: ContentGeneratorState.generatorMissing,
);

/// Finds the generation toolchain without asking the user to describe it.
///
/// This used to be two environment variables, one of which was a hand-written
/// nested-escaped JSON array carrying a python interpreter, a wrapper script
/// path, a `{media}` placeholder and a provider protocol — all of them
/// `listen-gen` internals that a person had no business knowing. The app now
/// looks in the places these tools actually live, and Settings overrides a
/// lookup rather than replacing it.
class ContentGeneratorLocator {
  const ContentGeneratorLocator({
    this.pythonPath = '',
    this.modelPath = '',
    this.whisperPath = '',
    this.ffprobePath = '',
    this.ffmpegPath = '',
    this.alignerPython = '',
    this.alignerScript = '',
    this.phoneSidecar = '',
    this.phoneModelDir = '',
    this.environment = const {},
    this.pythonCompatibilityProbe,
  });

  /// Configured overrides; empty means "look for it".
  final String pythonPath;
  final String modelPath;
  final String whisperPath;
  final String ffprobePath;
  final String ffmpegPath;
  final String alignerPython;
  final String alignerScript;
  final String phoneSidecar;
  final String phoneModelDir;

  /// Injected so tests never read the developer's own environment.
  final Map<String, String> environment;

  /// Test seam for the Python >=3.11 probe. Production executes the candidate
  /// with a version-only command; it never imports Gen or starts a run here.
  final Future<bool> Function(String path)? pythonCompatibilityProbe;

  String get _home => environment['HOME'] ?? Platform.environment['HOME'] ?? '';

  /// Alongside the app bundle, for a future release that ships the toolchain.
  String get _bundledRuntime =>
      '${File(Platform.resolvedExecutable).parent.parent.path}/Resources/runtime';

  /// `flutter run` executes from the repository root, where the same pinned
  /// Core artifact used by release packaging already owns the shared media
  /// tools. Finder/release launches use [_bundledRuntime] instead.
  String get _developmentRuntime =>
      '${Directory.current.absolute.path}/.backend/runtime/runtime';

  Future<ContentGeneratorSetup> resolve() async {
    final whisper = await _resolveExecutable(
      whisperPath,
      'whisper-cli',
      const [],
    );
    final ffprobe = await _resolveExecutable(ffprobePath, 'ffprobe', const []);
    final ffmpeg = await _resolveExecutable(ffmpegPath, 'ffmpeg', const []);
    final model = await _resolveModel();

    // The acoustic aligner and phoneme sidecars are a research toolchain
    // living in the listen-core working copy, driven by the same virtualenv.
    // Each side is only complete when every piece it needs is present.
    final alignerPython = await _resolveExecutable(this.alignerPython, '', [
      '$_home/LLPlayerNext/.venv/bin/python',
      '$_home/listen-gen/.venv/bin/python',
      '$_home/listen-core/.venv/bin/python',
      '$_home/.venv/bin/python',
    ], wantDirectory: false);
    final alignerScript = await _resolveExecutable(this.alignerScript, '', [
      '$_home/listen-core/scripts/forced-align/align-cli.py',
    ], wantDirectory: false);
    final phoneSidecar = await _resolveExecutable(this.phoneSidecar, '', [
      '$_home/listen-core/scripts/wav2vec2-phoneme-cli.py',
    ], wantDirectory: false);
    final phoneModelDir = await _resolveModelDirectory();
    final python = await _resolvePython(alignerPython);

    // The pinned Gen bundle is resolved and verified separately by
    // LocalListenGenReleaseService. This locator owns only the external media
    // toolchain required by that release.
    final state = switch (null) {
      _ when python == null => ContentGeneratorState.pythonMissing,
      _ when whisper == null => ContentGeneratorState.whisperMissing,
      _ when model == null => ContentGeneratorState.modelMissing,
      _ when ffprobe == null => ContentGeneratorState.ffprobeMissing,
      _ when ffmpeg == null => ContentGeneratorState.ffmpegMissing,
      _ => ContentGeneratorState.ready,
    };
    return (
      pythonPath: python ?? '',
      modelPath: model ?? '',
      whisperPath: whisper ?? '',
      ffprobePath: ffprobe ?? '',
      ffmpegPath: ffmpeg ?? '',
      alignerPython: alignerPython ?? '',
      alignerScript: alignerScript ?? '',
      phoneSidecar: phoneSidecar ?? '',
      phoneModelDir: phoneModelDir ?? '',
      state: state,
    );
  }

  /// Resolves the interpreter as an absolute path and verifies the release's
  /// declared Python floor. Finder's PATH commonly resolves `python3` to the
  /// macOS 3.9 runtime, so the launched process must never repeat that lookup.
  Future<String?> _resolvePython(String? resolvedAlignerPython) async {
    final candidates = <String>[
      if (pythonPath.isNotEmpty) pythonPath,
      '$_bundledRuntime/python3',
      '$_developmentRuntime/python3',
      ?resolvedAlignerPython,
      '/opt/homebrew/bin/python3',
      '/usr/local/bin/python3',
      ..._pathCandidates('python3'),
    ];
    final visited = <String>{};
    for (final candidate in candidates) {
      if (candidate.isEmpty || !visited.add(candidate)) continue;
      if (!await File(candidate).exists()) continue;
      if (await _isCompatiblePython(candidate)) return candidate;
    }
    return null;
  }

  Iterable<String> _pathCandidates(String name) sync* {
    final path = environment['PATH'] ?? Platform.environment['PATH'] ?? '';
    for (final directory in path.split(':')) {
      if (directory.isNotEmpty) yield '$directory/$name';
    }
  }

  Future<bool> _isCompatiblePython(String path) async {
    final probe = pythonCompatibilityProbe;
    if (probe != null) return probe(path);
    try {
      final result = await Process.run(path, const [
        '-c',
        'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)',
      ]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<String?> _resolveExecutable(
    String configured,
    String name,
    List<String> extraCandidates, {
    bool wantDirectory = false,
  }) async {
    if (configured.isNotEmpty) {
      final exists = wantDirectory
          ? await Directory(configured).exists()
          : await File(configured).exists();
      if (exists) return configured;
    }
    for (final candidate in [
      // An empty [name] means "this tool has no standard filename, only the
      // explicit candidates below". Interpolating it anyway yields the bare
      // runtime directory, which `wantDirectory: true` then happily accepts —
      // that is how the phoneme model directory resolved to the folder
      // holding ffmpeg, so every run shipped a `--phones-wav2vec2-model-dir`
      // that could not load and Gen answered `phone_failed` every time.
      if (name.isNotEmpty) '$_bundledRuntime/$name',
      if (name.isNotEmpty) '$_developmentRuntime/$name',
      ...extraCandidates,
      if (name.isNotEmpty) '/opt/homebrew/bin/$name',
      if (name.isNotEmpty) '/usr/local/bin/$name',
      if (name.isNotEmpty) '/usr/bin/$name',
    ]) {
      if (candidate.isEmpty) continue;
      if (wantDirectory) {
        if (await Directory(candidate).exists()) return candidate;
      } else if (await File(candidate).exists()) {
        return candidate;
      }
    }
    if (name.isEmpty) return null;
    // A GUI launch inherits a minimal PATH, so `which` is the last resort
    // rather than the first: the fixed locations above are what actually
    // answer when the app is opened from Finder.
    try {
      final result = await Process.run('/usr/bin/which', [name]);
      final path = (result.stdout as String).trim();
      if (result.exitCode == 0 && path.isNotEmpty) return path;
    } on ProcessException {
      return null;
    }
    return null;
  }

  /// The phoneme model, at the location the research toolchain installs it
  /// (see listen-core's setup-phoneme-model.sh). The environment override is
  /// the one the toolchain itself honors.
  Future<String?> _resolveModelDirectory() async {
    final configured = phoneModelDir.isNotEmpty
        ? phoneModelDir
        : environment['LISTEN_PHONEME_MODEL_DIR'] ??
            Platform.environment['LISTEN_PHONEME_MODEL_DIR'] ??
            environment['LLPLAYERNEXT_PHONEME_MODEL_DIR'] ??
            Platform.environment['LLPLAYERNEXT_PHONEME_MODEL_DIR'] ??
            '';
    return _resolveExecutable(configured, '', [
      '$_home/Library/Application Support/listen/models/wav2vec2-phoneme',
      '$_home/Library/Application Support/listen/models/phoneme',
      '$_home/Library/Application Support/LLPlayerNext/models/'
          'wav2vec2-phoneme',
      '$_home/listen-core/models/wav2vec2-phoneme',
    ], wantDirectory: true);
  }

  /// The whisper model, from the shared location the project already uses.
  ///
  /// When several are installed the largest wins: model files grow with
  /// capability, and a person who downloaded a bigger one meant to use it.
  Future<String?> _resolveModel() async {
    if (modelPath.isNotEmpty && await File(modelPath).exists()) {
      return modelPath;
    }
    for (final directory in [
      Directory('$_home/Library/Application Support/listen/models/whisper'),
      Directory('$_bundledRuntime/models/whisper'),
    ]) {
      if (!await directory.exists()) continue;
      final models = <File>[];
      await for (final entry in directory.list()) {
        if (entry is File && entry.path.endsWith('.bin')) models.add(entry);
      }
      if (models.isEmpty) continue;
      final sizes = <String, int>{};
      for (final model in models) {
        sizes[model.path] = await model.length();
      }
      models.sort((a, b) {
        final bySize = sizes[b.path]!.compareTo(sizes[a.path]!);
        // Ties broken by path so the choice never depends on directory order.
        return bySize != 0 ? bySize : a.path.compareTo(b.path);
      });
      return models.first.path;
    }
    return null;
  }
}

/// The `listen-gen` argv for a resolved toolchain.
///
/// Lives here rather than in configuration because every item is an internal
/// contract between this app and that CLI. A person configures *where* the
/// tools are; how to talk to them is the app's job.
///
/// The aligner and phoneme pieces are only added when the whole side is
/// present: a partial toolchain must not produce a half-configured argv that
/// fails the run, it must drop the side and let the generator degrade
/// honestly. The sense-group/acoustics/prosody baselines are deterministic
/// in-generator stages with no external toolchain, so they are always on.
List<String> contentGeneratorProviderArguments(ContentGeneratorSetup setup) => [
  '--provider',
  'whisper-cpp',
  '--whisper-model',
  setup.modelPath,
  '--whisper-model-id',
  setup.modelPath.split('/').last,
  '--whisper-cli',
  setup.whisperPath,
  if (setup.ffprobePath.isNotEmpty) ...['--ffprobe-command', setup.ffprobePath],
  if (setup.ffmpegPath.isNotEmpty) ...['--ffmpeg-command', setup.ffmpegPath],
  '--sense-groups',
  'baseline',
  '--acoustics',
  'baseline',
  '--prosody',
  'baseline',
  if (setup.alignerPython.isNotEmpty && setup.alignerScript.isNotEmpty) ...[
    '--aligner',
    'torchaudio',
    '--aligner-python',
    setup.alignerPython,
    '--aligner-script',
    setup.alignerScript,
    '--aligner-timeout-seconds',
    '3600',
  ],
  if (setup.alignerPython.isNotEmpty &&
      setup.phoneSidecar.isNotEmpty &&
      setup.phoneModelDir.isNotEmpty) ...[
    '--phones',
    'wav2vec2',
    '--phones-wav2vec2-python',
    setup.alignerPython,
    '--phones-wav2vec2-sidecar',
    setup.phoneSidecar,
    '--phones-wav2vec2-model-dir',
    setup.phoneModelDir,
    '--phones-wav2vec2-model-id',
    'facebook/wav2vec2-lv-60-espeak-cv-ft',
    '--phones-wav2vec2-model-revision',
    'ae45363bf3413b374fecd9dc8bc1df0e24c3b7f4',
  ],
];
