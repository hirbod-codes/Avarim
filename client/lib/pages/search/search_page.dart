// Search page with:
//   - a search box (auto-searches after the user stops typing for [kSearchDebounce])
//   - four tabs: Artists / Albums / Audios / Playlists (the active tab decides which endpoint is searched)
//   - paginated results (infinite scroll OR a "Load more" button, see [LoadMoreMode])
//   - initial load with no query -> fetches the selected tab's endpoint without `search`
//   - tapping an audio plays it in the global player dock (see audio_player_service.dart)
//   - albums and playlists have an "add to queue" button (appends all their audios, the current track keeps
//     playing); tapping a playlist adds all its audios to the queue and starts with the first of them
//   - EDIT MODE (audios tab): the pencil in the app bar toggles per-audio buttons
//       edit   -> pushes EditAudioPage with `?audioId=...` (the list refreshes when you come back)
//       delete -> DELETE /api/audio/:audioId, the button turns into a spinner while it runs
//
// pubspec.yaml:
//   flutter_riverpod: ^3.0.0   (plain Notifier API, no code-gen needed)
//   dio: ^5.4.0
//   go_router
//
// Everything is in one file for easy copy/paste; split it into
// models / api / controller / page files when you customize it.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/auth/token_storage.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

/// How long to wait after the last keystroke before searching.
const kSearchDebounce = Duration(seconds: 2);

const kPageSize = 20;

/// First page number your API expects (change to 0 if it is zero-based).
const kFirstPage = 1;

/// Page size used when fetching ALL the audios of an album / playlist to put them in the player queue.
const kQueueFetchPageSize = 50;

/// Ask "Delete this audio?" before actually deleting. Set to false to delete on the first press.
const kConfirmBeforeDelete = true;

const kEditArtistRoute = '/artist/edit';
const kEditAlbumRoute = '/album/edit';
const kEditAudioRoute = '/audio/edit';

enum SearchTab {
  artists('Artists', '/api/artist'),
  albums('Albums', '/api/album'),
  audios('Audios', '/api/audio'),
  playlists('Playlists', '/api/playlist');

  const SearchTab(this.label, this.path);
  final String label;
  final String path;
}

enum LoadMoreMode {
  /// Automatically loads the next page when the list is scrolled near the end.
  infiniteScroll,

  /// Shows a "Load more" button at the end of the list.
  button,
}

// ─────────────────────────────────────────────────────────────────────────────
// API (assumed endpoints - customize)
//
//   GET    {baseUrl}/artists?page=1&pageSize=20&search=foo
//   GET    {baseUrl}/albums?page=1&pageSize=20&search=foo
//   GET    {baseUrl}/audios?page=1&pageSize=20&search=foo
//   GET    {baseUrl}/playlists?page=1&pageSize=20&search=foo
//   DELETE {baseUrl}/api/audio/:audioId
//
// To queue an album / playlist, all of its audios are fetched page by page:
//   GET    {baseUrl}/api/album/audio?albumName=...&page=1&pageSize=50
//   GET    {baseUrl}/api/playlist/audio?playlistId=...&page=1&pageSize=50
//
// Response: { "items": [ {...}, {...} ] }   (a bare JSON array also works)
// ─────────────────────────────────────────────────────────────────────────────

class MusicSearchApi {
  MusicSearchApi(this._dio);
  final Dio _dio;

  Future<List<WithId>> search(SearchTab tab, {required String query, required int page, required int pageSize, CancelToken? cancelToken}) async {
    final res = await apiCall<List<WithId>>(
      () => _dio.get<dynamic>(
        tab.path,
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          // Omitted when empty so the initial load is a plain "list" request.
          if (query.isNotEmpty) 'search': query,
        },
        cancelToken: cancelToken,
      ),
      fromJson: (data) {
        return List.from(data).map<WithId>((e) {
          switch (tab) {
            case SearchTab.artists:
              return Artist.fromJson(e);
            case SearchTab.albums:
              return Album.fromJson(e);
            case SearchTab.audios:
              return Audio.fromJson(e);
            case SearchTab.playlists:
              return Playlist.fromJson(e);
          }
        }).toList();
      },
    );

    if (res.isFailure || res.dataOrNull == null) {
      NotificationService.showError(message: 'Nothing found');
      return [];
    }

    return res.dataOrNull ?? [];
  }

  /// Deletes an audio. Returns true on success.
  Future<bool> deleteAudio(String audioId) async {
    final res = await apiCall(() => _dio.delete<dynamic>('/api/audio/$audioId'));
    return res.isSuccess;
  }

  /// Ids of every audio of the album called [albumName], in order. Null when a request failed
  /// (its error was already shown).
  Future<List<String>?> albumAudioIds(String albumName) => _allAudioIds('/api/album/audio', {'albumName': albumName});

  /// Ids of every audio of a playlist, in playlist order. Null when a request failed
  /// (its error was already shown).
  Future<List<String>?> playlistAudioIds(String playlistId) => _allAudioIds('/api/playlist/audio', {'playlistId': playlistId});

  /// Pages through [path] until the last page. Both endpoints answer `{ status, data: [audio, ...] }`
  /// (page is 1-based, like the lists above).
  Future<List<String>?> _allAudioIds(String path, Map<String, dynamic> params) async {
    final ids = <String>{}; // a set: keeps the order, drops duplicates
    for (var page = kFirstPage; ; page++) {
      final res = await apiCall<List<String>>(
        () => _dio.get<dynamic>(path, queryParameters: {...params, 'page': page, 'pageSize': kQueueFetchPageSize}),
        fromJson: (data) => List.from(data).map(_audioIdOf).whereType<String>().toList(),
      );
      if (res.isFailure) return null;

      final pageIds = res.dataOrNull ?? const <String>[];
      final before = ids.length;
      ids.addAll(pageIds);

      // A short page is the last one. No NEW ids means the server ignored `page`: stop instead of looping forever.
      if (pageIds.length < kQueueFetchPageSize || ids.length == before) return ids.toList();
    }
  }

  /// An audio's id: `_id` (audio documents) or `audioId` (playlist / album link records).
  static String? _audioIdOf(dynamic e) {
    if (e is! Map) return null;
    final id = e['_id'] ?? e['audioId'];
    return id?.toString();
  }
}

final musicSearchApiProvider = Provider<MusicSearchApi>((ref) => MusicSearchApi(ref.watch(authDioProvider)));

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class TabResults {
  const TabResults({
    this.items = const [],
    this.page = 0,
    this.hasMore = true,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.loadedQuery,
  });

  final List<WithId> items;

  /// Last page that was loaded successfully.
  final int page;
  final bool hasMore;

  /// Loading the first page (or refreshing).
  final bool isLoading;

  /// Loading page + 1.
  final bool isLoadingMore;
  final Object? error;

  /// The query these results belong to (null = this tab was never loaded).
  final String? loadedQuery;

  TabResults copyWith({
    List<WithId>? items,
    int? page,
    bool? hasMore,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error,
    bool clearError = false,
    String? loadedQuery,
  }) => TabResults(
    items: items ?? this.items,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: clearError ? null : (error ?? this.error),
    loadedQuery: loadedQuery ?? this.loadedQuery,
  );
}

class SearchState {
  const SearchState({
    required this.tab,
    required this.query,
    required this.results,
    this.editMode = false,
    this.deletingIds = const {},
    this.queueingIds = const {},
  });

  final SearchTab tab;
  final String query;
  final Map<SearchTab, TabResults> results;

  /// Shows edit / delete buttons on audios.
  final bool editMode;

  /// Audios whose delete request is in flight (their delete button shows a spinner).
  final Set<String> deletingIds;

  /// Albums / playlists whose audios are being fetched to be queued (their queue button shows a spinner).
  final Set<String> queueingIds;

  TabResults of(SearchTab t) => results[t]!;

  SearchState copyWith({
    SearchTab? tab,
    String? query,
    Map<SearchTab, TabResults>? results,
    bool? editMode,
    Set<String>? deletingIds,
    Set<String>? queueingIds,
  }) => SearchState(
    tab: tab ?? this.tab,
    query: query ?? this.query,
    results: results ?? this.results,
    editMode: editMode ?? this.editMode,
    deletingIds: deletingIds ?? this.deletingIds,
    queueingIds: queueingIds ?? this.queueingIds,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class MusicSearchNotifier extends Notifier<SearchState> {
  Timer? _debounce;
  String _pendingQuery = '';
  final Map<SearchTab, CancelToken> _tokens = {};

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounce?.cancel();
      for (final token in _tokens.values) {
        token.cancel();
      }
    });

    _pendingQuery = '';

    // Initial load: no query, selected (first) tab.
    Future.microtask(_syncActiveTab);

    return SearchState(tab: SearchTab.artists, query: '', results: {for (final t in SearchTab.values) t: const TabResults()});
  }

  /// Called on every keystroke; searches after [kSearchDebounce] of silence.
  void onQueryChanged(String text) {
    _pendingQuery = text.trim();
    _debounce?.cancel();
    _debounce = Timer(kSearchDebounce, _commitQuery);
  }

  /// Search immediately (keyboard "search" action / clear button).
  void submit(String text) {
    _pendingQuery = text.trim();
    _commitQuery();
  }

  void setTab(SearchTab tab) {
    if (tab != state.tab) state = state.copyWith(tab: tab);
    // Also flushes a pending (debounced) query so the new tab loads once, with it.
    _commitQuery();
  }

  /// Pull-to-refresh / retry for a tab: reloads page 1, keeping old items visible.
  Future<void> refresh(SearchTab tab) => _load(tab, reset: true, keepItems: true);

  /// Loads page + 1 for [tab]. No-op if already loading, no more data, or
  /// the last attempt failed (unless [retry] is true).
  Future<void> loadMore(SearchTab tab, {bool retry = false}) => _load(tab, reset: false, retry: retry);

  void toggleEditMode() => state = state.copyWith(editMode: !state.editMode);

  /// Adds every audio of an album or a playlist to the player queue (see AudioPlayerService.add):
  ///  - [play] = true: the first of them starts playing right away, the rest of the queue is kept
  ///  - [play] = false: they are only appended, the current track keeps playing
  /// While the audios are fetched the item's id is in [SearchState.queueingIds] (its button spins).
  Future<void> addToQueue(WithId item, {required bool play}) async {
    if (state.queueingIds.contains(item.id)) return;
    state = state.copyWith(queueingIds: {...state.queueingIds, item.id});

    List<String>? ids;
    try {
      final api = ref.read(musicSearchApiProvider);
      ids = switch (item) {
        Album a => await api.albumAudioIds(a.name),
        Playlist p => await api.playlistAudioIds(p.id),
        _ => const <String>[],
      };
    } catch (e, st) {
      talker.error('fetching the audios to queue failed', e, st);
    }

    // ids == null: a request failed and its error was already shown.
    if (ids != null) {
      if (ids.isEmpty) {
        NotificationService.showError(message: 'There are no audios to add');
      } else {
        // The player is global, so this works even if the user already left the page.
        AudioPlayerService.add(audioIds: ids, play: play);
        if (!play) {
          NotificationService.showSuccess(message: ids.length == 1 ? 'Added 1 audio to the queue' : 'Added ${ids.length} audios to the queue');
        }
      }
    }

    if (ref.mounted) state = state.copyWith(queueingIds: {...state.queueingIds}..remove(item.id));
  }

  /// Deletes an audio. While the request runs its id is in [SearchState.deletingIds];
  /// on success it disappears from every tab (and from the floating player if it was playing).
  Future<void> deleteAudio(String id) async {
    if (state.deletingIds.contains(id)) return;
    state = state.copyWith(deletingIds: {...state.deletingIds, id});

    var deleted = false;
    try {
      deleted = await ref.read(musicSearchApiProvider).deleteAudio(id);
    } catch (e, st) {
      talker.error('deleting audio failed', e, st);
    }
    if (!ref.mounted) return;

    final deleting = {...state.deletingIds}..remove(id);

    if (!deleted) {
      state = state.copyWith(deletingIds: deleting);
      NotificationService.showError(message: 'Could not delete the audio');
      return;
    }

    state = state.copyWith(
      deletingIds: deleting,
      results: {for (final e in state.results.entries) e.key: e.value.copyWith(items: e.value.items.where((item) => item.id != id).toList())},
    );

    // Drops it from the player queue (no-op if it isn't queued; closes the dock if it was the last track).
    AudioPlayerService.remove(id);
  }

  // ── internals ──────────────────────────────────────────────────────────────

  void _commitQuery() {
    _debounce?.cancel();
    if (_pendingQuery != state.query) {
      state = state.copyWith(query: _pendingQuery);
    }
    _syncActiveTab();
  }

  /// Makes sure the active tab holds results for the current query.
  void _syncActiveTab() {
    if (!ref.mounted) return;
    final tab = state.tab;
    if (state.of(tab).loadedQuery != state.query) {
      unawaited(_load(tab, reset: true));
    }
  }

  void _put(SearchTab tab, TabResults results) {
    if (!ref.mounted) return;
    state = state.copyWith(results: {...state.results, tab: results});
  }

  Future<void> _load(SearchTab tab, {required bool reset, bool keepItems = false, bool retry = false}) async {
    final current = state.of(tab);

    if (!reset) {
      if (current.isLoading || current.isLoadingMore || !current.hasMore) return;
      if (current.error != null && !retry) return;
    }

    // A new request for this tab supersedes any in-flight one.
    _tokens[tab]?.cancel();
    final token = _tokens[tab] = CancelToken();

    final query = state.query;
    final page = reset ? kFirstPage : current.page + 1;

    _put(
      tab,
      reset
          ? (keepItems ? current.copyWith(isLoading: true, clearError: true, loadedQuery: query) : TabResults(isLoading: true, loadedQuery: query))
          : current.copyWith(isLoadingMore: true, clearError: true),
    );

    try {
      final fetched = await ref.read(musicSearchApiProvider).search(tab, query: query, page: page, pageSize: kPageSize, cancelToken: token);
      if (!ref.mounted || token.isCancelled) return;

      _put(
        tab,
        TabResults(
          items: reset ? fetched : [...state.of(tab).items, ...fetched],
          page: page,
          // Hide "load more" once the server returns an empty array.
          // (Use `fetched.length >= kPageSize` to also skip the last empty request.)
          hasMore: fetched.isNotEmpty,
          loadedQuery: query,
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || !ref.mounted) return;
      _fail(tab, e);
    } catch (e) {
      if (!ref.mounted) return;
      _fail(tab, e);
    }
  }

  void _fail(SearchTab tab, Object error) {
    _put(tab, state.of(tab).copyWith(isLoading: false, isLoadingMore: false, error: error));
  }
}

/// autoDispose: leaving the page resets query, tab and results.
final musicSearchProvider = NotifierProvider.autoDispose<MusicSearchNotifier, SearchState>(MusicSearchNotifier.new);

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.loadMoreMode = LoadMoreMode.infiniteScroll, this.onItemTap});

  final LoadMoreMode loadMoreMode;

  /// Called for every tapped result. (Audios additionally open the floating player.)
  final ValueChanged<WithId>? onItemTap;

  @override
  ConsumerState<SearchPage> createState() => _MusicSearchPageState();
}

class _MusicSearchPageState extends ConsumerState<SearchPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: SearchTab.values.length, vsync: this);
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      ref.read(musicSearchProvider.notifier).setTab(SearchTab.values[_tabs.index]);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(musicSearchProvider.select((s) => s.tab));
    final editMode = ref.watch(musicSearchProvider.select((s) => s.editMode));
    final notifier = ref.read(musicSearchProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _text,
          textInputAction: TextInputAction.search,
          onChanged: notifier.onQueryChanged,
          onSubmitted: notifier.submit,
          decoration: InputDecoration(
            hintText: 'Search ${tab.label.toLowerCase()}',
            isDense: true,
            filled: true,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _text,
              builder: (context, value, child) => value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _text.clear();
                        notifier.submit('');
                      },
                    ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          IconButton(
            tooltip: editMode ? 'Done' : 'Edit mode',
            isSelected: editMode,
            icon: const Icon(Icons.edit_outlined),
            selectedIcon: const Icon(Icons.check),
            onPressed: notifier.toggleEditMode,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final t in SearchTab.values) Tab(text: t.label)],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [for (final t in SearchTab.values) _ResultsList(tab: t, mode: widget.loadMoreMode, onItemTap: widget.onItemTap)],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results list (one per tab)
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsList extends ConsumerStatefulWidget {
  const _ResultsList({required this.tab, required this.mode, this.onItemTap});

  final SearchTab tab;
  final LoadMoreMode mode;
  final ValueChanged<WithId>? onItemTap;

  @override
  ConsumerState<_ResultsList> createState() => _ResultsListState();
}

class _ResultsListState extends ConsumerState<_ResultsList> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();

  // Keeps scroll position when switching tabs.
  @override
  bool get wantKeepAlive => true;

  bool get _auto => widget.mode == LoadMoreMode.infiniteScroll;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _loadMore({bool retry = false}) {
    unawaited(ref.read(musicSearchProvider.notifier).loadMore(widget.tab, retry: retry));
  }

  void _onScroll() {
    if (_auto && _scroll.position.extentAfter < 300) _loadMore();
  }

  /// If the first page doesn't fill the screen there is nothing to scroll,
  /// so keep loading pages until it does (or the server runs out).
  void _fillViewportIfNeeded() {
    if (!mounted || !_auto || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent <= 0) _loadMore();
  }

  void _onTap(WithId item) {
    widget.onItemTap?.call(item);

    if (item is Audio) {
      AudioPlayerService.add(audioId: item.id);
    } else if (item is Playlist) {
      // All of the playlist's audios go into the queue and the first of them starts playing.
      unawaited(ref.read(musicSearchProvider.notifier).addToQueue(item, play: true));
    }
  }

  /// Opens EditAudioPage for [audio]; refreshes the audios when the user comes back.
  Future<void> _edit(WithId item) async {
    if (item is Audio) {
      final location = Uri(path: kEditAudioRoute, queryParameters: {'audioId': item.id}).toString();
      await context.push(location);

      if (!mounted) return;
      unawaited(ref.read(musicSearchProvider.notifier).refresh(SearchTab.audios));
    }

    if (item is Artist) {
      final location = Uri(path: kEditArtistRoute, queryParameters: {'artistId': item.id}).toString();
      await context.push(location);

      if (!mounted) return;
      unawaited(ref.read(musicSearchProvider.notifier).refresh(SearchTab.artists));
    }

    if (item is Album) {
      final location = Uri(path: kEditAlbumRoute, queryParameters: {'albumId': item.id}).toString();
      await context.push(location);

      if (!mounted) return;
      unawaited(ref.read(musicSearchProvider.notifier).refresh(SearchTab.albums));
    }
  }

  Future<void> _delete(Audio audio) async {
    if (kConfirmBeforeDelete) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete audio?'),
          content: Text('"${audio.title}" will be permanently deleted.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    await ref.read(musicSearchProvider.notifier).deleteAudio(audio.id);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    final r = ref.watch(musicSearchProvider.select((s) => s.of(widget.tab)));
    final notifier = ref.read(musicSearchProvider.notifier);
    final editMode = ref.watch(musicSearchProvider.select((s) => s.editMode));
    final deletingIds = ref.watch(musicSearchProvider.select((s) => s.deletingIds));
    final queueingIds = ref.watch(musicSearchProvider.select((s) => s.queueingIds));

    if (r.items.isEmpty && (r.isLoading || r.loadedQuery == null)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (r.items.isEmpty && r.error != null) {
      return _Message(icon: Icons.error_outline, text: 'Something went wrong', actionLabel: 'Retry', onAction: () => notifier.refresh(widget.tab));
    }
    if (r.items.isEmpty) {
      return const _Message(icon: Icons.search_off, text: 'No results');
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewportIfNeeded());

    final showFooter = r.isLoadingMore || r.error != null || (r.hasMore && !_auto);

    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, queue, _) {
        final playingId = queue.currentId;
        // Keep the last item reachable above the player dock.
        final bottomPadding = queue.isEmpty ? 0.0 : kDockCollapsedExtent + MediaQuery.paddingOf(context).bottom;

        return RefreshIndicator(
          onRefresh: () => notifier.refresh(widget.tab),
          child: ListView.separated(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: bottomPadding),
            itemCount: r.items.length + (showFooter ? 1 : 0),
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i < r.items.length) {
                final item = r.items[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: _ResultTile(
                    item: item,
                    isPlaying: item is Audio && item.id == playingId,
                    editMode: editMode,
                    isDeleting: deletingIds.contains(item.id),
                    isQueueing: queueingIds.contains(item.id),
                    onTap: item is Artist
                        ? () {
                            context.push(Uri(path: '/artist', queryParameters: {'artistId': item.id}).toString());
                          }
                        : ((item is Audio || item is Playlist || widget.onItemTap != null) ? () => _onTap(item) : null),
                    onAddToQueue: item is Album || item is Playlist ? () => notifier.addToQueue(item, play: false) : null,
                    onEdit: () => _edit(item),
                    onDelete: item is Audio ? () => _delete(item) : null,
                  ),
                );
              }
              return _Footer(isLoadingMore: r.isLoadingMore, hasError: r.error != null, onLoadMore: _loadMore, onRetry: () => _loadMore(retry: true));
            },
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.isLoadingMore, required this.hasError, required this.onLoadMore, required this.onRetry});

  final bool isLoadingMore;
  final bool hasError;
  final VoidCallback onLoadMore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (isLoadingMore) {
      child = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (hasError) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load more"),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    } else {
      child = OutlinedButton(onPressed: onLoadMore, child: const Text('Load more'));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(child: child),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.actionLabel, this.onAction});

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(text),
          if (actionLabel != null) ...[const SizedBox(height: 8), FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!))],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tiles
// ─────────────────────────────────────────────────────────────────────────────

String _joinParts(List<String?> parts) => parts.whereType<String>().where((s) => s.isNotEmpty).join(' · ');

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.item,
    this.onTap,
    this.isPlaying = false,
    this.editMode = false,
    this.isDeleting = false,
    this.isQueueing = false,
    this.onEdit,
    this.onDelete,
    this.onAddToQueue,
  });

  final WithId item;
  final VoidCallback? onTap;

  /// True for the audio currently loaded in the floating player.
  final bool isPlaying;

  /// Audios show edit / delete buttons instead of the duration.
  final bool editMode;

  /// This audio's delete request is in flight.
  final bool isDeleting;

  /// This album's / playlist's audios are being fetched to be queued.
  final bool isQueueing;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  /// Albums and playlists: appends all their audios to the player queue.
  final VoidCallback? onAddToQueue;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      Artist a => ListTile(
        onTap: onTap,
        leading: Thumb(url: '/api/artist/avatar/${a.id}', icon: Icons.person, circular: true),
        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: editMode ? _editActions(context) : null,
      ),
      Album a => ListTile(
        onTap: onTap,
        leading: Thumb(url: '/api/album/avatar/${a.id}', icon: Icons.album),
        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: _subtitle([a.name]),
        trailing: editMode ? _editActions(context) : _queueButton(),
      ),
      Audio a => ListTile(
        onTap: isDeleting ? null : onTap,
        selected: isPlaying,
        leading: Thumb(url: '/api/audio/coverArt/${a.id}', icon: Icons.music_note),
        title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: _subtitle([a.tags?.artists.join(', '), a.tags?.album]),
        trailing: editMode ? _editActions(context) : (a.technical?.durationSec == null ? null : Text(_formatDuration(a.technical!.durationSec!.round()))),
      ),
      Playlist p => ListTile(
        // Tapping plays it: all its audios are added to the queue and the first one starts.
        onTap: isQueueing ? null : onTap,
        leading: Thumb(url: '/api/playlist/avatar/${p.id}', icon: Icons.queue_music),
        title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: _queueButton(),
      ),
      WithId() => throw UnimplementedError(),
    };
  }

  Widget _editActions(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: isDeleting ? null : onEdit),
        if (isDeleting)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: onDelete,
          ),
      ],
    );
  }

  /// "Add to queue" (spinner while the audios are being fetched).
  Widget? _queueButton() {
    if (onAddToQueue == null) return null;
    if (isQueueing) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return IconButton(tooltip: 'Add to queue', icon: const Icon(Icons.playlist_add), onPressed: onAddToQueue);
  }

  static Widget? _subtitle(List<String?> parts) {
    final text = _joinParts(parts);
    return text.isEmpty ? null : Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class Thumb extends ConsumerStatefulWidget {
  final String? url;
  final IconData icon;
  final bool circular;

  const Thumb({super.key, required this.url, required this.icon, this.circular = false});

  @override
  ConsumerState<Thumb> createState() => _Thumb();
}

class _Thumb extends ConsumerState<Thumb> {
  static const double _size = 48;

  String? _token;
  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _init();
  }

  void _init() async {
    try {
      final s = ref.watch(tokenStorageProvider);
      final token = await s.getAccessToken();
      if (!mounted) return;

      setState(() {
        _token = token;
        _loading = false;
      });
    } catch (e, st) {
      talker.error('caught error while trying to fetch image', e, st);
      if (!mounted) return null;

      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary);
    }

    final placeholder = Container(width: _size, height: _size, color: theme.colorScheme.surfaceContainerHighest, child: Icon(widget.icon));

    final image = widget.url == null
        ? placeholder
        : Image.network(
            widget.url!,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => placeholder,
            headers: {'Authorization': 'Bearer $_token'},
          );

    return ClipRRect(borderRadius: BorderRadius.circular(widget.circular ? _size / 2 : 8), child: image);
  }
}
