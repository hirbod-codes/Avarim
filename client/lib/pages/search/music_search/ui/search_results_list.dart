import 'dart:async';

import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/pages/search/music_search/ui/scrollable_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controller/music_search_controller.dart';
import '../models/load_more_mode.dart';
import '../models/search_tab.dart';
import '../models/search_tab_results.dart';
import 'results_list_footer.dart';
import 'results_list_message.dart';
import 'search_result_tile.dart';

/// The scrollable results of ONE tab (the page builds one per [SearchTab]).
class SearchResultsList extends ConsumerStatefulWidget {
  const SearchResultsList({super.key, required this.tab, required this.loadMoreMode, this.onResultTapped, this.tabResults});

  final SearchTab tab;
  final LoadMoreMode loadMoreMode;
  final ValueChanged<WithId>? onResultTapped;
  final SearchTabResults? tabResults;

  @override
  ConsumerState<SearchResultsList> createState() => _SearchResultsListState();
}

class _SearchResultsListState extends ConsumerState<SearchResultsList> with AutomaticKeepAliveClientMixin {
  // Keeps scroll position when switching tabs.
  @override
  bool get wantKeepAlive => true;

  bool get _loadsNextPageAutomatically => widget.loadMoreMode == LoadMoreMode.infiniteScroll;

  @override
  void dispose() {
    super.dispose();
  }

  void _loadNextPage({bool retryAfterError = false}) {
    unawaited(ref.read(musicSearchControllerProvider.notifier).loadNextPage(widget.tab, retryAfterError: retryAfterError));
  }

  // ── Building ───────────────────────────────────────────────────────────────

  /// What to show instead of the list while there is nothing to list: loading, an error, or no results.
  Widget _buildStateWithoutItems(SearchTabResults tabResults, MusicSearchController searchController) {
    final isLoadingOrNeverLoaded = tabResults.isLoadingFirstPage || tabResults.loadedForQuery == null;
    if (isLoadingOrNeverLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tabResults.lastError != null) {
      return ResultsListMessage(
        icon: Icons.error_outline,
        message: 'Something went wrong',
        actionLabel: 'Retry',
        onActionPressed: () => searchController.reloadFirstPage(widget.tab),
      );
    }

    final everyAudioHasAnArtist = widget.tab == SearchTab.audiosWithoutArtist && (tabResults.loadedForQuery ?? '').isEmpty;
    return ResultsListMessage(
      icon: everyAudioHasAnArtist ? Icons.check_circle_outline : Icons.search_off,
      message: everyAudioHasAnArtist ? 'Every audio has an artist' : 'No results',
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    final SearchTabResults tabResults = widget.tabResults ?? ref.watch(musicSearchControllerProvider.select((state) => state.resultsOf(widget.tab)));
    final searchController = ref.read(musicSearchControllerProvider.notifier);
    final isEditModeEnabled = ref.watch(musicSearchControllerProvider.select((state) => state.isEditModeEnabled));
    final idsBeingDeleted = ref.watch(musicSearchControllerProvider.select((state) => state.idsBeingDeleted));
    final idsBeingAddedToQueue = ref.watch(musicSearchControllerProvider.select((state) => state.idsBeingAddedToQueue));

    if (tabResults.loadedItems.isEmpty) {
      return _buildStateWithoutItems(tabResults, searchController);
    }

    final shouldShowFooter = tabResults.isLoadingNextPage || tabResults.lastError != null || (tabResults.hasMorePages && !_loadsNextPageAutomatically);

    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, queue, _) {
        // Keep the last item reachable above the player dock.
        final bottomPaddingAbovePlayerDock = queue.isEmpty ? 0.0 : kDockCollapsedExtent + MediaQuery.paddingOf(context).bottom;

        SearchResultTile getTile(WithId item) => SearchResultTile(
          item: item,
          isEditModeEnabled: isEditModeEnabled,
          isBeingDeleted: idsBeingDeleted.contains(item.id),
          isBeingAddedToQueue: idsBeingAddedToQueue.contains(item.id),
          onTap: widget.onResultTapped == null
              ? null
              : () {
                  widget.onResultTapped!(item);
                },
          onAddToQueue: item is Album || item is Playlist ? () => searchController.addAlbumOrPlaylistToQueue(item, playImmediately: false) : null,
          onAvatarPlay: item is Album || item is Playlist
              ? () {
                  unawaited(ref.read(musicSearchControllerProvider.notifier).replaceAlbumOrPlaylistToQueue(item, playImmediately: true));
                }
              : null,
        );

        return Stack(
          children: [
            ScrollableList(
              bottomPaddingAbovePlayerDock: bottomPaddingAbovePlayerDock,
              itemCount: tabResults.loadedItems.length + (shouldShowFooter ? 1 : 0),
              loadMoreMode: LoadMoreMode.infiniteScroll,
              loadNextPage: _loadNextPage,
              onRefresh: () => searchController.reloadFirstPage(widget.tab),
              itemBuilder: (context, index) {
                final isFooter = index >= tabResults.loadedItems.length;
                if (isFooter) {
                  return ResultsListFooter(
                    isLoadingNextPage: tabResults.isLoadingNextPage,
                    hasLoadingError: tabResults.lastError != null,
                    onLoadMorePressed: _loadNextPage,
                    onRetryPressed: () => _loadNextPage(retryAfterError: true),
                  );
                }

                final item = tabResults.loadedItems[index];
                return Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: getTile(item));
              },
            ),
          ],
        );
      },
    );
  }
}
