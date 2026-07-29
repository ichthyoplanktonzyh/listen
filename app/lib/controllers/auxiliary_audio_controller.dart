import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/speech_synthesis.dart';
import '../services/api_service.dart';

abstract interface class AuxiliaryAudioPlayer {
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

typedef AuxiliaryAudioPlayerFactory =
    AuxiliaryAudioPlayer Function(Uri source, bool local);

class _VideoAuxiliaryAudioPlayer implements AuxiliaryAudioPlayer {
  _VideoAuxiliaryAudioPlayer(Uri source, bool local)
    : _controller = local
          ? VideoPlayerController.file(File.fromUri(source))
          : VideoPlayerController.networkUrl(source);

  final VideoPlayerController _controller;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> dispose() => _controller.dispose();
}

/// Owns short auxiliary audio from dictionary providers and speech synthesis.
/// It is intentionally independent of any one surface; callers supply the
/// surrounding audio-focus action immediately before playback starts.
class AuxiliaryAudioController extends ChangeNotifier {
  AuxiliaryAudioController({AuxiliaryAudioPlayerFactory? playerFactory})
    : _playerFactory = playerFactory ?? _VideoAuxiliaryAudioPlayer.new;

  final AuxiliaryAudioPlayerFactory _playerFactory;
  AuxiliaryAudioPlayer? _player;
  int _generation = 0;
  bool _busy = false;
  String? _error;
  SpeechSynthesisAssetView? _asset;

  bool get busy => _busy;
  String? get error => _error;
  SpeechSynthesisAssetView? get asset => _asset;

  Future<bool> playRemote(
    String url, {
    required Future<void> Function() acquireAudioFocus,
  }) => _play(
    Uri.parse(url),
    local: false,
    acquireAudioFocus: acquireAudioFocus,
    syntheticAsset: null,
  );

  Future<SpeechSynthesisAssetView?> speak(
    LocalApi api, {
    required String text,
    required String language,
    required String purpose,
    required Future<void> Function() acquireAudioFocus,
  }) async {
    final generation = ++_generation;
    _setBusy(true);
    _error = null;
    try {
      final asset = await api.synthesizeSpeech(
        text: text,
        language: language,
        purpose: purpose,
      );
      if (generation != _generation) return null;
      final played = await _play(
        File(asset.audioPath).uri,
        local: true,
        acquireAudioFocus: acquireAudioFocus,
        syntheticAsset: asset,
        generation: generation,
      );
      return played && generation == _generation ? asset : null;
    } catch (error) {
      if (generation == _generation) {
        _error = 'This audio could not be loaded';
        notifyListeners();
      }
      return null;
    } finally {
      if (generation == _generation) _setBusy(false);
    }
  }

  Future<bool> _play(
    Uri source, {
    required bool local,
    required Future<void> Function() acquireAudioFocus,
    required SpeechSynthesisAssetView? syntheticAsset,
    int? generation,
  }) async {
    final currentGeneration = generation ?? ++_generation;
    if (generation == null) _setBusy(true);
    _error = null;
    try {
      await acquireAudioFocus();
      if (currentGeneration != _generation) return false;
      final previous = _player;
      _player = null;
      await previous?.pause();
      await previous?.dispose();
      if (currentGeneration != _generation) return false;
      final next = _playerFactory(source, local);
      _player = next;
      await next.initialize();
      if (currentGeneration != _generation) {
        await next.dispose();
        return false;
      }
      _asset = syntheticAsset;
      await next.play();
      notifyListeners();
      return true;
    } catch (error) {
      if (currentGeneration == _generation) {
        _error = 'This audio could not be loaded';
        notifyListeners();
      }
      return false;
    } finally {
      if (generation == null && currentGeneration == _generation) {
        _setBusy(false);
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    final player = _player;
    _player = null;
    _busy = false;
    await player?.pause();
    await player?.dispose();
    notifyListeners();
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_player?.dispose());
    _player = null;
    super.dispose();
  }
}
