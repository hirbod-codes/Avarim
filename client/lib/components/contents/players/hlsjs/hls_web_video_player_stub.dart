import 'package:avarim/components/contents/players/player_interface.dart';

/// No-op stand-in used on non-web platforms so that dart:js_interop and
/// package:web are never imported outside web compilation. Never actually
/// instantiated at runtime on native platforms — player_factory_native.dart
/// always returns MediaKitVideoPlayer instead — this exists purely so the
/// type is resolvable at compile time.
class HlsWebVideoPlayer implements AppVideoPlayer {
  HlsWebVideoPlayer() : viewId = '';

  final String viewId;

  @override
  Stream<PlayerState> get stateStream => const Stream<PlayerState>.empty();

  @override
  PlayerState get state => const PlayerState();

  @override
  Future<void> open(String url, {Map<String, String>? headers}) async {
    throw UnsupportedError('HlsWebVideoPlayer is only available on web.');
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> togglePlayPause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> dispose() async {}
}
