// coverage:ignore-file
//
// `JustAudioPlaybackController` is a thin pass-through wrapper around
// `package:just_audio`'s `AudioPlayer`. The controller's behavior is
// exercised throughout the test suite via the `PlaybackController`
// abstraction with a fake; the production wrapper itself only runs in
// smoke tests against the real audio backend, where construction and
// stream subscription are platform-mediated and not meaningfully
// testable in `flutter test`. The provider closure that returns it has
// the same constraint.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

abstract class PlaybackController {
  Future<void> setSource(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Duration get position;
  bool get playing;
  Stream<Duration> get positionStream;
  Stream<bool> get playingStream;
  Future<void> dispose();
}

class JustAudioPlaybackController implements PlaybackController {
  JustAudioPlaybackController() : _player = AudioPlayer();
  final AudioPlayer _player;
  String? _currentSource;

  @override
  Future<void> setSource(String path) async {
    if (_currentSource == path) return;
    _currentSource = path;
    await _player.setFilePath(path);
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Duration get position => _player.position;
  @override
  bool get playing => _player.playing;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<bool> get playingStream => _player.playingStream;
  @override
  Future<void> dispose() => _player.dispose();
}

/// Provided at app startup with `playbackControllerProvider.overrideWithValue(...)`.
/// Tests override with a fake.
final playbackControllerProvider = Provider<PlaybackController>((ref) {
  final controller = JustAudioPlaybackController();
  ref.onDispose(controller.dispose);
  return controller;
});
