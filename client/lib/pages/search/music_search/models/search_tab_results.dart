import 'package:avarim/api/models/with_id.dart';

/// Everything the page knows about one tab: its loaded items and where the loading stands.
class SearchTabResults {
  const SearchTabResults({
    this.loadedItems = const [],
    this.lastLoadedPageNumber = 0,
    this.hasMorePages = true,
    this.isLoadingFirstPage = false,
    this.isLoadingNextPage = false,
    this.lastError,
    this.loadedForQuery,
  });

  final List<WithId> loadedItems;

  /// Last page that was loaded successfully.
  final int lastLoadedPageNumber;
  final bool hasMorePages;

  /// Loading the first page (or refreshing).
  final bool isLoadingFirstPage;

  /// Loading the page after [lastLoadedPageNumber].
  final bool isLoadingNextPage;
  final Object? lastError;

  /// The query these results belong to (null = this tab was never loaded).
  final String? loadedForQuery;

  SearchTabResults copyWith({
    List<WithId>? loadedItems,
    int? lastLoadedPageNumber,
    bool? hasMorePages,
    bool? isLoadingFirstPage,
    bool? isLoadingNextPage,
    Object? lastError,
    bool shouldClearLastError = false,
    String? loadedForQuery,
  }) => SearchTabResults(
    loadedItems: loadedItems ?? this.loadedItems,
    lastLoadedPageNumber: lastLoadedPageNumber ?? this.lastLoadedPageNumber,
    hasMorePages: hasMorePages ?? this.hasMorePages,
    isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
    isLoadingNextPage: isLoadingNextPage ?? this.isLoadingNextPage,
    lastError: shouldClearLastError ? null : (lastError ?? this.lastError),
    loadedForQuery: loadedForQuery ?? this.loadedForQuery,
  );
}
