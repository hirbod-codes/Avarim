// web_audio_player.dart  (web only - see audio_player_factory.dart)
//
// The browser engine: a plain <audio> element, plus the Web Audio API for the equalizer.
//
// Needs `web` in pubspec.yaml (`flutter pub add web`; it is already pulled in by just_audio_web).
//
// Notes
//  - An <audio> element can't send an Authorization header. That is fine: on web the app already
//    plays a signed URL (see AudioContainer), so `headers` are ignored here.
//  - Web Audio can only process media that was loaded with CORS (crossOrigin = 'anonymous'), otherwise
//    the browser outputs silence. So the audio is first loaded that way. If that fails (the server sends
//    no CORS headers for audio) it is loaded once more the plain way: playback keeps working, only the
//    equalizer is reported as unavailable.
//  - The Web Audio graph is only built when the user actually turns the equalizer on with a non-flat
//    curve, and only after the audio has loaded. Without that, playback never touches Web Audio.

import 'dart:async';
import 'dart:js_interop';

import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:web/web.dart' as web;

class WebAudioPlayer implements AppAudioPlayer {
  WebAudioPlayer() {
    _audio = web.HTMLAudioElement()..preload = 'auto';
    _equalizer = _WebEqualizer(this);

    _listen('loadedmetadata', (_) {
      _loaded = true;
      _syncDuration();
      _equalizer._apply(); // the equalizer may have been waiting for the audio to load
    });
    _listen('durationchange', (_) => _syncDuration());
    _listen('timeupdate', (_) => _emit(_state.copyWith(position: _position)));
    _listen('progress', (_) => _emit(_state.copyWith(buffered: _bufferedEnd)));
    _listen('waiting', (_) => _emit(_state.copyWith(status: _audio.paused ? AudioPlayerStatus.loading : AudioPlayerStatus.buffering)));
    _listen('canplay', (_) {
      if (_state.hasError || _state.status == AudioPlayerStatus.ended) return;
      _emit(_state.copyWith(status: _audio.paused ? AudioPlayerStatus.paused : AudioPlayerStatus.playing));
    });
    _listen('playing', (_) => _emit(_state.copyWith(status: AudioPlayerStatus.playing)));
    _listen('pause', (_) {
      if (!_audio.ended) _emit(_state.copyWith(status: AudioPlayerStatus.paused));
    });
    _listen('seeked', (_) {
      if (_state.status == AudioPlayerStatus.ended && !_audio.ended) _emit(_state.copyWith(status: AudioPlayerStatus.paused));
    });
    _listen('ended', (_) => _emit(_state.copyWith(status: AudioPlayerStatus.ended)));
    _listen('volumechange', (_) => _emit(_state.copyWith(volume: _audio.volume)));
    _listen('ratechange', (_) => _emit(_state.copyWith(speed: _audio.playbackRate)));
    _listen('error', (_) => _onError());
  }

  late final web.HTMLAudioElement _audio;
  late final _WebEqualizer _equalizer;

  final _stateController = StreamController<AudioPlayerState>.broadcast();
  AudioPlayerState _state = const AudioPlayerState();

  final List<(String, JSFunction)> _listeners = [];

  String? _url;
  bool _loaded = false; // metadata of the current audio is available
  bool _corsOk = true; // false once the audio had to be loaded without CORS (no equalizer then)
  bool _triedWithoutCors = false;

  @override
  Stream<AudioPlayerState> get stateStream => _stateController.stream;

  @override
  AudioPlayerState get state => _state;

  @override
  AppEqualizer? get equalizer => _equalizer;

  // ── plumbing ───────────────────────────────────────────────────────────────

  void _emit(AudioPlayerState next) {
    _state = next;
    if (!_stateController.isClosed) _stateController.add(next);
  }

  void _listen(String type, void Function(web.Event event) handler) {
    final callback = handler.toJS;
    _audio.addEventListener(type, callback);
    _listeners.add((type, callback));
  }

  static Duration _seconds(double s) => Duration(microseconds: (s * 1e6).round());

  Duration get _position => _seconds(_audio.currentTime);

  void _syncDuration() {
    final seconds = _audio.duration;
    if (seconds.isFinite && seconds > 0) _emit(_state.copyWith(duration: _seconds(seconds)));
  }

  /// End of the buffered range that contains the playhead (or the last range).
  Duration get _bufferedEnd {
    final ranges = _audio.buffered;
    if (ranges.length == 0) return Duration.zero;

    final now = _audio.currentTime;
    for (var i = 0; i < ranges.length; i++) {
      if (ranges.start(i) <= now && now <= ranges.end(i)) return _seconds(ranges.end(i));
    }
    return _seconds(ranges.end(ranges.length - 1));
  }

  void _load({required bool withCors}) {
    _loaded = false;
    if (withCors) {
      _audio.crossOrigin = 'anonymous';
    } else {
      _audio.removeAttribute('crossorigin');
    }
    _audio.src = _url!;
    _audio.load();
  }

  void _onError() {
    // Maybe the server sends no CORS headers for audio: try once more as plain media. Not possible once
    // the equalizer is wired in, because that routes the audio through Web Audio.
    if (_corsOk && !_triedWithoutCors && _url != null && !_equalizer._graphBuilt) {
      _corsOk = false;
      _triedWithoutCors = true;
      _load(withCors: false);
      return;
    }

    final error = _audio.error;
    final message = (error != null && error.message.isNotEmpty) ? error.message : 'Playback error${error == null ? '' : ' (code ${error.code})'}';
    _emit(_state.copyWith(status: AudioPlayerStatus.error, error: message));
  }

  // ── AppAudioPlayer ─────────────────────────────────────────────────────────

  @override
  Future<void> open(String url, {Map<String, String>? headers, String? title, String? artist, String? albumArtUrl}) async {
    _url = url;
    _emit(
      _state.copyWith(
        status: AudioPlayerStatus.loading,
        position: Duration.zero,
        duration: Duration.zero,
        buffered: Duration.zero,
        title: title,
        artist: artist,
        albumArtUrl: albumArtUrl,
      ),
    );
    _load(withCors: _corsOk);
  }

  @override
  Future<void> play() async {
    await _equalizer.resumeIfNeeded();
    try {
      // Completes when playback has started (not when it ends).
      await _audio.play().toDart;
    } catch (_) {
      // Blocked by the browser's autoplay policy, or interrupted by a new load: stays paused.
    }
  }

  @override
  Future<void> pause() async => _audio.pause();

  @override
  Future<void> togglePlayPause() => (_audio.paused || _audio.ended) ? play() : pause();

  @override
  Future<void> seek(Duration position) async {
    _audio.currentTime = position.inMicroseconds / 1e6;
  }

  @override
  Future<void> setVolume(double volume) async {
    _audio.volume = volume.clamp(0.0, 1.0);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _audio.playbackRate = speed.clamp(0.25, 4.0);
  }

  @override
  Future<void> skipForward([Duration amount = const Duration(seconds: 10)]) {
    final target = _position + amount;
    return seek(target > _state.duration ? _state.duration : target);
  }

  @override
  Future<void> skipBackward([Duration amount = const Duration(seconds: 10)]) {
    final target = _position - amount;
    return seek(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Future<void> dispose() async {
    for (final (type, callback) in _listeners) {
      _audio.removeEventListener(type, callback);
    }
    _listeners.clear();

    // Stop downloading and release the element.
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();

    await _equalizer.dispose();
    await _stateController.close();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Equalizer: a chain of biquad filters between the <audio> element and the speakers
// ─────────────────────────────────────────────────────────────────────────────

class _WebEqualizer implements AppEqualizer {
  _WebEqualizer(this._owner);

  final WebAudioPlayer _owner;

  /// ISO octave bands. The first / last are shelves, the rest are peaking filters.
  static const _centers = [31.0, 62.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
  static const _rangeDb = 12.0;

  web.AudioContext? _context;
  final List<web.BiquadFilterNode> _filters = [];

  bool _enabled = false;
  final List<double> _gains = List.filled(_centers.length, 0.0);

  bool get _graphBuilt => _filters.isNotEmpty;

  @override
  bool get available => _owner._corsOk;

  @override
  Future<List<EqualizerBand>> bands() async => [for (final hz in _centers) EqualizerBand(centerHz: hz, minDb: -_rangeDb, maxDb: _rangeDb)];

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _apply();
  }

  @override
  Future<void> setBandGain(int index, double db) async {
    if (index < 0 || index >= _gains.length) return;
    _gains[index] = db.clamp(-_rangeDb, _rangeDb).toDouble();
    _apply();
  }

  /// Pushes the current settings into the filters, building the graph the first time it is needed.
  void _apply() {
    if (!_graphBuilt) {
      final wantsEffect = _enabled && _gains.any((g) => g != 0);
      // Not before the audio has loaded: only then do we know that it was loaded with CORS.
      if (!wantsEffect || !available || !_owner._loaded) return;
      _buildGraph();
    }

    for (var i = 0; i < _filters.length; i++) {
      _filters[i].gain.value = _enabled ? _gains[i] : 0.0;
    }
  }

  void _buildGraph() {
    final context = web.AudioContext();
    _context = context;

    web.AudioNode node = context.createMediaElementSource(_owner._audio);
    for (var i = 0; i < _centers.length; i++) {
      final filter = context.createBiquadFilter();
      filter.type = i == 0 ? 'lowshelf' : (i == _centers.length - 1 ? 'highshelf' : 'peaking');
      filter.frequency.value = _centers[i];
      filter.Q.value = 1.41; // one octave wide
      filter.gain.value = 0;

      node.connect(filter);
      _filters.add(filter);
      node = filter;
    }
    node.connect(context.destination);

    unawaited(resumeIfNeeded());
  }

  /// Browsers start an AudioContext suspended until the page has had a user gesture.
  Future<void> resumeIfNeeded() async {
    final context = _context;
    if (context == null || context.state != 'suspended') return;
    try {
      await context.resume().toDart;
    } catch (_) {
      // Still blocked: it is resumed on the next play().
    }
  }

  Future<void> dispose() async {
    final context = _context;
    _context = null;
    _filters.clear();
    if (context == null) return;
    try {
      await context.close().toDart;
    } catch (_) {
      // Already closed.
    }
  }
}
