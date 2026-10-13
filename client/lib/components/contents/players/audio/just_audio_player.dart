import 'dart:async';
import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:just_audio/just_audio.dart';

class JustAudioPlayer implements AppAudioPlayer {
  JustAudioPlayer() {
    _player = AudioPlayer();
    _bindStreams();
  }

  late final AudioPlayer _player;

  final _stateController = StreamController<AudioPlayerState>.broadcast();
  AudioPlayerState _state = const AudioPlayerState();

  @override
  Stream<AudioPlayerState> get stateStream => _stateController.stream;

  @override
  AudioPlayerState get state => _state;

  void _emit(AudioPlayerState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _bindStreams() {
    // Playing state
    _player.playerStateStream.listen((ps) {
      AudioPlayerStatus status;
      switch (ps.processingState) {
        case ProcessingState.idle:
          status = AudioPlayerStatus.idle;
        case ProcessingState.loading:
        case ProcessingState.buffering:
          status = ps.playing ? AudioPlayerStatus.buffering : AudioPlayerStatus.loading;
        case ProcessingState.ready:
          status = ps.playing ? AudioPlayerStatus.playing : AudioPlayerStatus.paused;
        case ProcessingState.completed:
          status = AudioPlayerStatus.ended;
      }
      _emit(_state.copyWith(status: status));
    });

    // Position
    _player.positionStream.listen((pos) {
      _emit(_state.copyWith(position: pos));
    });

    // Duration
    _player.durationStream.listen((dur) {
      if (dur != null) _emit(_state.copyWith(duration: dur));
    });

    // Buffered position
    _player.bufferedPositionStream.listen((buf) {
      _emit(_state.copyWith(buffered: buf));
    });

    // Volume
    _player.volumeStream.listen((vol) {
      _emit(_state.copyWith(volume: vol));
    });

    // Speed
    _player.speedStream.listen((speed) {
      _emit(_state.copyWith(speed: speed));
    });
  }

  @override
  Future<void> open(String url, {Map<String, String>? headers, String? title, String? artist, String? albumArtUrl}) async {
    _emit(
      _state.copyWith(
        status: AudioPlayerStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        error: null,
        title: title,
        artist: artist,
        albumArtUrl: albumArtUrl,
      ),
    );

    try {
      final source = AudioSource.uri(
        Uri.parse(url),
        headers: headers, // just_audio forwards these as HTTP headers,
        // which triggers Content-Range on the server
      );
      await _player.setAudioSource(source);
      // await _player.play();
    } catch (e) {
      _emit(_state.copyWith(status: AudioPlayerStatus.error, error: e.toString()));
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> togglePlayPause() => _player.playing ? pause() : play();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume.clamp(0.0, 1.0));

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed.clamp(0.25, 4.0));

  @override
  Future<void> skipForward([Duration amount = const Duration(seconds: 10)]) {
    final target = _state.position + amount;
    final clamped = target > _state.duration ? _state.duration : target;
    return _player.seek(clamped);
  }

  @override
  Future<void> skipBackward([Duration amount = const Duration(seconds: 10)]) {
    final target = _state.position - amount;
    final clamped = target < Duration.zero ? Duration.zero : target;
    return _player.seek(clamped);
  }

  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _stateController.close();
  }
}
