import 'package:flutter/widgets.dart';

import 'footer_badge_stub.dart' if (dart.library.html) 'footer_badge_web.dart' as impl;

/// Renders the required `<a><img></a>` badge in the footer — web only.
/// On mobile/desktop this renders nothing (SizedBox.shrink), since raw
/// HTML injection via dart:html only exists, and only makes sense, on
/// the web platform. No runtime platform check needed here — the
/// conditional import above already resolves to the right
/// implementation at compile time, same pattern as your
/// video_player_web/just_audio_web platform splits.
class ZibalBadge extends StatelessWidget {
  const ZibalBadge({super.key});

  @override
  Widget build(BuildContext context) => impl.buildFooterBadgeWidget();
}
