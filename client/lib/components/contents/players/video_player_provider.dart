import 'package:avarim/components/contents/players/media_kit_player.dart';
import 'package:avarim/components/contents/players/player_factory.dart';
import 'package:avarim/components/contents/players/player_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'video_player_provider.g.dart';

@riverpod
AppVideoPlayer videoPlayer(Ref ref) {
  final player = createPlayer();
  ref.onDispose(player.dispose);
  return player;
}

@riverpod
VideoController? videoController(Ref ref) {
  if (kIsWeb) return null;
  final player = ref.watch(videoPlayerProvider);
  if (player is MediaKitVideoPlayer) {
    return VideoController(player.nativePlayer);
  }
  return null;
}

@riverpod
Stream<PlayerState> playerState(Ref ref) {
  final player = ref.watch(videoPlayerProvider);
  return player.stateStream;
}

@riverpod
class VideoPlayerCommands extends _$VideoPlayerCommands {
  @override
  void build() {}

  AppVideoPlayer? _getPlayer() {
    if (!ref.mounted) return null;
    return ref.watch(videoPlayerProvider);
  }

  Future<void> open(String url, {Map<String, String>? headers}) async {
    await _getPlayer()?.open(url, headers: headers);
  }

  PlayerState? getState() {
    return _getPlayer()?.state;
  }

  Future<void> play() async {
    await _getPlayer()?.play();
  }

  Future<void> pause() async {
    await _getPlayer()?.pause();
  }

  Future<void> togglePlayPause() async {
    final player = _getPlayer();
    if (player == null) return;

    player.togglePlayPause();
  }

  Future<void> seek(Duration position) async {
    await _getPlayer()?.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _getPlayer()?.setVolume(volume);
  }
}
