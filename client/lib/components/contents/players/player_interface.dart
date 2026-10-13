import 'package:equatable/equatable.dart';

enum PlayerStatus { idle, loading, playing, paused, buffering, ended, error }

class PlayerState extends Equatable {
  const PlayerState({this.status = PlayerStatus.idle, this.position = Duration.zero, this.duration = Duration.zero, this.buffered = Duration.zero, this.volume = 1.0, this.error});

  final PlayerStatus status;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double volume; // 0.0 - 1.0
  final String? error;

  double get progress => duration.inMilliseconds > 0 ? position.inMilliseconds / duration.inMilliseconds : 0.0;

  PlayerState copyWith({PlayerStatus? status, Duration? position, Duration? duration, Duration? buffered, double? volume, String? error}) {
    return PlayerState(status: status ?? this.status, position: position ?? this.position, duration: duration ?? this.duration, buffered: buffered ?? this.buffered, volume: volume ?? this.volume, error: error ?? this.error);
  }

  String stringifyStatus(PlayerStatus s) {
    switch (s) {
      case PlayerStatus.buffering:
        return 'buffering';
      case PlayerStatus.ended:
        return 'ended';
      case PlayerStatus.error:
        return 'error';
      case PlayerStatus.idle:
        return 'idle';
      case PlayerStatus.loading:
        return 'loading';
      case PlayerStatus.paused:
        return 'paused';
      case PlayerStatus.playing:
        return 'playing';
    }
  }

  Map<String, dynamic> toJson() => {'status': stringifyStatus(status), 'position': position, 'duration': duration, 'buffered': buffered, 'volume': volume, 'error': error};

  @override
  List<Object?> get props => [status, position, duration, buffered, volume, error];
}

// ---------------------------------------------------------------------------
// Abstract interface — all backends implement this
// ---------------------------------------------------------------------------

abstract class AppVideoPlayer {
  /// The current player state as a stream.
  Stream<PlayerState> get stateStream;

  /// Current state snapshot.
  PlayerState get state;

  /// Open a URL and start loading. Supply [headers] for auth tokens, etc.
  Future<void> open(String url, {Map<String, String>? headers});

  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume); // 0.0 - 1.0

  /// Release all platform resources.
  Future<void> dispose();
}
