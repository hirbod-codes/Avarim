import 'dart:async';

import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/popup.dart';
import 'package:avarim/pages/edit_album/edit_album_page.dart';
import 'package:avarim/pages/edit_artist/edit_artist_page.dart';
import 'package:avarim/pages/edit_audio/edit_audio_page.dart';
import 'package:avarim/pages/search/music_search/data/music_search_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../controller/music_search_controller.dart';
import '../models/load_more_mode.dart';
import '../models/search_tab.dart';
import '../models/search_tab_results.dart';
import '../music_search_config.dart';
import 'delete_confirmation_dialog.dart';
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
  /// With [LoadMoreMode.infiniteScroll], the next page is requested when fewer pixels than this are left to scroll.
  static const _distanceFromEndThatTriggersNextPage = 300.0;

  final _scrollController = ScrollController();

  // Keeps scroll position when switching tabs.
  @override
  bool get wantKeepAlive => true;

  bool get _loadsNextPageAutomatically => widget.loadMoreMode == LoadMoreMode.infiniteScroll;

  Audio? _editingAudio;
  Album? _editingAlbum;
  Artist? _editingArtist;

  final _scroll = ScrollController();

  List<Audio> _albumViewAudios = [];
  Album? _openedAlbum;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollPositionChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadNextPage({bool retryAfterError = false}) {
    unawaited(ref.read(musicSearchControllerProvider.notifier).loadNextPage(widget.tab, retryAfterError: retryAfterError));
  }

  void _onScrollPositionChanged() {
    if (!_loadsNextPageAutomatically) return;

    final isNearEnd = _scrollController.position.extentAfter < _distanceFromEndThatTriggersNextPage;
    if (isNearEnd) _loadNextPage();
  }

  /// If the first page doesn't fill the screen there is nothing to scroll,
  /// so keep loading pages until it does (or the server runs out).
  void _loadNextPageIfViewportIsNotFilled() {
    if (!mounted || !_loadsNextPageAutomatically || !_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0) _loadNextPage();
  }

  // ── Reacting to taps ───────────────────────────────────────────────────────

  /// The tap handler of a row, or null when tapping it does nothing.
  VoidCallback? _tapCallbackFor(WithId item) {
    if (item is Artist) return () => _openArtistDetails(item);

    final isTappable = item is Audio || item is Album || item is Playlist || widget.onResultTapped != null;
    return isTappable ? () => _onResultTapped(item) : null;
  }

  void _openArtistDetails(Artist artist) {
    context.push(Uri(path: kArtistDetailsRoutePath, queryParameters: {'artistId': artist.id}).toString());
  }

  void _onResultTapped(WithId item) async {
    widget.onResultTapped?.call(item);

    if (item is Audio) {
      AudioPlayerService.add(audioId: item.id);
    } else if (item is Playlist) {
      // All of the playlist's audios go into the queue and the first of them starts playing.
      unawaited(ref.read(musicSearchControllerProvider.notifier).addAlbumOrPlaylistToQueue(item, playImmediately: true));
    } else if (item is Album) {
      final List<Audio>? audios = await ref.read(musicSearchApiProvider).fetchAllAudiosOfAlbum(item.id);
      if (!mounted) return;

      if (audios == null) return;

      setState(() {
        _albumViewAudios = audios;
        _openedAlbum = item;
      });
    }
  }

  // ── Editing ────────────────────────────────────────────────────────────────

  /// Opens the edit page of [item]; refreshes the affected tab(s) when the user comes back.
  Future<void> _openEditPageFor(WithId item) async {
    if (item is Audio) {
      await _openEditPageOfAudio(item);
    } else if (item is Artist) {
      await _openEditPageOfArtist(item);
    } else if (item is Album) {
      await _openEditPageOfAlbum(item);
    }
  }

  Future<void> _openEditPageOfAudio(Audio audio) async {
    setState(() {
      _editingAudio = audio;
    });
  }

  Future<void> _openEditPageOfArtist(Artist artist) async {
    setState(() {
      _editingArtist = artist;
    });

    // final editPageLocation = Uri(path: kEditArtistRoutePath, queryParameters: {'artistId': artist.id}).toString();
    // await context.push(editPageLocation);

    // if (!mounted) return;
    // unawaited(ref.read(musicSearchControllerProvider.notifier).reloadFirstPage(SearchTab.artists));
  }

  Future<void> _openEditPageOfAlbum(Album album) async {
    setState(() {
      _editingAlbum = album;
    });

    // final editPageLocation = Uri(path: kEditAlbumRoutePath, queryParameters: {'albumId': album.id}).toString();
    // await context.push(editPageLocation);

    // if (!mounted) return;
    // unawaited(ref.read(musicSearchControllerProvider.notifier).reloadFirstPage(SearchTab.albums));
  }

  // ── Deleting ───────────────────────────────────────────────────────────────

  Future<void> _confirmAndDelete(WithId item) async {
    if (kShouldConfirmBeforeDelete) {
      final wasConfirmed = await showDeleteConfirmationDialog(context, item: item);
      if (!wasConfirmed || !mounted) return;
    }

    final searchController = ref.read(musicSearchControllerProvider.notifier);
    if (item is Audio) {
      await searchController.deleteAudio(item.id);
    } else if (item is Album) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final theme = Theme.of(ctx);

          return AlertDialog(
            title: const Text('Delete all audios?'),
            content: Text(
              'Every audio of "${item.name}" will be deleted, one by one. '
              'They disappear from every album, artist and playlist they are in. This cannot be undone.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete all'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;

      await searchController.deleteAllAudiosOfAlbum(item);

      await searchController.deleteArtistOrAlbum(item);
    } else {
      await searchController.deleteArtistOrAlbum(item);
    }
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

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextPageIfViewportIsNotFilled());

    final shouldShowFooter = tabResults.isLoadingNextPage || tabResults.lastError != null || (tabResults.hasMorePages && !_loadsNextPageAutomatically);

    return ValueListenableBuilder<AudioQueueState>(
      valueListenable: AudioPlayerService.queue,
      builder: (context, queue, _) {
        final theme = Theme.of(context);

        final currentlyPlayingAudioId = queue.currentId;
        // Keep the last item reachable above the player dock.
        final bottomPaddingAbovePlayerDock = queue.isEmpty ? 0.0 : kDockCollapsedExtent + MediaQuery.paddingOf(context).bottom;

        SearchResultTile getTile(WithId item) => SearchResultTile(
          item: item,
          isPlaying: item is Audio && item.id == currentlyPlayingAudioId,
          isEditModeEnabled: isEditModeEnabled,
          isBeingDeleted: idsBeingDeleted.contains(item.id),
          isBeingAddedToQueue: idsBeingAddedToQueue.contains(item.id),
          onTap: _tapCallbackFor(item),
          onAddToQueue: item is Album || item is Playlist ? () => searchController.addAlbumOrPlaylistToQueue(item, playImmediately: false) : null,
          onAvatarPlay: item is Album || item is Playlist
              ? () {
                  unawaited(ref.read(musicSearchControllerProvider.notifier).replaceAlbumOrPlaylistToQueue(item, playImmediately: true));
                }
              : null,
          onEdit: () => _openEditPageFor(item),
          onDelete: item is Audio || item is Artist || item is Album ? () => _confirmAndDelete(item) : null,
        );

        return RefreshIndicator(
          onRefresh: () => searchController.reloadFirstPage(widget.tab),
          child: Stack(
            children: [
              ListView.separated(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: bottomPaddingAbovePlayerDock),
                itemCount: tabResults.loadedItems.length + (shouldShowFooter ? 1 : 0),
                separatorBuilder: (context, index) => const Divider(height: 1),
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

              if (_editingAudio != null)
                Positioned.fill(
                  child: Popup(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    leadings: [Text(_editingAudio!.title)],
                    onClose: () => setState(() {
                      _editingAudio = null;
                    }),
                    child: EditAudioPage(audioId: _editingAudio!.id),
                  ),
                ),

              if (_editingAlbum != null)
                Positioned.fill(
                  child: Popup(
                    leadings: [Text(_editingAlbum!.name)],
                    onClose: () => setState(() {
                      _editingAlbum = null;
                    }),
                    child: EditAlbumPage(albumId: _editingAlbum!.id),
                  ),
                ),

              if (_editingArtist != null)
                Positioned.fill(
                  child: Popup(
                    leadings: [Text(_editingArtist!.name)],
                    onClose: () => setState(() {
                      _editingArtist = null;
                    }),
                    child: EditArtistPage(artistId: _editingArtist!.id),
                  ),
                ),

              if (_openedAlbum != null)
                Positioned.fill(
                  child: Popup(
                    leadings: [
                      const Icon(Icons.album),
                      Text(_openedAlbum!.name, style: theme.textTheme.titleMedium),
                    ],
                    onClose: () => setState(() {
                      _openedAlbum = null;
                      _albumViewAudios = [];
                    }),
                    child: Expanded(
                      child: Scrollbar(
                        controller: _scroll,
                        child: SearchResultsList(
                          loadMoreMode: LoadMoreMode.infiniteScroll,
                          tab: SearchTab.audios,
                          tabResults: SearchTabResults(hasMorePages: false, loadedItems: _albumViewAudios, loadedForQuery: 'already loaded'),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
