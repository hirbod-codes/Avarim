// web_audio_player_stub.dart
//
// Used on every platform except web (see audio_player_factory.dart): there is no web engine there, so this just
// falls back to the regular player. It is never actually created.

import 'package:avarim/components/contents/players/audio/media_kit_audio_player.dart';

class WebAudioPlayer extends MediaKitAudioPlayer {
  WebAudioPlayer();
}
