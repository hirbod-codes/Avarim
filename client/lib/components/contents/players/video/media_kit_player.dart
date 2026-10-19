import 'dart:async';
import 'package:avarim/components/contents/players/video/player_interface.dart';
import 'package:avarim/lib/talker.dart';
import 'package:media_kit/media_kit.dart' hide PlayerState;

class MediaKitVideoPlayer implements AppVideoPlayer {
  MediaKitVideoPlayer() {
    _player = Player();
    _bindStreams();
  }

  late final Player _player;

  // Expose the raw media_kit Player so VideoController can attach to it.
  Player get nativePlayer => _player;

  final _stateController = StreamController<PlayerState>.broadcast();
  PlayerState _state = const PlayerState();

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  PlayerState get state => _state;

  void _emit(PlayerState next) {
    _state = next;
    _stateController.add(next);
  }

  void _bindStreams() {
    // Playing / paused
    _player.stream.playing.listen((playing) {
      talker.info('_player.stream.playing.listen');
      talker.info(playing);
      _emit(_state.copyWith(status: playing ? PlayerStatus.playing : PlayerStatus.paused));
    });

    // Buffering
    _player.stream.buffering.listen((buffering) {
      talker.info('_player.stream.buffering.listen');
      talker.info(buffering);
      if (buffering) _emit(_state.copyWith(status: PlayerStatus.buffering));
    });

    // Position
    _player.stream.position.listen((pos) {
      _emit(_state.copyWith(position: pos));
    });

    // Duration
    _player.stream.duration.listen((dur) {
      _emit(_state.copyWith(duration: dur));
    });

    // Buffer
    _player.stream.buffer.listen((buf) {
      _emit(_state.copyWith(buffered: buf));
    });

    // Volume — media_kit uses 0-100, we normalise to 0.0-1.0
    _player.stream.volume.listen((vol) {
      _emit(_state.copyWith(volume: vol / 100.0));
    });

    // End of media
    _player.stream.completed.listen((completed) {
      talker.info('_player.stream.completed.listen');
      talker.info(completed);
      if (completed) _emit(_state.copyWith(status: PlayerStatus.ended));
    });

    // Errors
    _player.stream.error.listen((err) {
      talker.info('[MediaKitVideoPlayer] error: $err');
      _emit(_state.copyWith(status: PlayerStatus.error, error: err));
    });
  }

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    talker.info('_player.open');
    final s = _state.copyWith(status: PlayerStatus.loading, position: Duration.zero, duration: Duration.zero, error: null);
    _emit(s);

    final media = Media(url, httpHeaders: headers);
    await _player.open(media, play: false);
    _emit(_state.copyWith(status: PlayerStatus.paused));

    talker.info('_player.open done');
    talker.info(s.toJson());
    talker.info(_state.toJson());
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume((volume * 100).clamp(0, 100));

  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _stateController.close();
  }

  @override
  Future<void> togglePlayPause() => _player.playOrPause();
}
