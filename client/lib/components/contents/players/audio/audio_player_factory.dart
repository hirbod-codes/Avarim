// audio_player_factory.dart
//
// Picks the audio engine:
//   - mobile / desktop: JustAudioPlayer (just_audio). Android also gets an equalizer there.
//   - web: WebAudioPlayer - an <audio> element + the Web Audio API, which is what makes an
//     equalizer possible in the browser (just_audio's web player doesn't expose its element).
//
// The web engine is only compiled on web (conditional import), so mobile builds never see it.

import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/just_audio_player.dart';
import 'package:avarim/components/contents/players/audio/web_audio_player_stub.dart'
    if (dart.library.js_interop) 'package:avarim/components/contents/players/audio/web_audio_player.dart';
import 'package:flutter/foundation.dart';

/// Set to false to go back to just_audio on web (playback only, no equalizer there).
const kUseWebAudioEngine = true;

AppAudioPlayer createAudioPlayer() => (kIsWeb && kUseWebAudioEngine) ? WebAudioPlayer() : JustAudioPlayer();
