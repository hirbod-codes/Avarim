import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/music_search_api.dart';
import '../models/music_search_state.dart';
import '../models/search_tab.dart';
import '../models/search_tab_results.dart';
import '../music_search_config.dart';

class MusicSearchController extends Notifier<MusicSearchState> {
  Timer? _searchDebounceTimer;

  /// The trimmed text of the search box. It becomes [MusicSearchState.committedQuery] once the user stops typing.
  String _uncommittedQuery = '';

  final Map<SearchTab, CancelToken> _cancelTokenByTab = {};

  @override
  MusicSearchState build() {
    ref.onDispose(() {
      _searchDebounceTimer?.cancel();
      for (final cancelToken in _cancelTokenByTab.values) {
        cancelToken.cancel();
      }
    });

    _uncommittedQuery = '';

    // Initial load: no query, selected (first) tab.
    Future.microtask(_loadActiveTabIfItsResultsAreStale);

    return MusicSearchState(
      selectedTab: SearchTab.artists,
      committedQuery: '',
      resultsByTab: {for (final tab in SearchTab.values) tab: const SearchTabResults()},
    );
  }

  // ── Search box and tabs ────────────────────────────────────────────────────

  /// Called on every keystroke; searches after [kSearchInputDebounceDuration] of silence.
  void onSearchTextChanged(String text) {
    _uncommittedQuery = text.trim();
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(kSearchInputDebounceDuration, _commitQueryAndLoadActiveTabIfNeeded);
  }

  /// Search immediately (keyboard "search" action / clear button).
  void submitSearchText(String text) {
    _uncommittedQuery = text.trim();
    _commitQueryAndLoadActiveTabIfNeeded();
  }

  void selectTab(SearchTab tab) {
    if (tab != state.selectedTab) state = state.copyWith(selectedTab: tab);
    // Also flushes a pending (debounced) query so the new tab loads once, with it.
    _commitQueryAndLoadActiveTabIfNeeded();
  }

  // ── Loading results ────────────────────────────────────────────────────────

  /// Pull-to-refresh / retry for a tab: reloads page 1, keeping old items visible.
  Future<void> reloadFirstPage(SearchTab tab) {
    return _loadResultsPage(tab, restartFromFirstPage: true, keepCurrentItemsWhileReloading: true);
  }

  /// Loads the page after the last loaded one for [tab]. No-op if already loading, no more data, or
  /// the last attempt failed (unless [retryAfterError] is true).
  Future<void> loadNextPage(SearchTab tab, {bool retryAfterError = false}) {
    return _loadResultsPage(tab, restartFromFirstPage: false, retryAfterError: retryAfterError);
  }

  // ── Actions on results ─────────────────────────────────────────────────────

  void toggleEditMode() => state = state.copyWith(isEditModeEnabled: !state.isEditModeEnabled);

  /// Adds every audio of an album or a playlist to the player queue (see AudioPlayerService.add):
  ///  - [playImmediately] = true: the first of them starts playing right away, the rest of the queue is kept
  ///  - [playImmediately] = false: they are only appended, the current track keeps playing
  /// While the audios are fetched the item's id is in [MusicSearchState.idsBeingAddedToQueue] (its button spins).
  Future<void> addAlbumOrPlaylistToQueue(WithId item, {required bool playImmediately}) async {
    if (state.idsBeingAddedToQueue.contains(item.id)) return;
    state = state.copyWith(idsBeingAddedToQueue: {...state.idsBeingAddedToQueue, item.id});

    List<String>? audioIds;
    try {
      final api = ref.read(musicSearchApiProvider);
      audioIds = switch (item) {
        Album album => await api.fetchAllAudioIdsOfAlbum(album.id),
        Playlist playlist => await api.fetchAllAudioIdsOfPlaylist(playlist.id),
        _ => const <String>[],
      };
    } catch (error, stackTrace) {
      talker.error('fetching the audios to queue failed', error, stackTrace);
    }

    // audioIds == null: a request failed and its error was already shown.
    if (audioIds != null) {
      if (audioIds.isEmpty) {
        NotificationService.showError(message: 'There are no audios to add');
      } else {
        // The player is global, so this works even if the user already left the page.
        AudioPlayerService.add(audioIds: audioIds, play: playImmediately);
        if (!playImmediately) {
          NotificationService.showSuccess(message: audioIds.length == 1 ? 'Added 1 audio to the queue' : 'Added ${audioIds.length} audios to the queue');
        }
      }
    }

    if (ref.mounted) {
      state = state.copyWith(idsBeingAddedToQueue: {...state.idsBeingAddedToQueue}..remove(item.id));
    }
  }

  /// Deletes an audio. While the request runs its id is in [MusicSearchState.idsBeingDeleted];
  /// on success it disappears from every tab (and from the floating player if it was playing).
  Future<void> deleteAudio(String audioId) async {
    if (state.idsBeingDeleted.contains(audioId)) return;
    state = state.copyWith(idsBeingDeleted: {...state.idsBeingDeleted, audioId});

    var wasDeleted = false;
    try {
      wasDeleted = await ref.read(musicSearchApiProvider).deleteAudioById(audioId);
    } catch (error, stackTrace) {
      talker.error('deleting audio failed', error, stackTrace);
    }
    if (!ref.mounted) return;

    final remainingIdsBeingDeleted = {...state.idsBeingDeleted}..remove(audioId);

    if (!wasDeleted) {
      state = state.copyWith(idsBeingDeleted: remainingIdsBeingDeleted);
      NotificationService.showError(message: 'Could not delete the audio');
      return;
    }

    state = state.copyWith(idsBeingDeleted: remainingIdsBeingDeleted, resultsByTab: _resultsByTabWithoutItem(audioId));

    // Drops it from the player queue (no-op if it isn't queued; closes the dock if it was the last track).
    AudioPlayerService.remove(audioId);
  }

  /// Deletes an artist or an album. While the request runs its id is in [MusicSearchState.idsBeingDeleted]; on success
  /// it disappears from every tab. A failure says why (an artist that still has albums or audios can't go).
  Future<void> deleteArtistOrAlbum(WithId item) async {
    final itemId = item.id;
    if (state.idsBeingDeleted.contains(itemId)) return;
    state = state.copyWith(idsBeingDeleted: {...state.idsBeingDeleted, itemId});

    ApiCallResult<dynamic>? deleteResult;
    try {
      final api = ref.read(musicSearchApiProvider);
      deleteResult = item is Artist ? await api.deleteArtistById(itemId) : await api.deleteAlbumById(itemId);
    } catch (error, stackTrace) {
      talker.error('deleting ${item.runtimeType} failed', error, stackTrace);
    }
    if (!ref.mounted) return;

    final remainingIdsBeingDeleted = {...state.idsBeingDeleted}..remove(itemId);

    if (deleteResult == null || !deleteResult.isSuccess) {
      state = state.copyWith(idsBeingDeleted: remainingIdsBeingDeleted);

      final failureErrorCode = switch (deleteResult) {
        ApiCallFailure(:final errorCode) => errorCode,
        _ => null,
      };

      final String failureMessage;
      if (item is Artist) {
        final artistStillHasAlbumsOrAudios = failureErrorCode == 'UNRESOLVED_ALBUMS_AUDIOS';
        failureMessage = artistStillHasAlbumsOrAudios
            ? 'This artist still has albums or audios. Delete them or move them to another artist first.'
            : 'Could not delete the artist';
      } else {
        failureMessage = 'Could not delete the album';
      }
      NotificationService.showError(message: failureMessage);
      return;
    }

    state = state.copyWith(idsBeingDeleted: remainingIdsBeingDeleted, resultsByTab: _resultsByTabWithoutItem(itemId));
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  void _commitQueryAndLoadActiveTabIfNeeded() {
    _searchDebounceTimer?.cancel();
    if (_uncommittedQuery != state.committedQuery) {
      state = state.copyWith(committedQuery: _uncommittedQuery);
    }
    _loadActiveTabIfItsResultsAreStale();
  }

  /// Makes sure the active tab holds results for the committed query.
  void _loadActiveTabIfItsResultsAreStale() {
    if (!ref.mounted) return;
    final activeTab = state.selectedTab;
    if (state.resultsOf(activeTab).loadedForQuery != state.committedQuery) {
      unawaited(_loadResultsPage(activeTab, restartFromFirstPage: true));
    }
  }

  Map<SearchTab, SearchTabResults> _resultsByTabWithoutItem(String itemId) {
    return {
      for (final entry in state.resultsByTab.entries)
        entry.key: entry.value.copyWith(loadedItems: entry.value.loadedItems.where((item) => item.id != itemId).toList()),
    };
  }

  void _replaceResultsOfTab(SearchTab tab, SearchTabResults results) {
    if (!ref.mounted) return;
    state = state.copyWith(resultsByTab: {...state.resultsByTab, tab: results});
  }

  Future<void> _loadResultsPage(
    SearchTab tab, {
    required bool restartFromFirstPage,
    bool keepCurrentItemsWhileReloading = false,
    bool retryAfterError = false,
  }) async {
    final currentResults = state.resultsOf(tab);

    if (!restartFromFirstPage) {
      if (currentResults.isLoadingFirstPage || currentResults.isLoadingNextPage || !currentResults.hasMorePages) return;
      if (currentResults.lastError != null && !retryAfterError) return;
    }

    // A new request for this tab supersedes any in-flight one.
    _cancelTokenByTab[tab]?.cancel();
    final cancelToken = _cancelTokenByTab[tab] = CancelToken();

    final query = state.committedQuery;
    final pageNumberToLoad = restartFromFirstPage ? kFirstPageNumber : currentResults.lastLoadedPageNumber + 1;

    final SearchTabResults resultsWhileLoading;
    if (!restartFromFirstPage) {
      resultsWhileLoading = currentResults.copyWith(isLoadingNextPage: true, shouldClearLastError: true);
    } else if (keepCurrentItemsWhileReloading) {
      resultsWhileLoading = currentResults.copyWith(isLoadingFirstPage: true, shouldClearLastError: true, loadedForQuery: query);
    } else {
      resultsWhileLoading = SearchTabResults(isLoadingFirstPage: true, loadedForQuery: query);
    }
    _replaceResultsOfTab(tab, resultsWhileLoading);

    try {
      final fetchedItems = await ref
          .read(musicSearchApiProvider)
          .fetchSearchResultsPage(tab, query: query, pageNumber: pageNumberToLoad, pageSize: kSearchResultsPageSize, cancelToken: cancelToken);
      if (!ref.mounted || cancelToken.isCancelled) return;

      _replaceResultsOfTab(
        tab,
        SearchTabResults(
          loadedItems: restartFromFirstPage ? fetchedItems : [...state.resultsOf(tab).loadedItems, ...fetchedItems],
          lastLoadedPageNumber: pageNumberToLoad,
          // Hide "load more" once the server returns an empty array.
          // (Use `fetchedItems.length >= kSearchResultsPageSize` to also skip the last empty request.)
          hasMorePages: fetchedItems.isNotEmpty,
          loadedForQuery: query,
        ),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || !ref.mounted) return;
      _markTabAsFailed(tab, error);
    } catch (error) {
      if (!ref.mounted) return;
      _markTabAsFailed(tab, error);
    }
  }

  void _markTabAsFailed(SearchTab tab, Object error) {
    _replaceResultsOfTab(tab, state.resultsOf(tab).copyWith(isLoadingFirstPage: false, isLoadingNextPage: false, lastError: error));
  }
}

/// autoDispose: leaving the page resets query, tab and results.
final musicSearchControllerProvider = NotifierProvider.autoDispose<MusicSearchController, MusicSearchState>(MusicSearchController.new);
