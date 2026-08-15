import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/controllers/download_controller.dart';
import 'package:llplayer_next/controllers/learning_controller.dart';
import 'package:llplayer_next/controllers/media_import_flow_controller.dart';
import 'package:llplayer_next/controllers/media_session_coordinator.dart';
import 'package:llplayer_next/controllers/player_controller.dart';
import 'package:llplayer_next/controllers/resource_actions_coordinator.dart';
import 'package:llplayer_next/controllers/settings_controller.dart';
import 'package:llplayer_next/controllers/speech_enhancement_workflow_controller.dart';
import 'package:llplayer_next/controllers/subtitle_controller.dart';
import 'package:llplayer_next/data/repositories/learning_material_repository.dart';
import 'package:llplayer_next/data/repositories/media_import_repository.dart';
import 'package:llplayer_next/data/repositories/media_session_repository.dart';
import 'package:llplayer_next/data/repositories/resource_repository.dart';
import 'package:llplayer_next/data/repositories/subtitle_analysis_repository.dart';
import 'package:llplayer_next/localization.dart';
import 'package:llplayer_next/models/api_failure.dart';
import 'package:llplayer_next/models/embedded_subtitle.dart';
import 'package:llplayer_next/models/learning_material.dart';
import 'package:llplayer_next/models/media_download.dart';
import 'package:llplayer_next/models/media_resolution.dart';
import 'package:llplayer_next/models/timeline.dart';
import 'package:llplayer_next/models/types.dart';
import 'package:llplayer_next/player_adapter.dart';
import 'package:llplayer_next/services/managed_asset_store.dart';
import 'package:llplayer_next/services/media_import_file_service.dart';

import 'support/learning_material_fixtures.dart';

/// Retention end to end through the session coordinator: opening local media
/// is Temporary Material (retain false) and keeps playing when Core fails;
/// opening resolves the media's learning material and makes material retention
/// the session authority; Keep copies into the managed store and re-registers
/// the managed path with retain true while preserving the bound material
/// identity; a failed registration rolls back only a copy this operation
/// created (never a pre-existing deduplication target); once registration
/// succeeds the copy is membership and is never deleted by a later resolve or
/// state failure; a late Keep registration or a late material resolution from
/// an older open can never overwrite a newer session (session epoch);
/// reference-in-place retains the material without copying and never calls the
/// legacy media retain; unretain is material membership through the
/// learning-material boundary; material resolution failure never blocks
/// playback or leaks raw errors.
void main() {
  test(
    'opening local media registers Temporary Material (retain false)',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final harness = _harness(adapter: adapter, repository: repository);

      await harness.session.openMediaPath('/media/original.mp3');

      expect(repository.registered, hasLength(1));
      expect(repository.registered.single.path, '/media/original.mp3');
      expect(repository.registered.single.retain, isFalse);
      // Playback happened and the session is marked temporary.
      expect(adapter.opened, ['/media/original.mp3']);
      expect(harness.player.mediaRetained, isFalse);
      expect(
        harness.player.status,
        _en('statusPlayingFile').replaceAll('{name}', 'original.mp3'),
      );
    },
  );

  test('playback still works when Core registration fails on open', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository()..failRegistration = true;
    final harness = _harness(adapter: adapter, repository: repository);

    await harness.session.openMediaPath('/media/original.mp3');

    expect(adapter.opened, ['/media/original.mp3']);
    expect(adapter.played, isTrue);
    // The failure is named on the status line, never the exception text.
    expect(harness.player.status, _en('statusPlayingCoreUnavailable'));
    expect(harness.player.statusFailure, isNotNull);
    expect(harness.player.status, isNot(contains('core refused')));
  });

  test('progress restore seeks only after playback starts', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository()
      ..savedProgress = const Duration(seconds: 14);
    final harness = _harness(adapter: adapter, repository: repository);

    await harness.session.openMediaPath('/media/original.mp3');

    // Real incident: the restore seek ran while paused, then the subtitle
    // auto-select's disableNativeSubtitles() (setActiveTracks([])) reset the
    // paused seek to zero and playback restarted at 0:00. The coordinator
    // must therefore play first and seek second, and only report the saved
    // position after the seek.
    expect(adapter.calls, contains('play'));
    expect(adapter.calls, contains('seek'));
    expect(
      adapter.calls.indexOf('play'),
      lessThan(adapter.calls.indexOf('seek')),
    );
    expect(harness.player.position, const Duration(seconds: 14));
  });

  test('an already-retained media reopens without losing membership', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository()
      ..alreadyRetained.add('/media/kept.mp3');
    final harness = _harness(adapter: adapter, repository: repository);

    await harness.session.openMediaPath('/media/kept.mp3');

    // Core 3.1 fingerprint identity: re-registering a kept path keeps its
    // membership even though the open itself passes retain false.
    expect(repository.registered.single.retain, isFalse);
    expect(harness.player.mediaRetained, isTrue);
  });

  test(
    'opening resolves a temporary material and derives retained state from it',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final materials = _FakeMaterialRepository()
        ..resolved = _materialDetails(retained: false);
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        materials: materials,
      );

      await harness.session.openMediaPath('/media/original.mp3');

      // Registration created the deterministic material graph; the open
      // resolved it by media id and made it the session authority.
      expect(materials.resolvedMediaIds, ['media-1']);
      expect(harness.session.currentMaterial?.material.id, 'material-1');
      expect(harness.session.currentMaterial?.isRetained, isFalse);
      expect(harness.player.mediaRetained, isFalse);
      expect(
        harness.player.status,
        _en('statusPlayingFile').replaceAll('{name}', 'original.mp3'),
      );
    },
  );

  test('reopening an already retained media resolves retained material despite '
      'register retain false', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository()
      ..alreadyRetained.add('/media/kept.mp3');
    final materials = _FakeMaterialRepository()
      ..resolved = _materialDetails(retained: true);
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      materials: materials,
    );

    await harness.session.openMediaPath('/media/kept.mp3');

    expect(repository.registered.single.retain, isFalse);
    expect(materials.resolvedMediaIds, ['media-1']);
    expect(harness.session.currentMaterial?.material.id, 'material-1');
    expect(harness.session.currentMaterial?.isRetained, isTrue);
    expect(harness.player.mediaRetained, isTrue);
  });

  test(
    'material resolution failure never blocks playback or leaks raw errors',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final materials = _FakeMaterialRepository()..resolveFails = true;
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        materials: materials,
      );

      await harness.session.openMediaPath('/media/original.mp3');

      // The file plays; the media registered fine; the material read is
      // non-gating enrichment, so the open status stays healthy and the raw
      // resolution error never reaches the status line.
      expect(adapter.opened, ['/media/original.mp3']);
      expect(adapter.played, isTrue);
      expect(harness.session.currentMaterial, isNull);
      expect(harness.player.mediaRetained, isFalse);
      expect(
        harness.player.status,
        _en('statusPlayingFile').replaceAll('{name}', 'original.mp3'),
      );
      expect(harness.player.status, isNot(contains('boom')));
      expect(harness.player.statusFailure, isNull);
    },
  );

  test('current material clears on media switch', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final materials = _FakeMaterialRepository()
      ..resolved = _materialDetails(materialId: 'material-a');
    late MediaSessionCoordinator session;
    final atSwitch = <MaterialDetails?>[];
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      materials: materials,
      onMediaSwitched: () => atSwitch.add(session.currentMaterial),
    );
    session = harness.session;

    await harness.session.openMediaPath('/media/a.mp3');
    expect(harness.session.currentMaterial?.material.id, 'material-a');

    atSwitch.clear();
    materials.resolved = _materialDetails(materialId: 'material-b');
    await harness.session.openMediaPath('/media/b.mp3');

    // The previous material is gone synchronously at the switch and the new
    // media resolves its own material — never a stale material from media A.
    expect(atSwitch, isNotEmpty);
    expect(atSwitch.first, isNull);
    expect(harness.session.currentMaterial?.material.id, 'material-b');
    expect(harness.session.currentMaterial?.material.id, isNot('material-a'));
  });

  test('a late material resolution from an older open cannot overwrite the '
      'newer session', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final materials = _GatedMaterialRepository();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      materials: materials,
    );

    // Media A opens and suspends at its gated material resolve.
    final openingA = harness.session.openMediaPath('/media/a.mp3');
    await _settle();
    expect(materials.gates, hasLength(1));

    // Media B supersedes it and resolves its own material first.
    final openingB = harness.session.openMediaPath('/media/b.mp3');
    await _settle();
    expect(materials.gates, hasLength(2));
    materials.gates[1].complete(_materialDetails(materialId: 'material-b'));
    await openingB;
    expect(harness.session.currentMaterial?.material.id, 'material-b');
    expect(harness.player.mediaPath, '/media/b.mp3');

    // A's late resolution is discarded: B keeps its session and material.
    materials.gates[0].complete(_materialDetails(materialId: 'material-a'));
    await openingA;
    expect(harness.session.currentMaterial?.material.id, 'material-b');
    expect(harness.session.currentMaterial?.material.id, isNot('material-a'));
    expect(harness.player.mediaPath, '/media/b.mp3');
    expect(
      harness.player.status,
      _en('statusPlayingFile').replaceAll('{name}', 'b.mp3'),
    );
  });

  test(
    'an external media switch invalidates an in-flight material resolve',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final materials = _GatedMaterialRepository();
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        materials: materials,
      );

      // Media A opens and suspends at its gated material resolve.
      final opening = harness.session.openMediaPath('/media/a.mp3');
      await _settle();
      expect(materials.gates, hasLength(1));

      // The online clear (external switch) drops the material and invalidates
      // the in-flight resolve before it can repopulate the session.
      harness.session.beginExternalMediaSwitch();
      materials.gates.single.complete(
        _materialDetails(materialId: 'material-a'),
      );
      await opening;

      expect(harness.session.currentMaterial, isNull);
    },
  );

  test('a late Keep registration preserves the copy and membership but cannot '
      'overwrite a newer session', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final materials = _FakeMaterialRepository()
      ..resolved = _materialDetails(materialId: 'material-a', retained: false);
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
      materials: materials,
    );

    await harness.session.openMediaPath('/media/a.mp3');
    expect(harness.session.currentMaterial?.material.id, 'material-a');

    // Keep suspends at its registration round-trip.
    repository.keepRegisterGate = Completer<void>();
    final keeping = harness.session.keepCurrentMedia();
    await _settle();

    // A newer local open supersedes the in-flight Keep.
    materials.resolved = _materialDetails(
      materialId: 'material-b',
      retained: false,
    );
    await harness.session.openMediaPath('/media/b.mp3');
    expect(harness.session.currentMaterial?.material.id, 'material-b');

    // The late registration lands: the copy and its membership survive, but
    // the newer session's player and status are never overwritten.
    repository.keepRegisterGate!.complete();
    await keeping;

    expect(store.deleted, isEmpty);
    expect(repository.registered.last.retain, isTrue);
    expect(repository.registered.last.path, store.copyPath);
    expect(harness.player.mediaPath, '/media/b.mp3');
    expect(harness.player.mediaPath, isNot(store.copyPath));
    expect(harness.session.currentMaterial?.material.id, 'material-b');
    expect(
      harness.player.status,
      _en('statusPlayingFile').replaceAll('{name}', 'b.mp3'),
    );
    expect(harness.player.retentionInFlight, isFalse);
  });

  test(
    'a Keep that goes stale before registration deletes only its new copy and '
    'never registers or writes status into the newer session',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final store = _FakeManagedStore();
      final materials = _FakeMaterialRepository()
        ..resolved = _materialDetails(
          materialId: 'material-a',
          retained: false,
        );
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
        materials: materials,
      );

      await harness.session.openMediaPath('/media/a.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-a');

      // Keep suspends at the managed-store copy.
      store.copyGate = Completer<void>();
      final keeping = harness.session.keepCurrentMedia();
      await _settle();

      // A newer local open supersedes the in-flight Keep.
      materials.resolved = _materialDetails(
        materialId: 'material-b',
        retained: false,
      );
      await harness.session.openMediaPath('/media/b.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-b');

      // The copy lands late: the stale Keep removes only what it created and
      // never starts the registration, so the newer session's media and
      // status are untouched and legacy retain/unretain stay unused.
      store.copyGate!.complete();
      await keeping;

      expect(store.deleted, [store.copyPath]);
      expect(repository.registered, hasLength(2));
      expect(
        repository.registered.map((entry) => entry.retain),
        everyElement(isFalse),
      );
      expect(repository.retained, isEmpty);
      expect(repository.unretained, isEmpty);
      expect(materials.retained, isEmpty);
      expect(materials.unretained, isEmpty);
      expect(harness.player.mediaPath, '/media/b.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-b');
      expect(
        harness.player.status,
        _en('statusPlayingFile').replaceAll('{name}', 'b.mp3'),
      );
      expect(harness.player.status, isNot(_en('statusKeepFailed')));
      expect(harness.player.retentionInFlight, isFalse);
    },
  );

  test(
    'a late failed Keep registration rolls back its new copy without writing '
    'failure into the newer session',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final store = _FakeManagedStore();
      final materials = _FakeMaterialRepository()
        ..resolved = _materialDetails(
          materialId: 'material-a',
          retained: false,
        );
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
        materials: materials,
      );

      await harness.session.openMediaPath('/media/a.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-a');

      // Keep suspends at its registration round-trip.
      repository.keepRegisterGate = Completer<void>();
      final keeping = harness.session.keepCurrentMedia();
      await _settle();

      // A newer local open supersedes the in-flight Keep.
      materials.resolved = _materialDetails(
        materialId: 'material-b',
        retained: false,
      );
      await harness.session.openMediaPath('/media/b.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-b');

      // The late registration fails: the stale Keep rolls back only its new
      // copy and skips the status write entirely.
      repository.keepRegisterGate!.completeError(StateError('core refused'));
      await keeping;

      expect(store.deleted, [store.copyPath]);
      expect(repository.registered, hasLength(2));
      expect(
        repository.registered.map((entry) => entry.retain),
        everyElement(isFalse),
      );
      expect(repository.retained, isEmpty);
      expect(repository.unretained, isEmpty);
      expect(materials.retained, isEmpty);
      expect(materials.unretained, isEmpty);
      expect(harness.player.mediaPath, '/media/b.mp3');
      expect(harness.player.mediaPath, isNot(store.copyPath));
      expect(harness.session.currentMaterial?.material.id, 'material-b');
      expect(
        harness.player.status,
        _en('statusPlayingFile').replaceAll('{name}', 'b.mp3'),
      );
      expect(harness.player.status, isNot(_en('statusKeepFailed')));
      expect(harness.player.retentionInFlight, isFalse);
    },
  );

  test(
    'a stale managed-store failure never writes into the newer session',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final store = _FakeManagedStore();
      final materials = _FakeMaterialRepository()
        ..resolved = _materialDetails(
          materialId: 'material-a',
          retained: false,
        );
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
        materials: materials,
      );

      await harness.session.openMediaPath('/media/a.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-a');

      // Keep suspends at the managed-store copy, which fails late.
      store.copyGate = Completer<void>();
      store.unavailable = true;
      final keeping = harness.session.keepCurrentMedia();
      await _settle();

      // A newer local open supersedes the in-flight Keep.
      materials.resolved = _materialDetails(
        materialId: 'material-b',
        retained: false,
      );
      await harness.session.openMediaPath('/media/b.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-b');

      // The store failure lands late: the stale Keep skips the status write
      // and the newer session's status and state stay untouched.
      store.copyGate!.complete();
      await keeping;

      expect(store.copies, isEmpty);
      expect(repository.registered, hasLength(2));
      expect(
        repository.registered.map((entry) => entry.retain),
        everyElement(isFalse),
      );
      expect(repository.retained, isEmpty);
      expect(repository.unretained, isEmpty);
      expect(materials.retained, isEmpty);
      expect(materials.unretained, isEmpty);
      expect(harness.player.mediaPath, '/media/b.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-b');
      expect(
        harness.player.status,
        _en('statusPlayingFile').replaceAll('{name}', 'b.mp3'),
      );
      expect(
        harness.player.status,
        isNot(_en('statusManagedStoreUnavailable')),
      );
      expect(harness.player.retentionInFlight, isFalse);
    },
  );

  test(
    'online import clears the session material before rebinding the player',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final materials = _FakeMaterialRepository()
        ..resolved = _materialDetails(materialId: 'material-a');
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        materials: materials,
      );

      await harness.session.openMediaPath('/media/a.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-a');

      final flow = MediaImportFlowController(
        _FakeImportRepository(),
        adapter,
        harness.session,
        () => true,
        (_) => true,
        playerController: harness.player,
        subtitleController: harness.subtitle,
        downloadController: DownloadController(),
      );

      final outcome = await flow.playOnline('https://example.com/watch?v=1');

      expect(outcome, isA<MediaImportSucceeded>());
      // The online clear dropped the session material synchronously and the
      // player was cleared before the new online media path was bound.
      expect(harness.session.currentMaterial, isNull);
      expect(harness.player.mediaId, isNull);
      expect(harness.player.mediaPath, 'https://example.com/watch?v=1');
      expect(adapter.opened, contains('https://example.com/watch?v=1'));
    },
  );

  test('Keep copies into the managed store and rebinds the session', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    var libraryRefreshes = 0;
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
      onLibraryChanged: () async {
        libraryRefreshes += 1;
      },
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original Title',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);

    await harness.session.keepCurrentMedia();

    // Copied once, registered at the managed path with retain true and the
    // original title, and the session now points at the managed copy.
    expect(store.copies, ['/media/original.mp3']);
    expect(repository.registered, hasLength(1));
    expect(repository.registered.single.path, store.copyPath);
    expect(repository.registered.single.retain, isTrue);
    expect(repository.registered.single.title, 'Original Title');
    expect(repository.registered.single.kind, 'audio');
    expect(repository.retained, isEmpty);
    expect(harness.player.mediaPath, store.copyPath);
    expect(harness.player.mediaTitle, 'Original Title');
    expect(harness.player.mediaId, 'media-1');
    expect(harness.player.mediaRetained, isTrue);
    expect(harness.player.status, _en('statusMediaKept'));
    expect(harness.player.statusIsError, isFalse);
    // The library list refreshes after membership changes instead of staying
    // a stale snapshot.
    expect(libraryRefreshes, 1);
    // The recent-media path follows the session to the managed copy.
    expect(harness.settings.lastRecordedPath, store.copyPath);
    expect(harness.player.retentionInFlight, isFalse);
  });

  test('Keep preserves material identity across the managed rebind and updates '
      'retained evidence', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final materials = _FakeMaterialRepository()
      ..resolved = _materialDetails(retained: false);
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
      materials: materials,
    );

    // Opening the original media binds a temporary material.
    await harness.session.openMediaPath('/media/original.mp3');
    expect(harness.session.currentMaterial?.material.id, 'material-1');
    expect(harness.session.currentMaterial?.isRetained, isFalse);

    // The managed rebind re-resolves the same material id/revision and the
    // membership evidence moves to the material.
    materials.resolved = _materialDetails(retained: true);
    await harness.session.keepCurrentMedia();

    expect(harness.player.mediaId, 'media-1');
    expect(harness.player.mediaPath, store.copyPath);
    expect(harness.session.currentMaterial?.material.id, 'material-1');
    expect(harness.session.currentMaterial?.isRetained, isTrue);
    expect(harness.player.mediaRetained, isTrue);
    expect(harness.player.status, _en('statusMediaKept'));
  });

  test(
    'a material resolve failure after a successful Keep registration reports '
    'Keep success and deletes nothing',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final store = _FakeManagedStore();
      final materials = _FakeMaterialRepository()
        ..resolved = _materialDetails(retained: false);
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
        materials: materials,
      );

      await harness.session.openMediaPath('/media/original.mp3');
      expect(harness.session.currentMaterial?.material.id, 'material-1');

      // The registration round-trip succeeds; the follow-up material read
      // fails. Resolution is non-gating enrichment.
      materials.resolveFails = true;
      await harness.session.keepCurrentMedia();

      // Keep reports success: membership is the media-level evidence from the
      // registration, the copy survives, and nothing is deleted.
      expect(store.deleted, isEmpty);
      expect(repository.registered.last.retain, isTrue);
      expect(repository.registered.last.path, store.copyPath);
      expect(harness.player.mediaPath, store.copyPath);
      expect(harness.player.mediaRetained, isTrue);
      expect(harness.session.currentMaterial, isNull);
      expect(harness.player.status, _en('statusMediaKept'));
      expect(harness.player.statusIsError, isFalse);
      expect(harness.player.statusFailure, isNull);
      expect(harness.player.status, isNot(contains('boom')));
    },
  );

  test(
    'a failed Core registration rolls back only a newly created copy',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository()..failRegistration = true;
      final store = _FakeManagedStore()..createdNew = true;
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
      );
      harness.player.setMedia(
        id: 'media-1',
        path: '/media/original.mp3',
        title: 'Original',
        fingerprint: 'fp',
      );
      harness.player.setMediaRetained(false);

      await harness.session.keepCurrentMedia();

      // The copy this operation created is removed; the media stays temporary.
      expect(store.deleted, [store.copyPath]);
      expect(repository.retained, isEmpty);
      expect(harness.player.mediaRetained, isFalse);
      expect(harness.player.mediaPath, '/media/original.mp3');
      expect(harness.player.status, _en('statusKeepFailed'));
      expect(harness.player.statusIsError, isTrue);
      expect(harness.player.statusFailure, isNotNull);
      expect(harness.player.status, isNot(contains('core refused')));
    },
  );

  test(
    'a failed Core registration never removes a pre-existing dedupe target',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository()..failRegistration = true;
      final store = _FakeManagedStore()..createdNew = false;
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
      );
      harness.player.setMedia(
        id: 'media-1',
        path: '/media/original.mp3',
        title: 'Original',
        fingerprint: 'fp',
      );
      harness.player.setMediaRetained(false);

      await harness.session.keepCurrentMedia();

      // The deduplication target was already in the store; nothing is deleted.
      expect(store.deleted, isEmpty);
      expect(repository.retained, isEmpty);
      expect(harness.player.mediaRetained, isFalse);
      expect(harness.player.status, _en('statusKeepFailed'));
    },
  );

  test(
    'an unavailable managed store reports honestly and changes nothing',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final store = _FakeManagedStore()..unavailable = true;
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        store: store,
      );
      harness.player.setMedia(
        id: 'media-1',
        path: '/media/original.mp3',
        title: 'Original',
        fingerprint: 'fp',
      );
      harness.player.setMediaRetained(false);

      await harness.session.keepCurrentMedia();

      expect(store.copies, isEmpty);
      expect(repository.registered, isEmpty);
      expect(repository.retained, isEmpty);
      expect(harness.player.mediaRetained, isFalse);
      expect(harness.player.status, _en('statusManagedStoreUnavailable'));
      expect(harness.player.statusIsError, isTrue);
      expect(harness.player.status, isNot(contains('ManagedStoreUnavailable')));
    },
  );

  test('a local managed-copy failure never leaks filesystem details', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore()..copyFails = true;
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);

    await harness.session.keepCurrentMedia();

    expect(repository.retained, isEmpty);
    expect(harness.player.mediaRetained, isFalse);
    expect(harness.player.status, _en('statusKeepFailed'));
    expect(harness.player.status, isNot(contains('ManagedStoreCopyFailed')));
    expect(harness.player.statusFailure, isNull);
  });

  test('reference in place retains the material without copying', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final materials = _FakeMaterialRepository();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
      materials: materials,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);
    harness.session.currentMaterial = _materialDetails(retained: false);

    await harness.session.referenceCurrentMediaInPlace();

    // Membership is material membership: the material endpoint runs, the
    // legacy media-level retain is never called, and nothing is copied.
    expect(materials.retained, ['material-1']);
    expect(repository.retained, isEmpty);
    expect(store.copies, isEmpty);
    expect(harness.player.mediaPath, '/media/original.mp3');
    expect(harness.player.mediaRetained, isTrue);
    expect(harness.session.currentMaterial?.isRetained, isTrue);
    expect(harness.player.status, _en('statusMediaKeptInPlace'));
  });

  test('reference in place preserves material identity and updates retained '
      'evidence', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final materials = _FakeMaterialRepository()
      ..resolved = _materialDetails(retained: false);
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
      materials: materials,
    );

    await harness.session.openMediaPath('/media/original.mp3');
    expect(harness.session.currentMaterial?.material.id, 'material-1');

    materials.resolved = _materialDetails(retained: true);
    await harness.session.referenceCurrentMediaInPlace();

    // Membership synchronized through the material boundary; the session's
    // material carries the fresh evidence without changing its identity.
    expect(materials.retained, ['material-1']);
    expect(repository.retained, isEmpty);
    expect(harness.session.currentMaterial?.material.id, 'material-1');
    expect(harness.session.currentMaterial?.isRetained, isTrue);
    expect(harness.player.mediaRetained, isTrue);
    expect(harness.player.mediaPath, '/media/original.mp3');
    expect(harness.player.status, _en('statusMediaKeptInPlace'));
  });

  test('reference in place without a resolved material reports the stable keep '
      'failure', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final materials = _FakeMaterialRepository();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      materials: materials,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Kept',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);
    // No resolved material — the coordinator must not invent an identity.

    await harness.session.referenceCurrentMediaInPlace();

    expect(materials.retained, isEmpty);
    expect(repository.retained, isEmpty);
    expect(harness.player.mediaRetained, isFalse);
    expect(harness.player.mediaId, 'media-1');
    expect(harness.player.status, _en('statusKeepFailed'));
    expect(harness.player.statusIsError, isTrue);
    // Stable named state only: no raw exception text, no failure detail.
    expect(harness.player.status, isNot(contains('StateError')));
    expect(harness.player.statusFailure, isNull);
  });

  test('reference in place with an unavailable material boundary reports the '
      'stable keep failure', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final materials = _FakeMaterialRepository()..unavailable = true;
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      materials: materials,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Kept',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);
    harness.session.currentMaterial = _materialDetails(retained: false);

    await harness.session.referenceCurrentMediaInPlace();

    expect(materials.retained, isEmpty);
    expect(repository.retained, isEmpty);
    expect(harness.player.mediaRetained, isFalse);
    expect(harness.player.status, _en('statusKeepFailed'));
    expect(harness.player.statusIsError, isTrue);
    expect(harness.player.statusFailure, isNull);
  });

  test('unretain changes membership only — material endpoint, media record, '
      'files, graph and learning state all untouched', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final materials = _FakeMaterialRepository();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
      materials: materials,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: store.copyPath,
      title: 'Kept',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(true);
    harness.session.currentMaterial = _materialDetails(retained: true);

    await harness.session.unretainCurrentMedia();

    // Unretain is material membership through the learning-material
    // boundary; the legacy media projection is not called.
    expect(materials.unretained, ['material-1']);
    expect(repository.unretained, isEmpty);
    // The media record and the material revision stay intact.
    expect(harness.player.mediaId, 'media-1');
    expect(harness.player.mediaPath, store.copyPath);
    expect(harness.session.currentMaterial?.material.id, 'material-1');
    expect(harness.session.currentMaterial?.material.retainedAtMs, isNull);
    expect(harness.session.currentMaterial?.currentRevision.id, 'revision-1');
    expect(harness.player.mediaRetained, isFalse);
    expect(store.deleted, isEmpty);
    expect(harness.player.status, _en('statusMediaUnkept'));
  });

  test(
    'unretain without a resolved material reports the stable failure state',
    () async {
      final adapter = _FakeAdapter();
      final repository = _FakeSessionRepository();
      final materials = _FakeMaterialRepository();
      final harness = _harness(
        adapter: adapter,
        repository: repository,
        materials: materials,
      );
      harness.player.setMedia(
        id: 'media-1',
        path: '/media/original.mp3',
        title: 'Kept',
        fingerprint: 'fp',
      );
      harness.player.setMediaRetained(true);
      // No resolved material identity — the coordinator must not invent one.

      await harness.session.unretainCurrentMedia();

      expect(materials.unretained, isEmpty);
      expect(repository.unretained, isEmpty);
      expect(harness.player.mediaRetained, isTrue);
      expect(harness.player.mediaId, 'media-1');
      expect(harness.player.status, _en('statusUnkeepFailed'));
      expect(harness.player.statusIsError, isTrue);
      // Stable named state only: no raw exception text, no failure detail.
      expect(harness.player.status, isNot(contains('StateError')));
      expect(harness.player.statusFailure, isNull);
    },
  );

  test('an unretain failure is named and keeps membership', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final materials = _FakeMaterialRepository()..unretainFails = true;
    final store = _FakeManagedStore();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
      materials: materials,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/store/copy.mp3',
      title: 'Kept',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(true);
    harness.session.currentMaterial = _materialDetails(retained: true);

    await harness.session.unretainCurrentMedia();

    expect(harness.player.mediaRetained, isTrue);
    expect(harness.player.status, _en('statusUnkeepFailed'));
    expect(harness.player.statusIsError, isTrue);
    expect(harness.player.status, isNot(contains('refused')));
  });

  test('retention operations refuse re-entry while in flight', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final store = _FakeManagedStore();
    final harness = _harness(
      adapter: adapter,
      repository: repository,
      store: store,
    );
    harness.player.setMedia(
      id: 'media-1',
      path: '/media/original.mp3',
      title: 'Original',
      fingerprint: 'fp',
    );
    harness.player.setMediaRetained(false);
    harness.player.setRetentionInFlight(true);

    await harness.session.keepCurrentMedia();

    expect(store.copies, isEmpty);
    expect(repository.registered, isEmpty);
    expect(harness.player.mediaRetained, isFalse);
  });

  test('retention needs an open media', () async {
    final adapter = _FakeAdapter();
    final repository = _FakeSessionRepository();
    final harness = _harness(adapter: adapter, repository: repository);

    await harness.session.keepCurrentMedia();
    expect(harness.player.status, _en('statusOpenMediaFirst'));

    await harness.session.referenceCurrentMediaInPlace();
    expect(harness.player.status, _en('statusOpenMediaFirst'));
  });
}

String _en(String key) => const AppLocalizations(Locale('en')).text(key);

MaterialDetails _materialDetails({
  String materialId = 'material-1',
  bool retained = true,
}) => materialDetails(
  materialId: materialId,
  retainedAtMs: retained ? 42 : null,
  documentRenditions: [documentRenditionForText('Hello', )],
  shape: MaterialShape.audio,
);

({
  _FakeAdapter adapter,
  PlayerController player,
  SubtitleController subtitle,
  _RecordingSettings settings,
  MediaSessionCoordinator session,
  LearningMaterialRepository materials,
})
_harness({
  required _FakeAdapter adapter,
  required _FakeSessionRepository repository,
  _FakeManagedStore? store,
  LearningMaterialRepository? materials,
  void Function()? onMediaSwitched,
  Future<void> Function()? onLibraryChanged,
}) {
  final player = PlayerController();
  final subtitle = SubtitleController();
  final settings = _RecordingSettings();
  final speech = SpeechEnhancementWorkflowController();
  final materialRepository = materials ?? _FakeMaterialRepository();
  final resourceActions =
      ResourceActionsCoordinator(
        player: player,
        subtitle: subtitle,
        speechEnhancement: speech,
        repository: _FakeResourceRepository(),
      )..bind(
        isMounted: () => true,
        text: (key) => _en(key),
        reloadSpeechEnhancements: (_) async {},
        activatePrimaryTrack: (_, {required nextStatus}) async {},
        reloadLearningEntries: () async {},
      );
  final session =
      MediaSessionCoordinator(
        adapter: adapter,
        player: player,
        subtitle: subtitle,
        learning: LearningController(),
        settings: settings,
        speechEnhancement: speech,
        resourceActions: resourceActions,
        repository: repository,
        subtitleAnalysis: _FakeSubtitleAnalysisRepository(),
        managedStore: store ?? _FakeManagedStore(),
        materialRepository: materialRepository,
        onLibraryChanged: onLibraryChanged,
        importFiles: _FixedImportFiles(),
      )..bind(
        isMounted: () => true,
        text: (key) => _en(key),
        confirmLLTimelineMismatch:
            ({
              required String resourceFingerprint,
              required String currentFingerprint,
            }) async => true,
        onMediaSwitched: onMediaSwitched ?? () {},
        reloadLearningEntries: () async {},
        loadPhraseCandidates: (_) async {},
      );
  return (
    adapter: adapter,
    player: player,
    subtitle: subtitle,
    settings: settings,
    session: session,
    materials: materialRepository,
  );
}

/// An adapter that plays nothing, so the coordinator's open path runs in a
/// plain Dart test. [DesktopPlayerAdapter] is a plain class, so a subclass
/// with real `open`/`play`/`seek` overrides is the seam.
class _FakeAdapter extends DesktopPlayerAdapter {
  final opened = <String>[];
  bool played = false;

  /// Playback call order, for restore-ordering assertions.
  final calls = <String>[];

  @override
  Future<void> open(String path, {bool play = true}) async {
    opened.add(path);
  }

  @override
  Future<void> play() async {
    played = true;
    calls.add('play');
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek');
  }
}

class _FakeSessionRepository implements MediaSessionRepository {
  bool failRegistration = false;
  bool failUnretain = false;

  /// When set, [registerMedia] calls with `retain: true` await this before
  /// recording or returning — the seam for a Keep that lands after the
  /// session moved on.
  Completer<void>? keepRegisterGate;
  final alreadyRetained = <String>{};
  final registered =
      <({String path, bool retain, String? title, String? kind})>[];
  final retained = <String>[];
  final unretained = <String>[];

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'refused by fake core');

  @override
  Future<MediaItem> registerMedia(
    String path, {
    required bool retain,
    String? title,
    String? kind,
  }) async {
    if (retain) {
      final gate = keepRegisterGate;
      if (gate != null) await gate.future;
    }
    registered.add((path: path, retain: retain, title: title, kind: kind));
    if (failRegistration) throw StateError('core refused');
    return MediaItem(
      id: 'media-1',
      path: path,
      fingerprint: 'fp',
      title: title ?? 'T',
      kind: kind ?? 'audio',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 1,
      // Core 3.1 fingerprint identity keeps existing membership on a
      // re-registration, even one that passes retain false.
      retainedAtMs: retain || alreadyRetained.contains(path) ? 1 : null,
    );
  }

  @override
  Future<MediaItem> retainMedia(String mediaId) async {
    retained.add(mediaId);
    return MediaItem(
      id: mediaId,
      path: '/media/original.mp3',
      fingerprint: 'fp',
      title: 'T',
      kind: 'audio',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 2,
      retainedAtMs: 2,
    );
  }

  @override
  Future<MediaItem> unretainMedia(String mediaId) async {
    if (failUnretain) throw StateError('refused');
    unretained.add(mediaId);
    return MediaItem(
      id: mediaId,
      path: '/media/original.mp3',
      fingerprint: 'fp',
      title: 'T',
      kind: 'audio',
      durationMs: 1000,
      availability: 'available',
      createdAtMs: 1,
      updatedAtMs: 2,
    );
  }

  @override
  Future<void> saveProgress(String mediaId, Duration position) async {}

  /// When set, [readProgress] returns it — the seam for restore-ordering
  /// tests.
  Duration? savedProgress;

  @override
  Future<Duration?> readProgress(String mediaId) async => savedProgress;

  @override
  Future<SubtitleTrack> importSubtitle(String mediaId, String path) async =>
      throw UnimplementedError();

  @override
  Future<SubtitleTrack> importTimeline({
    required String mediaId,
    required Map<String, dynamic> document,
    required bool allowMismatch,
  }) async => throw UnimplementedError();
}

class _FakeMaterialRepository implements LearningMaterialRepository {
  bool resolveFails = false;
  bool unretainFails = false;

  /// When true, [isAvailable] is false — modeling an unreachable
  /// learning-material boundary.
  bool unavailable = false;
  final resolvedMediaIds = <String>[];
  final retained = <String>[];
  final unretained = <String>[];

  /// What [resolveMaterialForMedia] returns. Null models a media with no
  /// bound material (a typed not-found on the wire).
  MaterialDetails? resolved;

  @override
  bool get isAvailable => !unavailable;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'refused by fake materials');

  @override
  Future<List<MaterialDetails>> listLearningMaterials() async => [];

  @override
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  }) async => throw UnimplementedError();

  @override
  Future<MaterialDetails> readLearningMaterial(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  ) async => throw UnimplementedError();

  @override
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) async => throw UnimplementedError();

  @override
  Future<MaterialDetails> retainLearningMaterial(String materialId) async {
    retained.add(materialId);
    return _materialDetails(materialId: materialId, retained: true);
  }

  @override
  Future<MaterialDetails> unretainLearningMaterial(String materialId) async {
    if (unretainFails) throw StateError('refused by fake materials');
    unretained.add(materialId);
    return _materialDetails(materialId: materialId, retained: false);
  }

  @override
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) async {
    if (resolveFails) throw StateError('material graph boom');
    resolvedMediaIds.add(mediaId);
    final value = resolved;
    if (value == null) {
      throw StateError('no learning material bound to $mediaId');
    }
    return value;
  }

  @override
  Future<MaterialRevision> updateSourceAssetAvailability(
    String materialId,
    String sourceAssetId,
    SourceAssetAvailability availability,
  ) async => throw UnimplementedError();

  @override
  Future<List<MaterialCapabilityProjection>> listMaterialCapabilities(
    String materialId,
  ) async => throw UnimplementedError();
}

/// Resolve is gated by a Completer so a test can complete an in-flight
/// material resolution out of order, proving that a stale session discards a
/// late result.
class _GatedMaterialRepository implements LearningMaterialRepository {
  final gates = <Completer<MaterialDetails>>[];

  @override
  bool get isAvailable => true;

  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'refused by fake materials');

  @override
  Future<List<MaterialDetails>> listLearningMaterials() async => [];

  @override
  Future<MaterialDetails> createLearningMaterial(
    CreateLearningMaterialInput input, {
    MaterialRetainDirective retain = const MaterialRetainOmitted(),
  }) async => throw UnimplementedError();

  @override
  Future<MaterialDetails> readLearningMaterial(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> appendMaterialRevision(
    String materialId,
    AppendMaterialRevisionInput input,
  ) async => throw UnimplementedError();

  @override
  Future<MaterialRevision> readMaterialRevision(
    String materialId,
    String revisionId,
  ) async => throw UnimplementedError();

  @override
  Future<MaterialDetails> retainLearningMaterial(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> unretainLearningMaterial(String materialId) async =>
      throw UnimplementedError();

  @override
  Future<MaterialDetails> resolveMaterialForMedia(String mediaId) {
    final gate = Completer<MaterialDetails>();
    gates.add(gate);
    return gate.future;
  }

  @override
  Future<MaterialRevision> updateSourceAssetAvailability(
    String materialId,
    String sourceAssetId,
    SourceAssetAvailability availability,
  ) async => throw UnimplementedError();

  @override
  Future<List<MaterialCapabilityProjection>> listMaterialCapabilities(
    String materialId,
  ) async => throw UnimplementedError();
}

/// Resolves any page URL to itself so the online-import flow can be driven
/// end to end without a real sidecar or external tool.
class _FakeImportRepository implements MediaImportRepository {
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'refused by fake import');

  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async => null;

  @override
  Future<String> resolveOnlineMedia(String pageUrl) async => pageUrl;

  @override
  Future<MediaDownloadHandle> downloadOnlineMedia(
    String pageUrl,
    String directory,
  ) => throw UnimplementedError();

  @override
  Future<MediaDownloadHandle> downloadEnclosure(
    String mediaUrl,
    String directory, {
    int? expectedBytes,
  }) => throw UnimplementedError();

  @override
  Future<String?> downloadArticle(String articleUrl, String directory) =>
      throw UnimplementedError();

  @override
  Future<ResolvedVideoDetails> resolveVideoDetails(String pageUrl) =>
      throw UnimplementedError();

  @override
  Future<ResolvedChannelDetails> resolveChannelDetails(String channelUrl) =>
      throw UnimplementedError();

  @override
  Future<List<EmbeddedSubtitle>> probeSubtitles(String mediaPath) async =>
      const [];

  @override
  Future<int?> probeMediaDurationMs(String mediaPath) async => null;

  @override
  Future<String> extractTextSubtitle(
    String mediaPath,
    EmbeddedSubtitle subtitle,
  ) => throw UnimplementedError();
}

/// Lets an open/Keep suspend at a Completer the test completes later.
Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeManagedStore implements ManagedAssetStoreService {
  String copyPath = '/store/copy-0.mp3';
  bool createdNew = true;
  bool unavailable = false;
  bool copyFails = false;

  /// When set, [copyIntoStore] awaits this before proceeding — the seam for
  /// a copy that lands after the session moved on.
  Completer<void>? copyGate;
  final copies = <String>[];
  final deleted = <String>[];

  @override
  Future<ManagedAssetCopy> copyIntoStore({
    required String sourcePath,
    String? mediaKind,
  }) async {
    final gate = copyGate;
    if (gate != null) await gate.future;
    if (unavailable) throw const ManagedStoreUnavailable();
    if (copyFails) throw const ManagedStoreCopyFailed();
    copies.add(sourcePath);
    return ManagedAssetCopy(
      path: copyPath,
      createdNew: createdNew,
      mediaKind: mediaKind ?? 'audio',
    );
  }

  @override
  Future<ManagedAssetCopy> copyBytesIntoStore({
    required List<int> bytes,
    required String mediaKind,
  }) async => throw UnimplementedError();

  @override
  Future<List<int>?> readBytes(String path) async => null;

  @override
  Future<void> deleteStoreCopy(String path) async {
    deleted.add(path);
  }
}

class _RecordingSettings extends SettingsController {
  String? lastRecordedPath;

  @override
  void recordRecentMedia({
    required String path,
    required String title,
    required int positionMs,
    required int durationMs,
    required int subtitleCount,
  }) {
    lastRecordedPath = path;
  }
}

class _FakeResourceRepository implements ResourceRepository {
  @override
  bool get isAvailable => false;
  @override
  ApiFailure failureDetail(Object error) =>
      ApiFailure(raw: '$error', message: 'unavailable');
  @override
  Future<ContentDifficultyProfile> contentFit(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<List<SubtitleTrack>> mediaSubtitles(String mediaId) async => [];
  @override
  Future<List<WordTiming>> wordTimings(String trackId) async => [];
  @override
  Future<List<PhoneTimelineSummary>> phoneTimelineSummaries(
    String trackId,
  ) async => [];
  @override
  Future<void> archiveSubtitle(String trackId) async {}
  @override
  Future<void> restoreSubtitle(String trackId) async {}
  @override
  Future<void> deleteSubtitle(String trackId) async {}
  @override
  Future<String> exportSubtitleSrt(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<LLTimelineDocument> exportTimeline(String trackId) async =>
      throw UnimplementedError();
  @override
  Future<void> updateTrackLanguage(String trackId, String language) async {}
  @override
  Future<void> activateWordTimeline(String timelineId) async {}
  @override
  Future<void> activatePhoneTimeline(String timelineId) async {}
  @override
  Future<void> archivePhoneTimeline(String timelineId) async {}
  @override
  Future<void> deletePhoneTimeline(String timelineId) async {}
}

class _FakeSubtitleAnalysisRepository implements SubtitleAnalysisRepository {
  @override
  bool get isAvailable => false;
  @override
  Future<bool> syntaxReady() async => false;
  @override
  Future<void> analyzeTrackSyntax(String trackId) async {}
  @override
  Future<PronunciationAnalysis> analyzePronunciation(String sentenceId) async =>
      throw UnimplementedError();
  @override
  Future<String> startPhoneticAnalysis({
    required String trackId,
    required String? sentenceId,
    required String preferredModelId,
  }) async => throw UnimplementedError();
}

/// Lets openMediaPath find a concrete media path without a picker.
class _FixedImportFiles implements MediaImportFileService {
  @override
  Future<String?> pickMedia() async => null;
  @override
  Future<String?> pickSubtitle() async => null;
  @override
  Future<TimelineFileDocument?> pickTimeline() async => null;
  @override
  String basename(String path) => path.split(Platform.pathSeparator).last;
  @override
  Future<String?> pickDownloadDirectory({
    required String confirmButtonText,
  }) async => null;
}
