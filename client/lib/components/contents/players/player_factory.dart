import 'package:avarim/components/contents/players/player_interface.dart';

// Conditional imports: Flutter tree-shakes the unused backend at compile time.
// On web builds, dart:io is unavailable — so we import the web stub.
import 'package:avarim/components/contents/players/player_factory_native.dart';
// if (dart.library.html) 'package:avarim/components/contents/players/player_factory_web.dart';

/// Returns the correct [AppVideoPlayer] for the current platform.
AppVideoPlayer createPlayer() => createPlatformPlayer();
