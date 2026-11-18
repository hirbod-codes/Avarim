import 'package:avarim/account/user_info_notifier.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/components/core/core.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/pages/search/edit_mode.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_search_api.dart';
import '../models/search_tab.dart';
import '../music_search_config.dart';
import 'items/items.dart';

/// Search page = a search box, one tab per [SearchTab], and a paginated list of results per tab.
///
///   - the search box searches after the user stops typing, see [kSearchInputDebounceDuration]
///   - the open tab decides which endpoint is searched; a tab loads the first time it is opened
///   - results load page by page: infinite scroll or a "Load more" button, see [LoadMoreMode]
///   - with no query the open tab's endpoint is fetched without `search`
///   - admins get a refresh button and an edit mode (pencil) with edit / delete buttons on the rows
///
/// This page only knows the open tab, the query and the paging of every tab. What a row can do (play, queue,
/// edit, delete) is up to the row widgets in items/.
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.loadMoreMode = LoadMoreMode.infiniteScroll, this.onResultTapped});

  final LoadMoreMode loadMoreMode;

  /// Called for every tapped result. (Audios additionally open the floating player.)
  final ValueChanged<WithId>? onResultTapped;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _searchFieldKey = GlobalKey<DebouncedSearchFieldState>();

  SearchTab _selectedTab = SearchTab.artists;
  String _query = '';

  /// The paging state of every tab. A tab holds results for the current query or nothing at all:
  /// a new query empties every tab, and the open one loads again.
  final _results = {for (final tab in SearchTab.values) tab: PagedState<WithId>()};
  final _cancelTokens = <SearchTab, CancelToken>{};

  MusicSearchApi get _api => ref.read(musicSearchApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _loadFirstPageIfNeeded(_selectedTab));
  }

  @override
  void dispose() {
    for (final cancelToken in _cancelTokens.values) {
      cancelToken.cancel();
    }
    super.dispose();
  }

  // ── Search box and tabs ────────────────────────────────────────────────────

  void _onQueryChanged(String query) {
    for (final cancelToken in _cancelTokens.values) {
      cancelToken.cancel();
    }
    setState(() {
      _query = query;
      for (final tab in SearchTab.values) {
        _results[tab] = PagedState<WithId>();
      }
    });
    _loadFirstPageIfNeeded(_selectedTab);
  }

  void _onTabChanged(SearchTab tab) {
    setState(() => _selectedTab = tab);
    // Applies a pending (debounced) query first, so the new tab loads once, with it.
    _searchFieldKey.currentState?.flush();
    _loadFirstPageIfNeeded(tab);
  }

  // ── Loading results ────────────────────────────────────────────────────────

  Future<void> _loadFirstPageIfNeeded(SearchTab tab) async {
    if (mounted && _results[tab]!.wasNeverRequested) await _loadPage(tab, restart: true);
  }

  /// Pull-to-refresh / retry: reloads page 1, keeping the old items visible meanwhile.
  Future<void> _reload(SearchTab tab) => _loadPage(tab, restart: true, keepItems: true);

  /// No-op if already loading, there is no more data, or the last attempt failed (unless [retryAfterError]).
  Future<void> _loadNextPage(SearchTab tab, {bool retryAfterError = false}) => _loadPage(tab, restart: false, retryAfterError: retryAfterError);

  Future<void> _loadPage(SearchTab tab, {required bool restart, bool keepItems = false, bool retryAfterError = false}) async {
    final current = _results[tab]!;
    if (!restart) {
      final cannotLoadMore = current.lastLoadedPage == null || current.isLoadingFirstPage || current.isLoadingNextPage || !current.hasMore;
      final waitsForRetry = current.hasError && !retryAfterError;
      if (cannotLoadMore || waitsForRetry) return;
    }

    // A new request for this tab supersedes any in-flight one.
    _cancelTokens[tab]?.cancel();
    final cancelToken = _cancelTokens[tab] = CancelToken();
    final pageToLoad = restart ? kFirstPageNumber : current.lastLoadedPage! + 1;

    setState(() {
      if (!restart) {
        _results[tab] = current.copyWith(isLoadingNextPage: true, shouldClearError: true);
      } else if (keepItems) {
        _results[tab] = current.copyWith(isLoadingFirstPage: true, shouldClearError: true);
      } else {
        _results[tab] = PagedState<WithId>(isLoadingFirstPage: true);
      }
    });

    try {
      final fetchedItems = await _api.fetchSearchResultsPage(
        tab,
        query: _query,
        pageNumber: pageToLoad,
        pageSize: kSearchResultsPageSize,
        cancelToken: cancelToken,
      );
      if (!mounted || cancelToken.isCancelled) return;

      setState(() {
        _results[tab] = PagedState<WithId>(
          items: restart ? fetchedItems : [..._results[tab]!.items, ...fetchedItems],
          lastLoadedPage: pageToLoad,
          // Hide "load more" once the server returns an empty array.
          // (Use `fetchedItems.length >= kSearchResultsPageSize` to also skip the last empty request.)
          hasMore: fetchedItems.isNotEmpty,
        );
      });
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) return;
      _markFailed(tab, error);
    } catch (error) {
      _markFailed(tab, error);
    }
  }

  void _markFailed(SearchTab tab, Object error) {
    if (!mounted) return;
    setState(() => _results[tab] = _results[tab]!.copyWith(isLoadingFirstPage: false, isLoadingNextPage: false, error: error));
  }

  /// Drops a deleted item from every tab it may be in.
  void _removeFromAllTabs(String itemId) {
    if (!mounted) return;
    setState(() {
      for (final tab in SearchTab.values) {
        final results = _results[tab]!;
        _results[tab] = results.copyWith(items: results.items.where((item) => item.id != itemId).toList());
      }
    });
  }

  // ── Building ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(userInfoProvider).info?.role == 'admin';

    return TabBarScaffold<SearchTab>(
      tabs: SearchTab.values,
      tabLabel: (tab) => tab.displayLabel,
      onTabChanged: _onTabChanged,
      title: _buildSearchField(),
      actions: isAdmin ? _buildAdminActions() : null,
      pageBuilder: (context, tab) => _buildResultsList(tab),
    );
  }

  Widget _buildSearchField() {
    return DebouncedSearchField(
      key: _searchFieldKey,
      debounce: kSearchInputDebounceDuration,
      hintText: 'Search ${_selectedTab.displayLabel.toLowerCase()}',
      onSearch: _onQueryChanged,
    );
  }

  List<Widget> _buildAdminActions() {
    return [AsyncIconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => _reload(_selectedTab))];
  }

  Widget _buildResultsList(SearchTab tab) {
    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, queue, _) => PagedListView<WithId>(
        state: _results[tab]!,
        loadMoreMode: widget.loadMoreMode,
        bottomPadding: queue.isEmpty ? 0.0 : kDockCollapsedExtent + MediaQuery.paddingOf(context).bottom,
        itemBuilder: (context, item) => _buildRow(item),
        onLoadNext: () => _loadNextPage(tab),
        onRetryNext: () => _loadNextPage(tab, retryAfterError: true),
        onReload: () => _reload(tab),
        emptyBuilder: (context) {
          // With no query, an empty "No artist" tab is good news.
          final everyAudioHasAnArtist = tab == SearchTab.audiosWithoutArtist && _query.isEmpty;
          return StatusMessage(
            icon: everyAudioHasAnArtist ? Icons.check_circle_outline : Icons.search_off,
            message: everyAudioHasAnArtist ? 'Every audio has an artist' : 'No results',
          );
        },
      ),
      // builder(context, queue.isEmpty ? 0.0 : kDockCollapsedExtent + MediaQuery.paddingOf(context).bottom),
    );
  }

  Widget _buildRow(WithId item) {
    void notifyTapped() => widget.onResultTapped?.call(item);
    final isEditModeEnabled = ref.watch(editModeProvider);

    // The key makes a row's own state (spinners) follow its item when the list changes.
    return switch (item) {
      Artist artist => ArtistListItem(
        key: ValueKey(item.id),
        artist: artist,
        isEditMode: isEditModeEnabled,
        onTap: notifyTapped,
        onDeleted: _removeFromAllTabs,
      ),
      Album album => AlbumListItem(key: ValueKey(item.id), album: album, isEditMode: isEditModeEnabled, onTap: notifyTapped, onDeleted: _removeFromAllTabs),
      Audio audio => AudioListItem(key: ValueKey(item.id), audio: audio, isEditMode: isEditModeEnabled, onTap: notifyTapped, onDeleted: _removeFromAllTabs),
      Playlist playlist => PlaylistListItem(
        key: ValueKey(item.id),
        playlist: playlist,
        isEditMode: isEditModeEnabled,
        onTap: notifyTapped,
        onDeleted: _removeFromAllTabs,
      ),
      WithId() => throw UnimplementedError('No list item for ${item.runtimeType}'),
    };
  }
}
