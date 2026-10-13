// music_search_page.dart
//
// Search page with:
//   - a search box (auto-searches after the user stops typing for [kSearchDebounce])
//   - three tabs: Artists / Albums / Audios (the active tab decides which endpoint is searched)
//   - paginated results (infinite scroll OR a "Load more" button, see [LoadMoreMode])
//   - initial load with no query -> fetches the selected tab's endpoint without `search`
//   - tapping an audio opens a minimizable floating player (see now_playing_dock.dart)
//
// pubspec.yaml:
//   flutter_riverpod: ^3.0.0   (plain Notifier API, no code-gen needed)
//   dio: ^5.4.0
//
// Everything is in one file for easy copy/paste; split it into
// models / api / controller / page files when you customize it.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/auth/token_storage.dart';
import 'package:avarim/components/contents/now_playing_dock.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

/// How long to wait after the last keystroke before searching.
const kSearchDebounce = Duration(seconds: 2);

const kPageSize = 20;

/// First page number your API expects (change to 0 if it is zero-based).
const kFirstPage = 1;

enum SearchTab {
  artists('Artists', '/api/artist'),
  albums('Albums', '/api/album'),
  audios('Audios', '/api/audio');

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
//   GET {baseUrl}/artists?page=1&pageSize=20&search=foo
//   GET {baseUrl}/albums?page=1&pageSize=20&search=foo
//   GET {baseUrl}/audios?page=1&pageSize=20&search=foo
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
  const SearchState({required this.tab, required this.query, required this.results});

  final SearchTab tab;
  final String query;
  final Map<SearchTab, TabResults> results;

  TabResults of(SearchTab t) => results[t]!;

  SearchState copyWith({SearchTab? tab, String? query, Map<SearchTab, TabResults>? results}) =>
      SearchState(tab: tab ?? this.tab, query: query ?? this.query, results: results ?? this.results);
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
        bottom: TabBar(
          controller: _tabs,
          tabs: [for (final t in SearchTab.values) Tab(text: t.label)],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [for (final t in SearchTab.values) _ResultsList(tab: t, mode: widget.loadMoreMode, onItemTap: widget.onItemTap)],
          ),
          // Floating, minimizable player. Taps outside the panel fall through to the list.
          const Align(alignment: Alignment.bottomCenter, child: NowPlayingDock()),
        ],
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
      ref.read(nowPlayingProvider.notifier).play(audioId: item.id, title: item.title, subtitle: _joinParts([item.tags?.artists.join(', '), item.tags?.album]));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    final r = ref.watch(musicSearchProvider.select((s) => s.of(widget.tab)));
    final notifier = ref.read(musicSearchProvider.notifier);
    final playingId = ref.watch(nowPlayingProvider.select((s) => s?.audioId));

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

    // Keep the last item reachable above the floating player.
    final bottomPadding = playingId == null ? 0.0 : kDockCollapsedExtent + MediaQuery.paddingOf(context).bottom;

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
            return _ResultTile(
              item: item,
              isPlaying: item is Audio && item.id == playingId,
              onTap: (item is Audio || widget.onItemTap != null) ? () => _onTap(item) : null,
            );
          }
          return _Footer(isLoadingMore: r.isLoadingMore, hasError: r.error != null, onLoadMore: _loadMore, onRetry: () => _loadMore(retry: true));
        },
      ),
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
  const _ResultTile({required this.item, this.onTap, this.isPlaying = false});

  final WithId item;
  final VoidCallback? onTap;

  /// True for the audio currently loaded in the floating player.
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      Artist a => ListTile(
        onTap: onTap,
        leading: Thumb(url: '/api/artist/avatar/${a.id}', icon: Icons.person, circular: true),
        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      Album a => ListTile(
        onTap: onTap,
        leading: Thumb(url: '/api/album/avatar/${a.id}', icon: Icons.album),
        title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: _subtitle([a.name]),
      ),
      Audio a => ListTile(
        onTap: onTap,
        selected: isPlaying,
        leading: Thumb(url: '/api/audio/coverArt/${a.id}', icon: Icons.music_note),
        title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: _subtitle([a.tags?.artists.join(', '), a.tags?.album]),
        trailing: a.technical?.durationSec == null ? null : Text(_formatDuration(a.technical!.durationSec!.round())),
      ),
      WithId() => throw UnimplementedError(),
    };
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
