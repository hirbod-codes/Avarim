// audio_player_service.dart  (put it next to notification_service.dart)
//
// Global audio player + queue, callable from anywhere without a BuildContext:
//
//   AudioPlayerService.play(audioId: id);                          // replace queue, start playing (mini bar)
//   AudioPlayerService.play(audioId: id, expand: true);            // ... and open the full-screen player
//   AudioPlayerService.play(audioIds: ids, startIndex: 2);         // play a whole playlist
//   AudioPlayerService.add(audioId: id);                           // append to the queue
//   AudioPlayerService.add(audioIds: ids);                         // append many
//   AudioPlayerService.remove(id);                                 // remove from the queue
//   AudioPlayerService.next() / previous() / skipTo(i)
//   AudioPlayerService.setMinimized(bool) / toggleMinimized() / close()
//
// Like NotificationService it inserts ONE persistent OverlayEntry into the root
// navigator's overlay, so the player stays above every page and keeps playing
// across navigation.
//
// Two states:
//   - minimized: a mini bar at the bottom (title, play/pause, expand, close)
//   - expanded:  the player fills the whole screen (minimize + close at the top right)
// Switching slides the player up/down while the mini bar slides the opposite way.
// The player stays mounted while minimized (it is just off-screen), so playback continues.
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
import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/audio_player_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Height of the mini bar's content row.
const kDockHeaderHeight = 64.0;

/// Thin progress line on top of the mini bar.
const kDockProgressHeight = 2.0;

/// Space the minimized dock occupies (excluding the bottom safe-area inset).
const kDockCollapsedExtent = kDockHeaderHeight + kDockProgressHeight;

/// Height reserved at the top of the full-screen player for the minimize / close buttons
/// (on top of the status-bar inset).
const kPlayerTopBarHeight = 56.0;

const _kDockAnimation = Duration(milliseconds: 300);
const _kDockCurve = Curves.easeInOutCubic;

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class AudioQueueState {
  const AudioQueueState({this.ids = const [], this.index = 0, this.minimized = false});

  final List<String> ids;

  /// Index of the current track in [ids].
  final int index;

  /// true: mini bar only. false: full-screen player.
  final bool minimized;

  bool get isEmpty => ids.isEmpty;
  String? get currentId => isEmpty ? null : ids[index];
  bool get hasNext => index < ids.length - 1;
  bool get hasPrevious => index > 0;

  AudioQueueState copyWith({List<String>? ids, int? index, bool? minimized}) =>
      AudioQueueState(ids: ids ?? this.ids, index: index ?? this.index, minimized: minimized ?? this.minimized);
}

/// Title / artists lookup for the mini bar (the queue only stores ids).
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
  /// [startIndex]. It starts in the mini bar; pass [expand] to open the
  /// full-screen player right away. If the track that would play is already the
  /// current one it keeps playing (no reload).
  static void play({String? audioId, List<String>? audioIds, int startIndex = 0, bool expand = false}) {
    final ids = _normalize(audioId, audioIds);
    if (ids.isEmpty) return;

    final index = math.min(math.max(startIndex, 0), ids.length - 1);
    final previous = _state.value;
    final sameTrack = !previous.isEmpty && previous.currentId == ids[index];

    _state.value = AudioQueueState(ids: ids, index: index, minimized: expand ? false : (sameTrack ? previous.minimized : true));
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

  /// No-op on the last track. Also what the player calls when a track finishes.
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
        // Full-screen layer. It is transparent and lets touches through everywhere
        // except on the mini bar / the expanded player.
        return Positioned.fill(child: state.isEmpty ? const SizedBox.shrink() : _Dock(state: state));
      },
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.state});

  final AudioQueueState state;

  @override
  Widget build(BuildContext context) {
    // One player (one Riverpod scope) per track, shared by the full-screen player
    // and the mini bar, so the bar's play/pause controls the very same player.
    Widget dock = ProviderScope(
      key: ValueKey(state.currentId),
      overrides: [audioPlayerCommandsProvider],
      child: _DockBody(state: state),
    );

    // Android back button / gesture: minimize the full-screen player instead of popping the page behind it.
    if (Router.maybeOf(context) != null) {
      dock = BackButtonListener(
        onBackButtonPressed: () async {
          if (AudioPlayerService.queue.value.minimized) return false;
          AudioPlayerService.setMinimized(true);
          return true;
        },
        child: dock,
      );
    }

    return dock;
  }
}

class _DockBody extends StatelessWidget {
  const _DockBody({required this.state});

  final AudioQueueState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.paddingOf(context);
    final minimized = state.minimized;
    final audioId = state.currentId!;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Full-screen player: slides down out of view when minimized, up to fill the screen when expanded.
        // It stays mounted either way, so playback is never interrupted.
        IgnorePointer(
          ignoring: minimized,
          child: ExcludeSemantics(
            excluding: minimized,
            child: AnimatedSlide(
              offset: minimized ? const Offset(0, 1) : Offset.zero,
              duration: _kDockAnimation,
              curve: _kDockCurve,
              child: Material(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AudioContainer(
                        // New key per track -> AudioContainer reloads for the new audio.
                        key: ValueKey(audioId),
                        audioId: audioId,
                        height: double.infinity,
                        borderRadius: BorderRadius.zero,
                        ownPlayerScope: false, // the dock's ProviderScope is shared with the mini bar
                        autoPlay: true,
                        onCompleted: AudioPlayerService.next,
                        // Keep the controls clear of the status bar, the top-right buttons and the nav bar.
                        contentPadding: EdgeInsets.only(top: insets.top + kPlayerTopBarHeight, bottom: insets.bottom),
                        showQueueControls: state.ids.length > 1,
                        onPrevious: state.hasPrevious ? AudioPlayerService.previous : null,
                        onNext: state.hasNext ? AudioPlayerService.next : null,
                      ),
                    ),
                    Positioned(
                      top: insets.top,
                      right: 4,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(tooltip: 'Minimize', icon: const Icon(Icons.expand_more), onPressed: AudioPlayerService.toggleMinimized),
                            IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: AudioPlayerService.close),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Mini bar: slides up when minimized, down out of view when expanded.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: !minimized,
            child: AnimatedSlide(
              // 1.5 (not 1.0) so its shadow is fully off-screen too.
              offset: minimized ? Offset.zero : const Offset(0, 1.5),
              duration: _kDockAnimation,
              curve: _kDockCurve,
              child: _MiniBar(state: state),
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniBar extends ConsumerWidget {
  const _MiniBar({required this.state});

  final AudioQueueState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final commands = ref.watch(audioPlayerCommandsProvider.notifier);
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

    return Material(
      elevation: 12,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        // The bar's color extends under the system navigation bar.
        padding: EdgeInsets.only(bottom: bottomInset),
        child: StreamBuilder<AudioPlayerState>(
          stream: commands.stateStream,
          initialData: commands.currentState,
          builder: (context, snapshot) {
            final player = snapshot.data ?? const AudioPlayerState();
            final busy = player.isLoading || player.isBuffering;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: kDockProgressHeight,
                  child: LinearProgressIndicator(value: player.progress, minHeight: kDockProgressHeight, backgroundColor: Colors.transparent),
                ),
                InkWell(
                  onTap: AudioPlayerService.toggleMinimized,
                  child: SizedBox(
                    height: kDockHeaderHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          // Play / pause first, before the music note.
                          if (busy)
                            const SizedBox(
                              width: 40,
                              height: 40,
                              child: Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2.5)),
                            )
                          else
                            IconButton(
                              tooltip: player.isPlaying ? 'Pause' : 'Play',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                player.status == AudioPlayerStatus.ended
                                    ? Icons.replay
                                    : player.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                              ),
                              onPressed: () => commands.togglePlayPause(),
                            ),
                          const SizedBox(width: 4),
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
                          if (multiple)
                            IconButton(
                              tooltip: 'Previous',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_previous),
                              onPressed: state.hasPrevious ? AudioPlayerService.previous : null,
                            ),
                          if (multiple)
                            IconButton(
                              tooltip: 'Next',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.skip_next),
                              onPressed: state.hasNext ? AudioPlayerService.next : null,
                            ),
                          IconButton(
                            tooltip: 'Expand',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.expand_less),
                            onPressed: AudioPlayerService.toggleMinimized,
                          ),
                          IconButton(
                            tooltip: 'Close',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close),
                            onPressed: AudioPlayerService.close,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Optional: keeps the end of a scrollable from hiding behind the mini bar
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
