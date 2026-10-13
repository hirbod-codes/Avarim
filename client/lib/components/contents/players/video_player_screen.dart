import 'dart:async';

import 'package:avarim/app_config.dart';
import 'package:avarim/components/contents/players/media_kit_player.dart';
import 'package:avarim/components/contents/players/player_control_widgets.dart';
import 'package:avarim/components/contents/players/player_factory.dart';
import 'package:avarim/components/contents/players/player_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.videoId, required this.url, this.accessToken, this.headers, this.title});

  final String videoId;
  final String url;
  final String? accessToken;
  final Map<String, String>? headers;
  final String? title;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  bool _controlsVisible = true;
  Timer? _hideTimer;

  static const _controlsTimeout = Duration(seconds: 5);

  late final AppVideoPlayer _player;
  late final VideoController? _videoController;
  bool _showVideoSurface = false;
  bool _loading = false;

  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    // Each VideoPlayerScreen instance gets its own player, not a shared app-wide one
    _player = createPlayer();
    _videoController = _player is MediaKitVideoPlayer ? VideoController(_player.nativePlayer as dynamic) : null;
    _stateSub = _player.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _showVideoSurface = state.status != PlayerStatus.idle && state.status != PlayerStatus.loading && state.status != PlayerStatus.error;
          _loading = state.status == PlayerStatus.loading;
        });
      }
    });

    // Hide system UI for a cinematic look
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Start loading the video
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _player.open(widget.url, headers: widget.headers);
    });

    // Start the controls auto-hide timer
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsTimeout, () {
      if (mounted && _controlsVisible) setState(() => _controlsVisible = false);
    });
  }

  void _resetSchedule() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _onTap() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (!_showVideoSurface)
          Positioned.fill(
            child: _AlbumArt(videoId: widget.videoId, accessToken: widget.accessToken),
          ),

        // ── Video frame fills the whole screen ──────────────────────────
        if (_showVideoSurface)
          Positioned.fill(
            child: Video(
              controller: _videoController!,
              fit: BoxFit.contain,
              // We own the controls — turn off the built-in overlay.
              controls: NoVideoControls,
            ),
          ),

        Positioned.fill(
          child: GestureDetector(
            onTap: _onTap,
            behavior: HitTestBehavior.opaque,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),

        // ── Bottom controls ─────────────────────────────────────────────
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          bottom: _controlsVisible ? 0 : -120,
          left: 0,
          right: 0,
          child: PlayerControls(player: _player, state: _player.state, onTouch: _resetSchedule),
        ),

        // ── Center spinner while loading ─────────────────────────────────
        if (_loading) Center(child: CircularProgressIndicator(color: Colors.white70)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Album art
// ---------------------------------------------------------------------------

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({this.videoId, this.accessToken});
  final String? videoId;
  final String? accessToken;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: videoId != null && accessToken != null
          ? Image.network('${AppConfig.apiUrl}/api/video/thumbnail/$videoId', fit: BoxFit.contain, headers: {'Authorization': 'Bearer $accessToken'})
          : Icon(Icons.music_note_rounded, size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

// class _TopBar extends StatelessWidget {
//   const _TopBar({this.title});
//   final String? title;

//   @override
//   Widget build(BuildContext context) {
//     return DecoratedBox(
//       decoration: const BoxDecoration(
//         gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent]),
//       ),
//       child: SafeArea(
//         bottom: false,
//         child: Row(
//           children: [
//             if (title != null)
//               Expanded(
//                 child: Text(
//                   title!,
//                   style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
//                   overflow: TextOverflow.ellipsis,
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }
// }
