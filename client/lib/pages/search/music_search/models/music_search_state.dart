import 'search_tab.dart';
import 'search_tab_results.dart';

/// The whole state of the search page.
class MusicSearchState {
  const MusicSearchState({
    required this.selectedTab,
    required this.committedQuery,
    required this.resultsByTab,
    this.isEditModeEnabled = false,
    this.idsBeingDeleted = const {},
    this.idsBeingAddedToQueue = const {},
  });

  final SearchTab selectedTab;

  /// The query that was actually searched (typed text only becomes the committed query after the debounce).
  final String committedQuery;
  final Map<SearchTab, SearchTabResults> resultsByTab;

  /// Shows edit / delete buttons on the results.
  final bool isEditModeEnabled;

  /// Items whose delete request is in flight (their delete button shows a spinner).
  final Set<String> idsBeingDeleted;

  /// Albums / playlists whose audios are being fetched to be queued (their queue button shows a spinner).
  final Set<String> idsBeingAddedToQueue;

  SearchTabResults resultsOf(SearchTab tab) => resultsByTab[tab]!;

  MusicSearchState copyWith({
    SearchTab? selectedTab,
    String? committedQuery,
    Map<SearchTab, SearchTabResults>? resultsByTab,
    bool? isEditModeEnabled,
    Set<String>? idsBeingDeleted,
    Set<String>? idsBeingAddedToQueue,
  }) => MusicSearchState(
    selectedTab: selectedTab ?? this.selectedTab,
    committedQuery: committedQuery ?? this.committedQuery,
    resultsByTab: resultsByTab ?? this.resultsByTab,
    isEditModeEnabled: isEditModeEnabled ?? this.isEditModeEnabled,
    idsBeingDeleted: idsBeingDeleted ?? this.idsBeingDeleted,
    idsBeingAddedToQueue: idsBeingAddedToQueue ?? this.idsBeingAddedToQueue,
  );
}
