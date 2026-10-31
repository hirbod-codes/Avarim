// playback_controller.dart
//
// Plays the queue, without any widget.
//
// The queue (AudioPlayerService) says WHAT should play. This opens the track in the one audio engine, starts it,
// moves to the next track when one ends and keeps the OS media controls up to date. The dock only shows the
// engine and sends it commands.
//
// It must not depend on widgets: while the window is minimized (Windows) or the app is in the background (mobile)
// Flutter draws no frames, so nothing that widgets do (opening a track from initState, rebuilding after the queue
// moved on) happens until the app is visible again. Streams, futures and timers keep running, and that is all
// this uses.

import 'dart:async';

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/providers/audio_links.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/auth/token_storage.dart';
import 'package:avarim/components/contents/players/audio/audio_player_factory.dart';
import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/equalizer_settings.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/components/global/system_media_session.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/lib/talker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlaybackController {
  PlaybackController._();

  static final PlaybackController instance = PlaybackController._();

  ProviderContainer? _container;
  AppAudioPlayer? _player;
  StreamSubscription<AudioPlayerState>? _stateSubscription;
  AudioPlayerStatus? _lastStatus;

  String? _loadedKey; // '<audioId>#<session>' of the track that is (being) loaded
  int _ticket = 0; // a load that finds a newer ticket was overtaken and stops

  Object? _sessionToken;
  SessionTrack? _sessionTrack;

  /// The audio engine everything talks to. Created on first use, kept from track to track (so the equalizer, volume
  /// and speed stay), released when the queue is closed.
  AppAudioPlayer get player {
    final existing = _player;
    if (existing != null) return existing;

    final created = createAudioPlayer();
    _player = created;
    _stateSubscription = created.stateStream.listen(_onPlayerState);
    return created;
  }

  /// Starts following the queue. Call once at startup.
  void start(ProviderContainer container) {
    if (_container != null) return;
    _container = container;
    AudioPlayerService.queue.addListener(_onQueue);
    _onQueue();
  }

  // ---- the queue -----------------------------------------------------------

  void _onQueue() {
    final state = AudioPlayerService.queue.value;
    if (state.isEmpty) {
      _release();
      return;
    }

    final key = '${state.currentId}#${state.session}';
    if (key != _loadedKey) {
      _loadedKey = key;
      unawaited(_load(state));
    } else {
      _refreshSession(state); // the next / previous buttons depend on the queue
    }
  }

  void _release() {
    _ticket++;
    _loadedKey = null;

    final token = _sessionToken;
    if (token != null) SystemMediaSession.detach(token);
    _sessionToken = null;
    _sessionTrack = null;

    _stateSubscription?.cancel();
    _stateSubscription = null;
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
  }

  // ---- loading a track -----------------------------------------------------

  Future<void> _load(AudioQueueState state) async {
    final container = _container;
    if (container == null) return;

    final audioId = state.currentId!;
    final ticket = ++_ticket;
    final player = this.player;
    // The engine may still say "ended" for the track before: that isn't a new end.
    _lastStatus = player.state.status;

    try {
      final accessToken = await container.read(tokenStorageProvider).getAccessToken();
      String? signedToken;
      if (kIsWeb) signedToken = await container.read(audioControllerProvider).getSignedToken(audioId: audioId);
      if (ticket != _ticket) return;

      if (accessToken == null || accessToken.isEmpty) {
        NotificationService.showError(message: _failureText());
        return;
      }

      final url = '${AppConfig.apiUrl}/api/audio/file${kIsWeb ? '/web' : ''}/$audioId${signedToken == null ? '' : '/$signedToken'}';
      final headers = {'Authorization': 'Bearer $accessToken'};

      _attachSession(state, audioId, headers, ticket);

      await player.open(url, headers: headers);
      if (ticket != _ticket) return;

      // The user's equalizer settings follow them from track to track.
      unawaited(EqualizerStore.applyTo(player.equalizer));

      // Not awaited: play() may only complete when playback stops.
      if (state.autoPlay && !player.state.hasError) unawaited(player.play());
    } catch (e, st) {
      talker.error('could not start $audioId', e, st);
      if (ticket == _ticket) NotificationService.showError(message: _failureText());
    }
  }

  String _failureText() {
    final context = rootNavigatorKey.currentContext;
    return (context == null ? null : AppLocalizations.of(context))?.audio_fetch_failed ?? 'Could not load the audio';
  }

  /// A track ended: on to the next one (the last one just stays ended).
  void _onPlayerState(AudioPlayerState s) {
    final ended = s.status == AudioPlayerStatus.ended;
    final wasEnded = _lastStatus == AudioPlayerStatus.ended;
    _lastStatus = s.status;

    if (ended && !wasEnded) AudioPlayerService.next();
  }

  // ---- the OS media controls ----------------------------------------------

  SessionControls _controls(AudioQueueState state) {
    final player = this.player;
    return SessionControls(
      play: player.play,
      pause: player.pause,
      seek: player.seek,
      next: state.hasNext ? AudioPlayerService.next : null,
      previous: state.hasPrevious ? AudioPlayerService.previous : null,
    );
  }

  void _refreshSession(AudioQueueState state) {
    final token = _sessionToken;
    final track = _sessionTrack;
    if (token != null && track != null) SystemMediaSession.update(token, track, _controls(state));
  }

  void _attachSession(AudioQueueState state, String audioId, Map<String, String> headers, int ticket) {
    final container = _container!;
    final track = SessionTrack(id: audioId, artUrl: '${AppConfig.apiUrl}/api/audio/coverArt/$audioId', artHeaders: headers);
    _sessionTrack = track;
    final token = SystemMediaSession.attach(track, _controls(state), player.stateStream);
    _sessionToken = token;

    // The title and the artists need requests of their own: the OS controls get them a moment later.
    unawaited(() async {
      try {
        final audio = await container.read(audioControllerProvider).get(audioId: audioId);

        List<Artist>? artists;
        try {
          artists = await container.read(audioArtistsProvider(audioId).future);
        } catch (_) {
          // no artists: the title alone is fine
        }
        if (ticket != _ticket || _sessionToken != token) return;

        final filled = SessionTrack(id: audioId, title: audio?.title, artist: artistsLabel(artists), artUrl: track.artUrl, artHeaders: headers);
        _sessionTrack = filled;
        SystemMediaSession.update(token, filled, _controls(AudioPlayerService.queue.value));
      } catch (e, st) {
        talker.error('could not read the title for the media controls', e, st);
      }
    }());
  }
}
