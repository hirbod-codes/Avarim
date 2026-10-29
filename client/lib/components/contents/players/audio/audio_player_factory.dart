// audio_player_factory.dart
//
// Picks the audio engine:
//   - web: WebAudioPlayer - an <audio> element + the Web Audio API, which is what makes an equalizer possible in
//     the browser.
//   - every other platform: MediaKitAudioPlayer - libmpv through media_kit, with a 10 band equalizer.
//
// The web engine is only compiled on web (conditional import), so native builds never see it.

import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/media_kit_audio_player.dart';
import 'package:avarim/components/contents/players/audio/web_audio_player_stub.dart'
    if (dart.library.js_interop) 'package:avarim/components/contents/players/audio/web_audio_player.dart';
import 'package:flutter/foundation.dart';

AppAudioPlayer createAudioPlayer() => kIsWeb ? WebAudioPlayer() : MediaKitAudioPlayer();
