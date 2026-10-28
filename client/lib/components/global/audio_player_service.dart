// audio_player_service.dart  (put it next to notification_service.dart)
//
// Global audio player + persistent queue, callable from anywhere without a BuildContext:
//
//   AudioPlayerService.play(audioId: id);                          // replace queue, start playing (mini bar)
//   AudioPlayerService.play(audioId: id, expand: true);            // ... and open the full-screen player
//   AudioPlayerService.play(audioIds: ids, startIndex: 2);         // play a whole playlist
//
//   AudioPlayerService.add(audioId: id);                           // add to the queue AND play it now (queue is kept)
//   AudioPlayerService.add(audioIds: playlist.audioIds);           // add many, start with the first of them
//   AudioPlayerService.add(audioId: id, play: false);              // add silently, current track keeps playing
//   AudioPlayerService.playNext(audioId: id);                      // insert right after the current track
//   AudioPlayerService.playNext(audioIds: ids);
//   AudioPlayerService.remove(id);
//   AudioPlayerService.move(oldIndex, newIndex);
//   AudioPlayerService.next() / previous() / skipTo(i)
//
//   AudioPlayerService.setMinimized(bool) / toggleMinimized()
//   AudioPlayerService.setQueueVisible(bool) / toggleQueueVisible()   // queue panel inside the full-screen player
//   AudioPlayerService.close();                                    // stop, clear the queue (also from storage)
//
//   await AudioPlayerService.restore();                            // bring back last session's queue (see below)
//
// Like NotificationService it inserts ONE persistent OverlayEntry into the root
// navigator's overlay, so the player stays above every page and keeps playing
// across navigation.
//
// Two states:
//   - minimized: a mini bar at the bottom (title, play/pause, expand, close)
//   - expanded:  the player fills the whole screen (minimize / close at the top right, queue next to the speed button)
//
// PERSISTENCE
//   The queue (ids + current index) is saved to shared_preferences (Android, iOS, web, desktop)
//   on every change. Nothing is saved while the queue is empty.
//   - call `AudioPlayerService.restore()` once the user is SIGNED IN (e.g. on app start when a token
//     exists, or right after login). It shows the mini bar with the last track, paused.
//   - call `AudioPlayerService.close()` on logout, so the next account doesn't inherit the queue.
//
// Requirements:
//   - shared_preferences in pubspec.yaml
//   - ProviderScope above MaterialApp (the player screen uses Riverpod).
//   - rootNavigatorKey attached to the app's root Navigator (already true for NotificationService).
//
// The queue is a unique list: ids that are already queued are ignored.

import 'dart:async';
import 'dart:math' as math;

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/pages/search/album_playlist_menu.dart' show SaveAsPlaylistButton;
import 'package:avarim/api/providers/audio_links.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/contents/audio_container.dart';
import 'package:avarim/components/contents/players/audio/audio_player_interface.dart';
import 'package:avarim/components/contents/players/audio/audio_player_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Height of the mini bar's content row.
const kDockHeaderHeight = 64.0;

/// Thin progress line on top of the mini bar.
const kDockProgressHeight = 2.0;

/// Space the minimized dock occupies (excluding the bottom safe-area inset).
const kDockCollapsedExtent = kDockHeaderHeight + kDockProgressHeight;

/// Height of the strip along the top edge of the minimized dock that can be tapped / dragged to seek. It is
/// drawn over the top of the bar, so it doesn't change [kDockCollapsedExtent].
const kDockSeekHeight = 14.0;

/// Height reserved at the top of the full-screen player for the minimize / close buttons
/// (on top of the status-bar inset).
const kPlayerTopBarHeight = 56.0;

/// On wide screens the queue panel stays centered at this width.
const kQueuePanelMaxWidth = 560.0;

const _kDockAnimation = Duration(milliseconds: 300);
const _kDockCurve = Curves.easeInOutCubic;

const _kQueueIdsKey = 'avarim.audio_queue.ids';
const _kQueueIndexKey = 'avarim.audio_queue.index';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

@immutable
class AudioQueueState {
  const AudioQueueState({this.ids = const [], this.index = 0, this.minimized = false, this.autoPlay = true, this.session = 0});

  final List<String> ids;

  /// Index of the current track in [ids].
  final int index;

  /// true: mini bar only. false: full-screen player.
  final bool minimized;

  /// Whether the current track starts playing when it is loaded. False only for a queue that was
  /// restored from storage (it must not start making noise when the app opens).
  final bool autoPlay;

  /// Bumped to force the current track to reload (a restored, never-started track the user asks to play).
  final int session;

  bool get isEmpty => ids.isEmpty;
  String? get currentId => isEmpty ? null : ids[index];
  bool get hasNext => index < ids.length - 1;
  bool get hasPrevious => index > 0;

  AudioQueueState copyWith({List<String>? ids, int? index, bool? minimized, bool? autoPlay, int? session}) => AudioQueueState(
    ids: ids ?? this.ids,
    index: index ?? this.index,
    minimized: minimized ?? this.minimized,
    autoPlay: autoPlay ?? this.autoPlay,
    session: session ?? this.session,
  );
}

/// Title / artists lookup (the queue only stores ids). Results are kept for a few minutes so that
/// scrolling the queue or switching between mini bar and queue doesn't refetch every row.
final _audioMetaProvider = FutureProvider.autoDispose.family<Audio?, String>((ref, id) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);

  try {
    return await ref.read(audioControllerProvider).get(audioId: id);
  } catch (_) {
    link.close(); // don't keep failures around
    rethrow;
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class AudioPlayerService {
  AudioPlayerService._();

  static final ValueNotifier<AudioQueueState> _state = ValueNotifier(const AudioQueueState())..addListener(_persistIfChanged);
  static final ValueNotifier<bool> _queueVisible = ValueNotifier(false);
  static OverlayEntry? _entry;

  // What was last written to storage (so that only real queue changes are saved).
  static List<String>? _persistedIds;
  static int? _persistedIndex;

  /// Listen to this from the UI (e.g. highlight the playing track, show a queue
  /// page): `ValueListenableBuilder(valueListenable: AudioPlayerService.queue, ...)`.
  static ValueListenable<AudioQueueState> get queue => _state;

  /// Whether the queue panel is open inside the full-screen player.
  static ValueListenable<bool> get queueVisible => _queueVisible;

  // ── Playing ────────────────────────────────────────────────────────────────

  /// Replaces the queue with [audioId] or [audioIds] and starts playing
  /// [startIndex]. It starts in the mini bar; pass [expand] to open the
  /// full-screen player right away. If the track that would play is already the
  /// current one and is playing, it keeps playing (no reload).
  static void play({String? audioId, List<String>? audioIds, int startIndex = 0, bool expand = false}) {
    final ids = _normalize(audioId, audioIds);
    if (ids.isEmpty) return;

    final index = math.min(math.max(startIndex, 0), ids.length - 1);
    final previous = _state.value;
    // A restored track that was never started doesn't count: playing it must reload it with autoplay.
    final sameTrack = !previous.isEmpty && previous.currentId == ids[index] && previous.autoPlay;

    _state.value = AudioQueueState(
      ids: ids,
      index: index,
      minimized: expand ? false : (sameTrack ? previous.minimized : true),
      autoPlay: true,
      session: sameTrack ? previous.session : previous.session + 1,
    );
    _ensureDock();
  }

  static void skipTo(int index) {
    final s = _state.value;
    if (s.isEmpty || index < 0 || index >= s.ids.length || index == s.index) return;
    _state.value = s.copyWith(index: index, autoPlay: true);
  }

  /// No-op on the last track. Also what the player calls when a track finishes.
  static void next() {
    final s = _state.value;
    if (s.hasNext) _state.value = s.copyWith(index: s.index + 1, autoPlay: true);
  }

  static void previous() {
    final s = _state.value;
    if (s.hasPrevious) _state.value = s.copyWith(index: s.index - 1, autoPlay: true);
  }

  // ── Editing the queue ──────────────────────────────────────────────────────

  /// Adds [audioId] / [audioIds] (e.g. a whole playlist) to the end of the queue and, by default,
  /// plays the added track right away (the first of [audioIds]). Unlike [play] the rest of the
  /// queue is kept.
  ///
  ///  - ids that are already queued are not duplicated; if the one to play is already queued the
  ///    player jumps to it
  ///  - [play] = false: only append, the current track is never interrupted
  ///  - [expand] opens the full-screen player (otherwise the mini bar / current state is kept)
  ///  - with an empty queue it behaves like [AudioPlayerService.play]
  static void add({String? audioId, List<String>? audioIds, bool play = true, bool expand = false}) {
    final incoming = _normalize(audioId, audioIds);
    if (incoming.isEmpty) return;

    final s = _state.value;
    if (s.isEmpty) {
      if (play) {
        AudioPlayerService.play(audioIds: incoming, expand: expand);
      } else {
        // Nothing to keep playing: queue it, but don't start it.
        _state.value = AudioQueueState(ids: incoming, minimized: true, autoPlay: false);
        _ensureDock();
      }
      return;
    }

    final fresh = incoming.where((id) => !s.ids.contains(id)).toList();
    final ids = fresh.isEmpty ? s.ids : [...s.ids, ...fresh];

    if (!play) {
      if (fresh.isNotEmpty) _state.value = s.copyWith(ids: ids);
      return;
    }

    final target = incoming.first;
    // Already playing it: keep it going. A restored, never-started track is reloaded with autoplay.
    final sameTrack = s.currentId == target && s.autoPlay;

    _state.value = s.copyWith(
      ids: ids,
      index: ids.indexOf(target),
      autoPlay: true,
      minimized: expand ? false : s.minimized,
      session: sameTrack ? s.session : s.session + 1,
    );
  }

  /// Inserts [audioId] / [audioIds] right after the current track, in the given order.
  /// Ids that were already queued are moved there. Starts playing if nothing is queued yet.
  static void playNext({String? audioId, List<String>? audioIds}) {
    final incoming = _normalize(audioId, audioIds);
    if (incoming.isEmpty) return;

    final s = _state.value;
    if (s.isEmpty) {
      play(audioIds: incoming);
      return;
    }

    final current = s.currentId!;
    final fresh = incoming.where((id) => id != current).toList();
    if (fresh.isEmpty) return;

    final ids = s.ids.where((id) => !fresh.contains(id)).toList();
    ids.insertAll(ids.indexOf(current) + 1, fresh);

    _state.value = s.copyWith(ids: ids, index: ids.indexOf(current));
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

    _state.value = s.copyWith(ids: ids, index: index, autoPlay: removedAt == s.index ? true : s.autoPlay);
  }

  /// Moves the track at [oldIndex] so that it ends up at [newIndex] (its final position in the list).
  /// The current track keeps playing wherever it ends up.
  static void move(int oldIndex, int newIndex) {
    final s = _state.value;
    if (oldIndex < 0 || oldIndex >= s.ids.length) return;

    final target = math.min(math.max(newIndex, 0), s.ids.length - 1);
    if (target == oldIndex) return;

    final current = s.currentId!;
    final ids = [...s.ids];
    ids.insert(target, ids.removeAt(oldIndex));

    _state.value = s.copyWith(ids: ids, index: ids.indexOf(current));
  }

  // ── Window state ───────────────────────────────────────────────────────────

  static void setMinimized(bool minimized) {
    final s = _state.value;
    if (s.isEmpty || s.minimized == minimized) return;
    if (minimized) _queueVisible.value = false;
    _state.value = s.copyWith(minimized: minimized);
  }

  static void toggleMinimized() => setMinimized(!_state.value.minimized);

  /// Opens / closes the queue panel (opening also expands the player).
  static void setQueueVisible(bool visible) {
    if (_state.value.isEmpty) return;
    if (visible) setMinimized(false);
    _queueVisible.value = visible;
  }

  static void toggleQueueVisible() => setQueueVisible(!_queueVisible.value);

  /// Clears the queue, disposes the player, hides the dock and wipes the saved queue.
  static void close() {
    _queueVisible.value = false;
    _state.value = const AudioQueueState();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Brings back the queue of the last session: the mini bar appears with the last track, paused
  /// (it never starts playing by itself). Does nothing if there is no saved queue or something is
  /// already queued. Call it once the user is signed in.
  static Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(_kQueueIdsKey) ?? const <String>[]).toSet().toList();
      if (ids.isEmpty || !_state.value.isEmpty) return;

      final index = math.min(math.max(prefs.getInt(_kQueueIndexKey) ?? 0, 0), ids.length - 1);

      _persistedIds = ids; // already on disk, no need to write it back
      _persistedIndex = index;
      _state.value = AudioQueueState(ids: ids, index: index, minimized: true, autoPlay: false);
      _ensureDock();
    } catch (e) {
      debugPrint('AudioPlayerService.restore failed: $e');
    }
  }

  static void _persistIfChanged() {
    final s = _state.value;
    if (listEquals(s.ids, _persistedIds) && s.index == _persistedIndex) return;

    _persistedIds = s.ids;
    _persistedIndex = s.index;
    _save(s.ids, s.index);
  }

  static Future<void> _save(List<String> ids, int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (ids.isEmpty) {
        await prefs.remove(_kQueueIdsKey);
        await prefs.remove(_kQueueIndexKey);
      } else {
        await prefs.setStringList(_kQueueIdsKey, ids);
        await prefs.setInt(_kQueueIndexKey, index);
      }
    } catch (e) {
      debugPrint('AudioPlayerService: saving the queue failed: $e');
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static List<String> _normalize(String? audioId, List<String>? audioIds) {
    assert((audioId == null) != (audioIds == null), 'Pass either audioId or audioIds');
    // A set literal keeps insertion order and drops duplicates.
    return <String>{if (audioId != null) audioId, ...?audioIds}.where((id) => id.isNotEmpty).toList();
  }

  static void _ensureDock([int attempt = 0]) {
    if (_entry != null && _entry!.mounted) return;

    final overlay = rootNavigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Called before the root navigator exists (app start): retry on the next frames.
      if (attempt < 120) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!_state.value.isEmpty) _ensureDock(attempt + 1);
        });
        SchedulerBinding.instance.scheduleFrame();
      }
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
      key: ValueKey('${state.currentId}#${state.session}'),
      overrides: [audioPlayerCommandsProvider],
      child: _DockBody(state: state),
    );

    // Android back button / gesture: close the queue panel, then minimize the player,
    // instead of popping the page behind it.
    if (Router.maybeOf(context) != null) {
      dock = BackButtonListener(
        onBackButtonPressed: () async {
          if (AudioPlayerService.queueVisible.value) {
            AudioPlayerService.setQueueVisible(false);
            return true;
          }
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

    return ValueListenableBuilder<bool>(
      valueListenable: AudioPlayerService.queueVisible,
      builder: (context, queueOpen, _) {
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
                            key: ValueKey('$audioId#${state.session}'),
                            audioId: audioId,
                            height: double.infinity,
                            borderRadius: BorderRadius.zero,
                            ownPlayerScope: false, // the dock's ProviderScope is shared with the mini bar
                            autoPlay: state.autoPlay,
                            onCompleted: AudioPlayerService.next,
                            // Keep the controls clear of the status bar, the top-right buttons and the nav bar.
                            contentPadding: EdgeInsets.only(top: insets.top + kPlayerTopBarHeight, bottom: insets.bottom),
                            showQueueControls: state.ids.length > 1,
                            onPrevious: state.hasPrevious ? AudioPlayerService.previous : null,
                            onNext: state.hasNext ? AudioPlayerService.next : null,
                            // Shown next to the playback speed button.
                            extraActions: [
                              IconButton(
                                tooltip: 'Queue',
                                visualDensity: VisualDensity.compact,
                                isSelected: queueOpen,
                                icon: const Icon(Icons.queue_music_outlined),
                                selectedIcon: const Icon(Icons.queue_music),
                                style: IconButton.styleFrom(
                                  foregroundColor: queueOpen ? theme.colorScheme.onPrimaryContainer : null,
                                  backgroundColor: queueOpen ? theme.colorScheme.primaryContainer : null,
                                ),
                                onPressed: AudioPlayerService.toggleQueueVisible,
                              ),
                            ],
                          ),
                        ),

                        // Queue panel: slides up over the player (below the top bar).
                        Positioned.fill(
                          top: insets.top + kPlayerTopBarHeight,
                          child: IgnorePointer(
                            ignoring: !queueOpen,
                            child: ExcludeSemantics(
                              excluding: !queueOpen,
                              child: AnimatedSlide(
                                offset: queueOpen ? Offset.zero : const Offset(0, 1),
                                duration: _kDockAnimation,
                                curve: _kDockCurve,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(8, 0, 8, insets.bottom + 8),
                                  child: Align(
                                    alignment: Alignment.topCenter,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: kQueuePanelMaxWidth),
                                      child: _QueuePanel(state: state),
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Queue panel
// ─────────────────────────────────────────────────────────────────────────────

class _QueuePanel extends StatelessWidget {
  const _QueuePanel({required this.state});

  final AudioQueueState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ids = state.ids;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(
              children: [
                Expanded(child: Text('Queue · ${ids.length}', style: theme.textTheme.titleMedium)),
                SaveAsPlaylistButton(tooltip: 'Save the queue as a playlist', audioIds: () => List<String>.of(AudioPlayerService.queue.value.ids)),
                IconButton(tooltip: 'Close queue', icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => AudioPlayerService.setQueueVisible(false)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ReorderableListView.builder(
              primary: false,
              // Our own handles (below) so that dragging works the same on every platform.
              buildDefaultDragHandles: false,
              itemCount: ids.length,
              onReorder: (oldIndex, newIndex) {
                // ReorderableListView reports newIndex as if the item was still in the list.
                if (newIndex > oldIndex) newIndex -= 1;
                AudioPlayerService.move(oldIndex, newIndex);
              },
              itemBuilder: (context, i) => _QueueTile(key: ValueKey(ids[i]), audioId: ids[i], index: i, isCurrent: i == state.index),
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({super.key, required this.audioId, required this.index, required this.isCurrent});

  final String audioId;
  final int index;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final meta = ref.watch(_audioMetaProvider(audioId));
    final audio = meta.value;

    final title = audio?.title ?? (meta.hasError ? 'Unavailable audio' : '…');
    // an audio's artists are resolved from its links, not read from its tags
    final artists = artistsLabel(ref.watch(audioArtistsProvider(audioId)).value);

    return ListTile(
      selected: isCurrent,
      onTap: () => AudioPlayerService.skipTo(index),
      leading: SizedBox(
        width: 28,
        child: Center(child: isCurrent ? const Icon(Icons.equalizer) : Text('${index + 1}', style: theme.textTheme.bodyMedium)),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: artists == null || artists.isEmpty ? null : Text(artists, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Remove from queue',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close),
            onPressed: () => AudioPlayerService.remove(audioId),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.drag_handle)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini bar
// ─────────────────────────────────────────────────────────────────────────────

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
      artistsLabel(ref.watch(audioArtistsProvider(state.currentId!)).value),
      albumsLabel(ref.watch(audioAlbumsProvider(state.currentId!)).value),
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

            return Stack(
              // the seek handle may stick out above the bar
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The line (and the seek handle) is drawn by the seek bar on top of this spacer.
                    const SizedBox(height: kDockProgressHeight),
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
                ),
                // Tap or drag along the top edge of the bar to seek.
                Positioned(left: 0, right: 0, top: 0, height: kDockSeekHeight, child: _DockSeekBar(player: player)),
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

// ---------------------------------------------------------------------------
// Seek bar on the top edge of the minimized dock
// ---------------------------------------------------------------------------

/// The progress line along the top edge of the mini bar. It always shows the position; tap it or drag along it
/// to seek without expanding the player. The handle is small and grows (with the line) while the mouse is over
/// the bar (web / desktop) or while it is dragged (touch).
class _DockSeekBar extends ConsumerStatefulWidget {
  const _DockSeekBar({required this.player});

  final AudioPlayerState player;

  @override
  ConsumerState<_DockSeekBar> createState() => _DockSeekBarState();
}

class _DockSeekBarState extends ConsumerState<_DockSeekBar> {
  /// 0..1 while the user drags (the bar follows the pointer before the player catches up).
  double? _drag;
  bool _hover = false;

  double _fractionAt(double dx, double width) => width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);

  void _seek(double fraction) {
    final duration = widget.player.duration;
    if (duration == Duration.zero) return; // nothing loaded yet
    ref.read(audioPlayerCommandsProvider.notifier).seek(Duration(milliseconds: (fraction * duration.inMilliseconds).round()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final player = widget.player;
    final progress = _drag ?? player.progress;

    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Semantics(
            slider: true,
            label: 'Seek',
            value: '${(progress * 100).round()}%',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _seek(_fractionAt(d.localPosition.dx, width)),
              onHorizontalDragStart: (d) => setState(() => _drag = _fractionAt(d.localPosition.dx, width)),
              onHorizontalDragUpdate: (d) => setState(() => _drag = _fractionAt(d.localPosition.dx, width)),
              onHorizontalDragEnd: (_) {
                final fraction = _drag;
                setState(() => _drag = null);
                if (fraction != null) _seek(fraction);
              },
              onHorizontalDragCancel: () => setState(() => _drag = null),
              child: CustomPaint(
                size: Size(width, kDockSeekHeight),
                painter: _DockSeekPainter(
                  progress: progress,
                  buffered: player.bufferedProgress,
                  active: _hover || _drag != null,
                  playedColor: theme.colorScheme.primary,
                  bufferedColor: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                  trackColor: theme.colorScheme.onSurface.withValues(alpha: 0.12),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DockSeekPainter extends CustomPainter {
  const _DockSeekPainter({
    required this.progress,
    required this.buffered,
    required this.active,
    required this.playedColor,
    required this.bufferedColor,
    required this.trackColor,
  });

  final double progress;
  final double buffered;

  /// Hovered or dragged: a thicker line and a bigger handle.
  final bool active;
  final Color playedColor;
  final Color bufferedColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final lineHeight = active ? kDockProgressHeight * 2 : kDockProgressHeight;
    final played = size.width * progress.clamp(0.0, 1.0);

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, lineHeight), Paint()..color = trackColor);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width * buffered.clamp(0.0, 1.0), lineHeight), Paint()..color = bufferedColor);
    canvas.drawRect(Rect.fromLTWH(0, 0, played, lineHeight), Paint()..color = playedColor);

    final radius = active ? 7.0 : 3.5;
    final x = size.width <= radius * 2 ? played : played.clamp(radius, size.width - radius);
    canvas.drawCircle(Offset(x, lineHeight / 2), radius, Paint()..color = playedColor);
  }

  @override
  bool shouldRepaint(_DockSeekPainter old) =>
      old.progress != progress || old.buffered != buffered || old.active != active || old.playedColor != playedColor || old.bufferedColor != bufferedColor || old.trackColor != trackColor;
}
