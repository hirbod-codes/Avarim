// now_playing_dock.dart
//
// A full-width, minimizable player dock pinned to the bottom (SoundCloud-style):
//
//   - minimized: a slim bar (title / artists, expand, close)
//   - expanded:  the same bar + the full player opening upward above it
//
// The player STAYS MOUNTED while minimized (it is just clipped to zero height),
// so playback continues.
//
// Usage:
//   ref.read(nowPlayingProvider.notifier).play(audioId: id, title: title);
//   ...
//   Stack(children: [content, Align(alignment: Alignment.bottomCenter, child: NowPlayingDock())])
//
// The provider is autoDispose, so the dock (and playback) goes away together
// with the page hosting it. To keep playing across navigation, make it a plain
// NotifierProvider and mount one NowPlayingDock app-wide, e.g. in
// MaterialApp.builder (that also makes it span the sidebar on desktop).

import 'dart:math' as math;

import 'package:avarim/components/contents/audio_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height the player is laid out at. AudioPlayerScreen isn't scrollable and needs
/// roughly 730px, so it is always built at this size and scaled DOWN (not cropped)
/// when the screen can't fit it. Raise it if the player ever grows.
const kPlayerDesignHeight = 760.0;

/// The player is designed for a phone/card width, so on wide screens it stays
/// centered at this width inside the full-width dock instead of stretching.
const kPlayerMaxContentWidth = 560.0;

/// Height of the always-visible bar.
const kDockHeaderHeight = 64.0;

/// Space the dock occupies when minimized (excluding the bottom safe-area inset).
/// Lists can use it as bottom padding so the last item isn't hidden behind the dock.
const kDockCollapsedExtent = kDockHeaderHeight;

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class NowPlaying {
  const NowPlaying({required this.audioId, required this.title, this.subtitle, this.minimized = false});

  final String audioId;
  final String title;
  final String? subtitle;
  final bool minimized;

  NowPlaying copyWith({bool? minimized}) => NowPlaying(audioId: audioId, title: title, subtitle: subtitle, minimized: minimized ?? this.minimized);
}

class NowPlayingNotifier extends Notifier<NowPlaying?> {
  @override
  NowPlaying? build() => null;

  /// Opens the dock for [audioId]. If it's already the loaded track, it is
  /// just brought back up (no reload).
  void play({required String audioId, required String title, String? subtitle}) {
    final current = state;
    if (current != null && current.audioId == audioId) {
      state = current.copyWith(minimized: false);
      return;
    }
    state = NowPlaying(audioId: audioId, title: title, subtitle: subtitle);
  }

  void toggleMinimized() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(minimized: !current.minimized);
  }

  /// Closes the dock and disposes the player.
  void close() => state = null;
}

final nowPlayingProvider = NotifierProvider.autoDispose<NowPlayingNotifier, NowPlaying?>(NowPlayingNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Dock
// ─────────────────────────────────────────────────────────────────────────────

class NowPlayingDock extends ConsumerWidget {
  const NowPlayingDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final np = ref.watch(nowPlayingProvider);
    if (np == null) return const SizedBox.shrink();

    final notifier = ref.read(nowPlayingProvider.notifier);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Never taller than the space we're given (small phones, short windows).
        final available = constraints.maxHeight - bottomInset - kDockHeaderHeight;
        final playerHeight = math.min(kPlayerDesignHeight, math.max(0.0, available));

        return SizedBox(
          width: double.infinity,
          child: Material(
            elevation: 12,
            color: theme.colorScheme.surfaceContainerHigh,
            clipBehavior: Clip.hardEdge,
            child: Padding(
              // The dock's color extends under the system navigation bar.
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The player is always built; minimizing only animates its
                  // visible height to 0 so playback isn't interrupted.
                  ClipRect(
                    child: AnimatedAlign(
                      alignment: Alignment.topCenter,
                      heightFactor: np.minimized ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: SizedBox(
                        width: double.infinity,
                        height: playerHeight,
                        child: ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: kPlayerMaxContentWidth),
                              child: LayoutBuilder(
                                builder: (context, box) => FittedBox(
                                  // Only ever shrinks: when less than kPlayerDesignHeight is
                                  // available the whole player scales down instead of overflowing.
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: box.maxWidth,
                                    height: kPlayerDesignHeight,
                                    child: AudioContainer(
                                      // New key per track -> AudioContainer reloads for the new audio.
                                      key: ValueKey(np.audioId),
                                      audioId: np.audioId,
                                      height: kPlayerDesignHeight,
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _DockHeader(title: np.title, subtitle: np.subtitle, minimized: np.minimized, onToggle: notifier.toggleMinimized, onClose: notifier.close),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DockHeader extends StatelessWidget {
  const _DockHeader({required this.title, required this.subtitle, required this.minimized, required this.onToggle, required this.onClose});

  final String title;
  final String? subtitle;
  final bool minimized;
  final VoidCallback onToggle;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    return InkWell(
      onTap: onToggle,
      child: SizedBox(
        height: kDockHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: Row(
            children: [
              Icon(Icons.music_note, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    if (hasSubtitle) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(tooltip: minimized ? 'Expand' : 'Minimize', icon: Icon(minimized ? Icons.expand_less : Icons.expand_more), onPressed: onToggle),
              IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
        ),
      ),
    );
  }
}
