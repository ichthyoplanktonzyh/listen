import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/speech_synthesis_repository.dart';
import '../models/speech_synthesis.dart';
import '../services/auxiliary_audio_player.dart';

/// Owns short auxiliary audio from dictionary providers and speech synthesis.
/// It is intentionally independent of any one surface; callers supply the
/// surrounding audio-focus action immediately before playback starts.
class AuxiliaryAudioController extends ChangeNotifier {
  AuxiliaryAudioController({
    this.speechRepository = const UnavailableSpeechSynthesisRepository(),
    this.playbackService = const VideoAuxiliaryAudioPlaybackService(),
  });

  final SpeechSynthesisRepository speechRepository;
  final AuxiliaryAudioPlaybackService playbackService;
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
    remoteSource: Uri.parse(url),
    acquireAudioFocus: acquireAudioFocus,
    syntheticAsset: null,
  );

  Future<SpeechSynthesisAssetView?> speak(
    String text, {
    required String language,
    required String purpose,
    required Future<void> Function() acquireAudioFocus,
  }) async {
    final generation = ++_generation;
    _setBusy(true);
    _error = null;
    try {
      final asset = await speechRepository.synthesize(
        text: text,
        language: language,
        purpose: purpose,
      );
      if (generation != _generation) return null;
      final played = await _play(
        localPath: asset.audioPath,
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

  Future<bool> _play({
    Uri? remoteSource,
    String? localPath,
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
      final next = localPath == null
          ? playbackService.createRemote(remoteSource!)
          : playbackService.createLocalFile(localPath);
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
