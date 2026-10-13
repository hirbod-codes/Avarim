import 'package:avarim/components/contents/players/player_interface.dart';
import 'hlsjs/hls_web_video_player.dart';

AppVideoPlayer createPlatformPlayer() => HlsWebVideoPlayer();
