// media_kit_audio_player.dart
//
// The audio engine of every platform except web: libmpv through media_kit (Android, iOS, macOS, Windows,
// Linux). One engine everywhere means the same behaviour and the same equalizer (see mpv_equalizer.dart).
//
// The OS audio session (audio focus on Android, AVAudioSession on iOS) belongs to audio_session, which also
// serves the lock screen / notification controls (see system_media_session.dart), so media_kit is told not to
// manage the iOS session itself.

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/mpv_equalizer.dart';
import 'package:avarim/lib/talker.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

class MediaKitAudioPlayer implements AppAudioPlayer {
  MediaKitAudioPlayer() {
    // _player = Player(configuration: const PlayerConfiguration(title: 'Avarim', iosManageAudioSession: false));
    _player = Player(configuration: const PlayerConfiguration(title: 'Avarim'));
    _equalizer = MpvEqualizer(_player);
    _bindStreams();
  }

  late final Player _player;
  late final MpvEqualizer _equalizer;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final _stateController = StreamController<AudioPlayerState>.broadcast();
  AudioPlayerState _state = const AudioPlayerState();

  // What the status is made of (see _status).
  bool _opened = false;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  String? _error;

  @override
  AppEqualizer? get equalizer => _equalizer;

  @override
  Stream<AudioPlayerState> get stateStream => _stateController.stream;

  @override
  AudioPlayerState get state => _state;

  void _emit(AudioPlayerState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  AudioPlayerStatus get _status {
    if (_error != null) return AudioPlayerStatus.error;
    if (!_opened) return AudioPlayerStatus.idle;
    if (_completed) return AudioPlayerStatus.ended;
    if (_state.duration == Duration.zero) return AudioPlayerStatus.loading; // not ready yet
    if (_buffering) return _playing ? AudioPlayerStatus.buffering : AudioPlayerStatus.loading;
    return _playing ? AudioPlayerStatus.playing : AudioPlayerStatus.paused;
  }

  void _emitStatus() => _emit(_state.copyWith(status: _status, error: _error));

  void _bindStreams() {
    final s = _player.stream;
    _subscriptions.addAll([
      s.playing.listen((v) {
        _playing = v;
        _emitStatus();
      }),
      s.completed.listen((v) {
        _completed = v;
        _emitStatus();
      }),
      s.buffering.listen((v) {
        _buffering = v;
        _emitStatus();
      }),
      s.position.listen((v) => _emit(_state.copyWith(position: v))),
      s.duration.listen((v) {
        _state = _state.copyWith(duration: v); // before the status: it depends on the duration
        _emitStatus();
      }),
      s.buffer.listen((v) => _emit(_state.copyWith(buffered: v))),
      s.volume.listen((v) => _emit(_state.copyWith(volume: (v / 100).clamp(0.0, 1.0).toDouble()))), // mpv: 0..100
      s.rate.listen((v) => _emit(_state.copyWith(speed: v))),
      s.error.listen((e) {
        talker.error('media_kit player error: $e');
        _error = e;
        _emitStatus();
      }),
    ]);
  }

  @override
  Future<void> open(String url, {Map<String, String>? headers, String? title, String? artist, String? albumArtUrl}) async {
    _opened = true;
    _playing = false;
    _buffering = false;
    _completed = false;
    _error = null;

    _emit(
      _state.copyWith(
        status: AudioPlayerStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        buffered: Duration.zero,
        error: null,
        title: title,
        artist: artist,
        albumArtUrl: albumArtUrl,
      ),
    );

    try {
      // `headers` (Authorization) go to libmpv's HTTP layer, which is what makes the server answer with ranges.
      await _player.open(Media(url, httpHeaders: headers), play: false);
    } catch (e, st) {
      talker.error('could not open $url', e, st);
      _error = e.toString();
      _emitStatus();
    }
  }

  /// Android / iOS: the app has to hold the audio session (and audio focus) while it plays. Other platforms
  /// have no audio_session implementation, so nothing is asked there.
  Future<bool> _activateAudioSession() async {
    if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && defaultTargetPlatform != TargetPlatform.iOS)) return true;
    try {
      return await (await AudioSession.instance).setActive(true);
    } catch (e, st) {
      talker.error('could not activate the audio session', e, st);
      return true; // better to play than to stay silent
    }
  }

  @override
  Future<void> play() async {
    if (!await _activateAudioSession()) return; // audio focus was refused
    await _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> togglePlayPause() => _playing ? pause() : play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// [volume] is 0..1 (mpv works with 0..100).
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0) * 100);

  @override
  Future<void> setSpeed(double speed) => _player.setRate(speed.clamp(0.25, 4.0));

  @override
  Future<void> skipForward([Duration amount = const Duration(seconds: 10)]) {
    final target = _state.position + amount;
    return _player.seek(target > _state.duration ? _state.duration : target);
  }

  @override
  Future<void> skipBackward([Duration amount = const Duration(seconds: 10)]) {
    final target = _state.position - amount;
    return _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _equalizer.dispose();
    await _player.dispose();
    await _stateController.close();
  }
}
