import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:avarim/components/contents/players/video/player_interface.dart';
import 'package:web/web.dart' as web;

import 'interop.dart';

/// Web backend that plays HLS via hls.js (Chrome/Firefox) or the browser's
/// native HLS support (Safari), rendering into a real HTML <video> element
/// through a platform view.
class HlsWebVideoPlayer implements AppVideoPlayer {
  HlsWebVideoPlayer() : viewId = 'hls-video-${_counter++}' {
    _video = web.HTMLVideoElement()
      ..autoplay = false
      ..controls = false
      ..playsInline = true;
    _video.style.width = '100%';
    _video.style.height = '100%';
    _video.style.objectFit = 'contain';
    _video.style.pointerEvents = 'none';

    ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) => _video);
    _attachVideoListeners();
  }

  static int _counter = 0;

  /// Used by HtmlElementView to render this player's <video> element.
  final String viewId;

  late final web.HTMLVideoElement _video;
  Hls? _hls;
  bool _playing = false;

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

  void _attachVideoListeners() {
    _video.addEventListener(
      'loadedmetadata',
      (web.Event _) {
        _emit(_state.copyWith(duration: Duration(milliseconds: (_video.duration * 1000).round())));
      }.toJS,
    );

    _video.addEventListener(
      'timeupdate',
      (web.Event _) {
        _emit(_state.copyWith(position: Duration(milliseconds: (_video.currentTime * 1000).round())));
      }.toJS,
    );

    _video.addEventListener(
      'progress',
      (web.Event _) {
        final buffered = _video.buffered;
        if (buffered.length > 0) {
          final end = buffered.end(buffered.length - 1);
          _emit(_state.copyWith(buffered: Duration(milliseconds: (end * 1000).round())));
        }
      }.toJS,
    );

    _video.addEventListener(
      'waiting',
      (web.Event _) {
        _emit(_state.copyWith(status: PlayerStatus.buffering));
      }.toJS,
    );

    _video.addEventListener(
      'playing',
      (web.Event _) {
        _emit(_state.copyWith(status: PlayerStatus.playing));
      }.toJS,
    );

    _video.addEventListener(
      'pause',
      (web.Event _) {
        if (_state.status != PlayerStatus.ended) {
          _emit(_state.copyWith(status: PlayerStatus.paused));
        }
      }.toJS,
    );

    _video.addEventListener(
      'ended',
      (web.Event _) {
        _emit(_state.copyWith(status: PlayerStatus.ended));
      }.toJS,
    );

    _video.addEventListener(
      'volumechange',
      (web.Event _) {
        _emit(_state.copyWith(volume: _video.volume));
      }.toJS,
    );

    _video.addEventListener(
      'error',
      (web.Event _) {
        final err = _video.error;
        _emit(_state.copyWith(status: PlayerStatus.error, error: err?.message.isNotEmpty == true ? err!.message : 'Video playback error'));
      }.toJS,
    );
  }

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    _emit(_state.copyWith(status: PlayerStatus.loading, position: Duration.zero, duration: Duration.zero, error: null));

    _hls?.destroy();
    _hls = null;

    final canPlayNative = _video.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;

    if (canPlayNative) {
      // Safari: native HLS, no hls.js needed.
      _video.src = url;
    } else if (Hls.isSupported()) {
      final hls = Hls();
      _hls = hls;

      hls.on(
        HlsEvent.error,
        ((JSAny _, HlsErrorData data) {
          _handleHlsError(data);
        }).toJS,
      );

      hls.attachMedia(_video);
      hls.loadSource(url);
    } else {
      _emit(_state.copyWith(status: PlayerStatus.error, error: 'HLS playback is not supported in this browser.'));
      return;
    }

    _emit(_state.copyWith(status: PlayerStatus.paused));

    // try {
    //   await _video.play().toDart;
    //   _playing = true;
    // } catch (_) {
    //   // Autoplay likely blocked by the browser — user can hit play manually.
    // }
  }

  void _handleHlsError(HlsErrorData data) {
    if (!data.fatal) return;

    switch (data.type) {
      case HlsErrorType.network:
        _hls?.startLoad();
        break;
      case HlsErrorType.media:
        _hls?.recoverMediaError();
        break;
      default:
        _emit(_state.copyWith(status: PlayerStatus.error, error: 'Fatal HLS error: ${data.type} (${data.details})'));
        _hls?.destroy();
        _hls = null;
    }
  }

  @override
  Future<void> play() async {
    await _video.play().toDart;
    _playing = true;
  }

  @override
  Future<void> pause() async {
    _video.pause();
    _playing = false;
  }

  @override
  Future<void> togglePlayPause() async {
    if (_playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    _video.currentTime = position.inMilliseconds / 1000;
  }

  @override
  Future<void> setVolume(double volume) async {
    _video.volume = volume.clamp(0.0, 1.0);
  }

  @override
  Future<void> dispose() async {
    _hls?.destroy();
    _hls = null;
    _video.pause();
    _video.removeAttribute('src');
    _video.load();
    await _stateController.close();
  }
}
