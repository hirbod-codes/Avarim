import 'package:equatable/equatable.dart';

// ---------------------------------------------------------------------------
// Value objects
// ---------------------------------------------------------------------------

enum AudioPlayerStatus { idle, loading, playing, paused, buffering, ended, error }

class AudioPlayerState extends Equatable {
  const AudioPlayerState({this.status = AudioPlayerStatus.idle, this.position = Duration.zero, this.duration = Duration.zero, this.buffered = Duration.zero, this.volume = 1.0, this.speed = 1.0, this.error, this.title, this.artist, this.albumArtUrl});

  final AudioPlayerStatus status;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double volume;
  final double speed;
  final String? error;

  // Metadata
  final String? title;
  final String? artist;
  final String? albumArtUrl;

  bool get isPlaying => status == AudioPlayerStatus.playing;
  bool get isBuffering => status == AudioPlayerStatus.buffering;
  bool get isLoading => status == AudioPlayerStatus.loading;
  bool get hasError => status == AudioPlayerStatus.error;

  double get progress => duration.inMilliseconds > 0 ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;

  double get bufferedProgress => duration.inMilliseconds > 0 ? (buffered.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;

  AudioPlayerState copyWith({AudioPlayerStatus? status, Duration? position, Duration? duration, Duration? buffered, double? volume, double? speed, String? error, String? title, String? artist, String? albumArtUrl}) {
    return AudioPlayerState(status: status ?? this.status, position: position ?? this.position, duration: duration ?? this.duration, buffered: buffered ?? this.buffered, volume: volume ?? this.volume, speed: speed ?? this.speed, error: error ?? this.error, title: title ?? this.title, artist: artist ?? this.artist, albumArtUrl: albumArtUrl ?? this.albumArtUrl);
  }

  @override
  List<Object?> get props => [status, position, duration, buffered, volume, speed, error, title, artist, albumArtUrl];
}

// ---------------------------------------------------------------------------
// Abstract interface
// ---------------------------------------------------------------------------

abstract class AppAudioPlayer {
  Stream<AudioPlayerState> get stateStream;
  AudioPlayerState get state;

  /// Open a URL with optional headers (e.g. Authorization for Content-Range).
  Future<void> open(String url, {Map<String, String>? headers, String? title, String? artist, String? albumArtUrl});

  Future<void> play();
  Future<void> pause();
  Future<void> togglePlayPause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> setSpeed(double speed);
  Future<void> skipForward([Duration amount = const Duration(seconds: 15)]);
  Future<void> skipBackward([Duration amount = const Duration(seconds: 15)]);

  Future<void> dispose();
}
