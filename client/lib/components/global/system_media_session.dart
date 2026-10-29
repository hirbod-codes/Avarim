// system_media_session.dart
//
// The OS media controls: the notification and lock screen (Android, iOS), Control Center (macOS), the media
// keys and the system overlay (Windows, SMTC) and MPRIS (Linux). All of them go through audio_service, which has
// a platform implementation for each (audio_service_win, audio_service_mpris; the rest is built in).
//
// The player lives inside the dock (one per track, see AudioPlayerService), so this is a thin bridge:
//   - AudioPlayerScreen attaches the current track and its controls, and detaches when it goes away;
//   - the session mirrors the player's state to the OS and hands the OS buttons to those controls.
// On web (and when the platform can't start the service) every call does nothing.

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/lib/talker.dart';
import 'package:flutter/foundation.dart';

/// What the OS buttons do. A null [next] / [previous] means there is no such track: the button isn't shown.
class SessionControls {
  const SessionControls({required this.play, required this.pause, required this.seek, this.next, this.previous});

  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function(Duration position) seek;
  final VoidCallback? next;
  final VoidCallback? previous;
}

/// What the OS shows about the track. [artHeaders] are sent when [artUrl] is fetched.
class SessionTrack {
  const SessionTrack({required this.id, this.title, this.artist, this.artUrl, this.artHeaders});

  final String id;
  final String? title;
  final String? artist;
  final String? artUrl;
  final Map<String, String>? artHeaders;
}

class _AvarimAudioHandler extends BaseAudioHandler with SeekHandler {
  @override
  Future<void> play() async => SystemMediaSession._controls?.play();

  @override
  Future<void> pause() async => SystemMediaSession._controls?.pause();

  @override
  Future<void> seek(Duration position) async => SystemMediaSession._controls?.seek(position);

  @override
  Future<void> skipToNext() async => SystemMediaSession._controls?.next?.call();

  @override
  Future<void> skipToPrevious() async => SystemMediaSession._controls?.previous?.call();

  /// The notification was dismissed: pause, the queue stays.
  @override
  Future<void> stop() async {
    await SystemMediaSession._controls?.pause();
    await super.stop();
  }
}

class SystemMediaSession {
  SystemMediaSession._();

  static _AvarimAudioHandler? _handler;
  static Object? _token; // identifies the attached player
  static SessionControls? _controls;
  static SessionTrack? _track;
  static StreamSubscription<AudioPlayerState>? _subscription;
  static AudioPlayerState? _last;
  static bool _pausedByInterruption = false;

  /// Starts the service. Call once at startup (not on web). A platform that can't run it just has no OS controls.
  static Future<void> init() async {
    if (kIsWeb || _handler != null) return;

    // Audio focus / AVAudioSession (Android, iOS). Other platforms have no implementation: ignored.
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen(_onInterruption); // a call, another app taking the audio
      session.becomingNoisyEventStream.listen((_) => _controls?.pause()); // headphones unplugged
    } catch (e) {
      talker.info('no audio session on this platform: $e');
    }

    try {
      _handler = await AudioService.init(
        builder: _AvarimAudioHandler.new,
        config: const AudioServiceConfig(
          // Also used as a part of the D-Bus name on Linux and required on Windows.
          androidNotificationChannelId: 'ir.avarim.channel.audio',
          androidNotificationChannelName: 'Playback',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );
    } catch (e, st) {
      talker.error('could not start the media session', e, st);
    }
  }

  /// Shows [track] to the OS and follows [states]. Returns the token to pass to [detach] and [update].
  static Object attach(SessionTrack track, SessionControls controls, Stream<AudioPlayerState> states) {
    final token = Object();
    _token = token;
    _track = track;
    _controls = controls;
    _last = null;
    _pausedByInterruption = false;

    _subscription?.cancel();
    _subscription = states.listen(_onState);

    _publishMetadata(null);
    return token;
  }

  /// The title / artist (they load a moment after the track) or the available buttons changed.
  static void update(Object token, SessionTrack track, SessionControls controls) {
    if (_token != token) return;
    _track = track;
    _controls = controls;

    _publishMetadata(_last?.duration);
    final last = _last;
    if (last != null) _publishPlayback(last);
  }

  /// A player went away. Ignored when a newer one has attached meanwhile (the next track is built before the
  /// previous one is disposed).
  static void detach(Object token) {
    if (_token != token) return;
    _token = null;
    _track = null;
    _controls = null;
    _last = null;
    _subscription?.cancel();
    _subscription = null;

    _handler?.playbackState.add(PlaybackState(processingState: AudioProcessingState.idle, playing: false));
  }

  // ---- mirroring the player to the OS --------------------------------------

  static void _onState(AudioPlayerState s) {
    final previous = _last;
    _last = s;

    if (previous == null || previous.duration != s.duration) _publishMetadata(s.duration);

    // Position ticks come many times a second; the OS moves the position by itself while playing, so only real
    // changes are pushed: status, speed, or a jump (a seek).
    final jumped = previous != null && (s.position - previous.position).abs() > const Duration(seconds: 2);
    if (previous == null || previous.status != s.status || previous.speed != s.speed || jumped) _publishPlayback(s);
  }

  static void _publishMetadata(Duration? duration) {
    final handler = _handler;
    final track = _track;
    if (handler == null || track == null) return;

    final title = track.title?.trim() ?? '';
    handler.mediaItem.add(
      MediaItem(
        id: track.id,
        title: title.isEmpty ? 'Avarim' : title,
        artist: track.artist,
        artUri: track.artUrl == null ? null : Uri.tryParse(track.artUrl!),
        artHeaders: track.artHeaders,
        duration: (duration != null && duration > Duration.zero) ? duration : null,
      ),
    );
  }

  static void _publishPlayback(AudioPlayerState s) {
    final handler = _handler;
    final controls = _controls;
    if (handler == null || controls == null) return;

    final playing = s.status == AudioPlayerStatus.playing || s.status == AudioPlayerStatus.buffering;
    final processing = switch (s.status) {
      AudioPlayerStatus.idle || AudioPlayerStatus.error => AudioProcessingState.idle,
      AudioPlayerStatus.loading => AudioProcessingState.loading,
      AudioPlayerStatus.buffering => AudioProcessingState.buffering,
      AudioPlayerStatus.playing || AudioPlayerStatus.paused => AudioProcessingState.ready,
      AudioPlayerStatus.ended => AudioProcessingState.completed,
    };
    final buttons = <MediaControl>[
      if (controls.previous != null) MediaControl.skipToPrevious,
      playing ? MediaControl.pause : MediaControl.play,
      if (controls.next != null) MediaControl.skipToNext,
    ];

    handler.playbackState.add(
      PlaybackState(
        controls: buttons,
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: [for (var i = 0; i < buttons.length; i++) i],
        processingState: processing,
        playing: playing,
        updatePosition: s.position,
        bufferedPosition: s.buffered,
        speed: s.speed,
      ),
    );
  }

  // ---- audio focus ---------------------------------------------------------

  static void _onInterruption(AudioInterruptionEvent event) {
    final controls = _controls;
    if (controls == null) return;

    if (event.begin) {
      // Something else wants the audio (a call, another player): pause, and remember to resume afterwards.
      if (_last?.isPlaying ?? false) {
        _pausedByInterruption = true;
        controls.pause();
      }
    } else if (_pausedByInterruption) {
      _pausedByInterruption = false;
      if (event.type != AudioInterruptionType.unknown) controls.play();
    }
  }
}
