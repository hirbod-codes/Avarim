import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:avarim/components/contents/players/audio/audio_player_factory.dart';
import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/equalizer_settings.dart';

part 'audio_player_provider.g.dart';

@riverpod
class AudioPlayerCommands extends _$AudioPlayerCommands {
  late final AppAudioPlayer _player;

  @override
  void build() {
    _player = createAudioPlayer();
    ref.onDispose(_player.dispose);
  }

  // Expose state stream for widgets to watch
  Stream<AudioPlayerState> get stateStream => _player.stateStream;
  AudioPlayerState get currentState => _player.state;

  /// null when this platform has no equalizer.
  AppEqualizer? get equalizer => _player.equalizer;

  Future<void> open(String url, {Map<String, String>? headers, String? title, String? artist, String? albumArtUrl}) async {
    await _player.open(url, headers: headers, title: title, artist: artist, albumArtUrl: albumArtUrl);
    // The user's equalizer settings follow them from track to track. Not awaited: on Android the equalizer
    // only answers once the audio has loaded, and opening must not wait for that.
    unawaited(EqualizerStore.applyTo(_player.equalizer));
  }

  Future<void> play() async => _player.play();
  Future<void> pause() async => _player.pause();

  Future<void> togglePlayPause() => _player.togglePlayPause();

  Future<void> seek(Duration position) async => _player.seek(position);
  Future<void> setVolume(double volume) async => _player.setVolume(volume);
  Future<void> setSpeed(double speed) async => _player.setSpeed(speed);
  Future<void> skipForward() async => _player.skipForward();
  Future<void> skipBackward() async => _player.skipBackward();
}
