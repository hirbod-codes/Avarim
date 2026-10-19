import 'package:avarim/components/contents/players/video/player_interface.dart';
import 'media_kit_player.dart';

AppVideoPlayer createPlatformPlayer() => MediaKitVideoPlayer();
