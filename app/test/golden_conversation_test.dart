import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:llplayer_next/controllers/realtime_conversation_controller.dart';
import 'package:llplayer_next/data/repositories/realtime_conversation_repository.dart';
import 'package:llplayer_next/services/api_service.dart';
import 'package:llplayer_next/services/realtime_audio_bridge.dart';
import 'package:llplayer_next/services/shadowing_recorder.dart';
import 'package:llplayer_next/theme/icon_size.dart';
import 'package:llplayer_next/theme/spacing.dart';
import 'package:llplayer_next/widgets/common/capability_viz.dart';
import 'package:llplayer_next/widgets/panels/conversation_stage_shell.dart';
import 'package:llplayer_next/widgets/panels/realtime_conversation_panel.dart';

import 'support/golden.dart';

/// Baselines for the conversation surfaces rebuilt in S4 (#83 · #84).
///
/// The lobby is the screen the design spec calls the worst in the app and the
/// stage the best, so both are worth freezing the moment they are agreed. The
/// lobby especially: what makes the rebuilt version right is a *composition*
/// claim — one heading, one 56pt action, everything else folded under it — and
/// the widget tests can only check that each piece is present. A later slice
/// that adds "just one more" control to the lobby passes every one of those
/// tests and fails this image.
///
/// Stage scenes render at a single brightness on purpose:
/// [ConversationStageShell] imposes `ListenTheme.dark()` on its subtree under
/// both themes — the room is dark because the lights are off, not because the
/// app is in dark mode — so a light baseline would be a byte-identical second
/// copy, and a duplicate file reads as coverage it is not.
///
/// **Deliberately not covered: the lobby's history rows.** Their labels are
/// built from `DateTime.fromMillisecondsSinceEpoch`, which formats in the
/// machine's local zone, so one fixture renders `14:43` in UTC and `22:43` in
/// UTC+8 — a baseline that would fail on a reviewer's laptop for a reason with
/// nothing to do with design. The row's wording is already pinned directly,
/// against a fixed `AppLocalizations`, in
/// `realtime_conversation_panel_test.dart`. Putting the rows on the net needs
/// an injectable clock/zone on the panel, which is a `lib/` change this slice
/// is not allowed to make.
void main() {
  // The four rooms of the 回声水面, plus its resting state. The design's claim
  // is that they are told apart without reading a label, which is exactly the
  // kind of claim only a picture can hold.
  for (final activity in RealtimeConversationActivity.values) {
    goldenScene(
      'conversation_echo_${activity.name}',
      size: GoldenSurface.strip,
      brightnesses: const [Brightness.dark],
      builder: (context) => ConversationStageShell(
        segment: ConversationStageSegment.stage,
        builder: (context) => Center(
          child: ConversationEchoSurface(
            levels: conversationEchoLevelsOf(activity),
          ),
        ),
      ),
    );
  }

  // The whole room: 「唯一光源」 means the water glows and the controls do not,
  // which is a relationship between two things in one frame.
  goldenScene(
    'conversation_stage',
    size: GoldenSurface.window,
    brightnesses: const [Brightness.dark],
    builder: (context) => _stage(),
  );

  // The same room at the narrowest window the macOS shell allows: the
  // composition has to stay centred instead of crushing the controls into the
  // water.
  goldenScene(
    'conversation_stage_min_window',
    size: GoldenSurface.minWindow,
    brightnesses: const [Brightness.dark],
    builder: (context) => _stage(),
  );

  // Both brightnesses, even though the room is dark in both: the light
  // baseline is what caught the lobby resolving its ink against the *app*
  // theme instead of the shell's, and it is the file that would go red if the
  // shell ever went back to taking a pre-built `child`.
  goldenScene(
    'conversation_lobby',
    size: GoldenSurface.window,
    builder: (context) => const _Lobby(),
  );

  // Nothing configured yet: the dead end has to stay a dead end with a door,
  // not an empty form.
  goldenScene(
    'conversation_lobby_first_run',
    size: GoldenSurface.window,
    builder: (context) => const _Lobby(profiles: []),
  );
}

Widget _stage() => ConversationStageShell(
  segment: ConversationStageSegment.stage,
  builder: (context) => ConversationStageLayout(
    exitAffordance: IconButton(
      onPressed: () {},
      iconSize: ListenIconSize.chrome,
      icon: const Icon(Icons.arrow_back),
    ),
    visualization: ConversationEchoSurface(
      levels: conversationEchoLevelsOf(
        RealtimeConversationActivity.assistantSpeaking,
      ),
    ),
    controls: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: ListenSpacing.gap16,
      children: [
        OutlinedButton(
          onPressed: () {},
          child: const Text('Finish and transcribe locally'),
        ),
        TextButton(onPressed: () {}, child: const Text('Cancel and discard')),
      ],
    ),
  ),
);

/// The lobby, driven through the real panel rather than a stand-in.
///
/// The panel loads its voices from the API on mount, so the scene answers that
/// request from a canned transport instead of poking the controller — the
/// frame captured is then the one a learner actually gets. The session list
/// answers empty; see the library doc for why the history rows stay off the
/// net.
class _Lobby extends StatefulWidget {
  const _Lobby({this.profiles = _profileFixture});

  final List<Map<String, Object?>> profiles;

  @override
  State<_Lobby> createState() => _LobbyState();
}

class _LobbyState extends State<_Lobby> {
  late final LocalApi _api = LocalApi.withTransport(
    baseUrl: 'http://golden',
    token: 'token',
    transport: (method, path, body) async {
      if (method == 'GET' && path == '/v1/realtime/providers') {
        return (statusCode: 200, body: jsonEncode(widget.profiles));
      }
      if (method == 'GET' && path == '/v1/realtime/sessions') {
        return (statusCode: 200, body: '[]');
      }
      throw StateError('Unexpected request: $method $path ${body ?? ''}');
    },
  );
  late final RealtimeConversationController _controller =
      RealtimeConversationController(
        repository: LocalRealtimeConversationRepository(() => _api),
        audio: _SilentAudio(),
      );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RealtimeConversationPanel(
    controller: _controller,
    launch: RealtimeConversationLaunch.free(
      language: 'en',
      modelId: 'asr-model',
    ),
    acquireAudioFocus: () async {},
    onClose: () {},
    onManageVoices: () async {},
  );
}

const _profileFixture = [
  {
    'id': 'profile-1',
    'display_name': 'Studio voice',
    'adapter_kind': 'qwen_omni_realtime',
    'base_url': 'wss://example.com/api-ws/v1/realtime',
    'model_id': 'qwen3.5-omni-plus-realtime',
    'voice': 'marin',
    'has_credential': true,
    'timeout_ms': 30000,
  },
];

/// The audio device the golden never opens.
class _SilentAudio implements RealtimeAudioSession {
  @override
  Stream<Uint8List> get pcmInput => const Stream.empty();

  @override
  Future<void> start({required int inputSampleRateHz}) async {}

  @override
  Future<void> beginTurn(String turnId, {int? audioStartMs}) async {}

  @override
  Future<CapturedRecording> endTurn() => throw UnimplementedError();

  @override
  Future<void> discardTurn() async {}

  @override
  Future<void> play(Uint8List pcm) async {}

  @override
  Future<void> stopPlayback() async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<CapturedRecording> stop() => throw UnimplementedError();

  @override
  Future<void> cancel() async {}
}
