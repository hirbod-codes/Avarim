// audio_player_service.dart  (put it next to notification_service.dart)
//
// Global audio player + queue, callable from anywhere without a BuildContext:
//
//   AudioPlayerService.play(audioId: id);                          // replace queue, start playing
//   AudioPlayerService.play(audioIds: ids, startIndex: 2);         // play a whole playlist
//   AudioPlayerService.add(audioId: id);                           // append to the queue
//   AudioPlayerService.add(audioIds: ids);                         // append many
//   AudioPlayerService.remove(id);                                 // remove from the queue
//   AudioPlayerService.next() / previous() / skipTo(i)
//   AudioPlayerService.toggleMinimized() / close()
//
// Like NotificationService it inserts ONE persistent OverlayEntry into the root
// navigator's overlay, so the dock is full-width, pinned to the bottom and stays
// above every page you navigate to. Playback continues across navigation.
//
// Requirements:
//   - ProviderScope above MaterialApp (the player screen uses Riverpod).
//   - rootNavigatorKey attached to the app's root Navigator (already true for
//     NotificationService).
//
// The queue is a unique list: ids that are already queued are ignored.

import 'dart:math' as math;

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/contents/audio_container.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height the player is laid out at. AudioPlayerScreen isn't scrollable and needs
/// roughly 730px, so it is always built at this size and scaled DOWN (not cropped)
/// when the screen can't fit it. Raise it if the player ever grows.
const kPlayerDesignHeight = 760.0;

/// Height of the always-visible bar.
const kDockHeaderHeight = 64.0;

/// Space the dock occupies when minimized (excluding the bottom safe-area inset).
const kDockCollapsedExtent = kDockHeaderHeight;

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class AudioQueueState {
  const AudioQueueState({this.ids = const [], this.index = 0, this.minimized = false});

  final List<String> ids;

  /// Index of the current track in [ids].
  final int index;
  final bool minimized;

  bool get isEmpty => ids.isEmpty;
  String? get currentId => isEmpty ? null : ids[index];
  bool get hasNext => index < ids.length - 1;
  bool get hasPrevious => index > 0;

  AudioQueueState copyWith({List<String>? ids, int? index, bool? minimized}) =>
      AudioQueueState(ids: ids ?? this.ids, index: index ?? this.index, minimized: minimized ?? this.minimized);
}

/// Title lookup for the dock header (the queue only stores ids).
final _audioMetaProvider = FutureProvider.autoDispose.family<Audio?, String>((ref, id) => ref.read(audioControllerProvider).get(audioId: id));

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class AudioPlayerService {
  AudioPlayerService._();

  static final ValueNotifier<AudioQueueState> _state = ValueNotifier(const AudioQueueState());
  static OverlayEntry? _entry;

  /// Listen to this from the UI (e.g. highlight the playing track, show a queue
  /// page): `ValueListenableBuilder(valueListenable: AudioPlayerService.queue, ...)`.
  static ValueListenable<AudioQueueState> get queue => _state;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Replaces the queue with [audioId] or [audioIds] and starts playing
  /// [startIndex]. If the track that would play is already the current one it
  /// keeps playing (no reload) and the dock is just brought back up.
  static void play({String? audioId, List<String>? audioIds, int startIndex = 0}) {
    final ids = _normalize(audioId, audioIds);
    if (ids.isEmpty) return;

    _state.value = AudioQueueState(ids: ids, index: math.min(math.max(startIndex, 0), ids.length - 1));
    _ensureDock();
  }

  /// Appends to the end of the queue. Starts playing if nothing is queued yet.
  /// The current track is never interrupted.
  static void add({String? audioId, List<String>? audioIds}) {
    final incoming = _normalize(audioId, audioIds);
    if (incoming.isEmpty) return;

    final s = _state.value;
    if (s.isEmpty) {
      play(audioIds: incoming);
      return;
    }

    final fresh = incoming.where((id) => !s.ids.contains(id)).toList();
    if (fresh.isEmpty) return;

    _state.value = s.copyWith(ids: [...s.ids, ...fresh]);
  }

  /// Removes a track from the queue.
  ///  - before the current one: playback is untouched
  ///  - the current one: the next track takes its place (or the previous one if it was last)
  ///  - last remaining: the dock closes
  static void remove(String audioId) {
    final s = _state.value;
    final removedAt = s.ids.indexOf(audioId);
    if (removedAt == -1) return;

    final ids = [...s.ids]..removeAt(removedAt);
    if (ids.isEmpty) {
      close();
      return;
    }

    var index = s.index;
    if (removedAt < index) {
      index--;
    } else if (removedAt == index) {
      index = math.min(index, ids.length - 1);
    }

    _state.value = s.copyWith(ids: ids, index: index);
  }

  static void skipTo(int index) {
    final s = _state.value;
    if (s.isEmpty || index < 0 || index >= s.ids.length || index == s.index) return;
    _state.value = s.copyWith(index: index);
  }

  /// No-op on the last track. Also what the player should call when a track finishes.
  static void next() {
    final s = _state.value;
    if (s.hasNext) _state.value = s.copyWith(index: s.index + 1);
  }

  static void previous() {
    final s = _state.value;
    if (s.hasPrevious) _state.value = s.copyWith(index: s.index - 1);
  }

  static void setMinimized(bool minimized) {
    final s = _state.value;
    if (s.isEmpty || s.minimized == minimized) return;
    _state.value = s.copyWith(minimized: minimized);
  }

  static void toggleMinimized() => setMinimized(!_state.value.minimized);

  /// Clears the queue, disposes the player and hides the dock.
  static void close() => _state.value = const AudioQueueState();

  // ── Internals ──────────────────────────────────────────────────────────────

  static List<String> _normalize(String? audioId, List<String>? audioIds) {
    assert((audioId == null) != (audioIds == null), 'Pass either audioId or audioIds');
    // A set literal keeps insertion order and drops duplicates.
    return <String>{if (audioId != null) audioId, ...?audioIds}.where((id) => id.isNotEmpty).toList();
  }

  static void _ensureDock() {
    if (_entry != null && _entry!.mounted) return;

    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Called before the root navigator exists (e.g. during startup): retry next frame.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_state.value.isEmpty) _ensureDock();
      });
      return;
    }

    // Stays inserted for the app's lifetime (like NotificationService); it
    // renders nothing while the queue is empty.
    _entry = OverlayEntry(builder: (_) => const _AudioDockOverlay());
    overlay.insert(_entry!);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dock
// ─────────────────────────────────────────────────────────────────────────────

class _AudioDockOverlay extends StatelessWidget {
  const _AudioDockOverlay();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, state, _) {
        // Positioned.fill + Align: the dock gets bounded (loose) constraints, and
        // the empty area around it doesn't swallow touches.
        return Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: state.isEmpty ? const SizedBox.shrink() : _Dock(state: state),
          ),
        );
      },
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.state});

  final AudioQueueState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final audioId = state.currentId!;

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
                      heightFactor: state.minimized ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      child: SizedBox(
                        width: double.infinity,
                        height: playerHeight,
                        child: ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: LayoutBuilder(
                            builder: (context, box) {
                              // The player is built at kPlayerDesignHeight and scaled DOWN (never up)
                              // when the screen is shorter. The design width is widened by the same
                              // factor, so after scaling it still spans the full screen width.
                              final scale = (box.maxHeight / kPlayerDesignHeight).clamp(0.05, 1.0);
                              return FittedBox(
                                fit: BoxFit.scaleDown,
                                child: SizedBox(
                                  width: box.maxWidth / scale,
                                  height: kPlayerDesignHeight,
                                  child: AudioContainer(
                                    // New key per track -> AudioContainer reloads for the new audio.
                                    key: ValueKey(audioId),
                                    audioId: audioId,
                                    height: kPlayerDesignHeight,
                                    borderRadius: BorderRadius.zero,
                                    autoPlay: true,
                                    onCompleted: AudioPlayerService.next,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  _DockHeader(state: state),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DockHeader extends ConsumerWidget {
  const _DockHeader({required this.state});

  final AudioQueueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = ref.watch(_audioMetaProvider(state.currentId!));
    final audio = meta.value;
    final title = audio?.title ?? (meta.hasError ? '—' : '…');
    final multiple = state.ids.length > 1;

    // "2 / 5 · Artist A, Artist B · Album" (the parts that exist)
    final subtitle = [
      if (multiple) '${state.index + 1} / ${state.ids.length}',
      audio?.tags?.artists.join(', '),
      audio?.tags?.album,
    ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');

    return InkWell(
      onTap: AudioPlayerService.toggleMinimized,
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
                    if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              if (multiple) ...[
                IconButton(
                  tooltip: 'Previous',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.skip_previous),
                  onPressed: state.hasPrevious ? AudioPlayerService.previous : null,
                ),
                IconButton(
                  tooltip: 'Next',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.skip_next),
                  onPressed: state.hasNext ? AudioPlayerService.next : null,
                ),
              ],
              IconButton(
                tooltip: state.minimized ? 'Expand' : 'Minimize',
                visualDensity: VisualDensity.compact,
                icon: Icon(state.minimized ? Icons.expand_less : Icons.expand_more),
                onPressed: AudioPlayerService.toggleMinimized,
              ),
              IconButton(tooltip: 'Close', visualDensity: VisualDensity.compact, icon: const Icon(Icons.close), onPressed: AudioPlayerService.close),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Optional: keeps the end of a scrollable from hiding behind the dock
// ─────────────────────────────────────────────────────────────────────────────

/// Drop at the end of a list / as a last sliver (`SliverToBoxAdapter(child: AudioDockSpacer())`).
/// Takes the minimized dock's height while something is queued, nothing otherwise.
class AudioDockSpacer extends StatelessWidget {
  const AudioDockSpacer({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, state, _) => SizedBox(height: state.isEmpty ? 0 : kDockCollapsedExtent + bottomInset),
    );
  }
}
