/// What a paginated list knows about itself: the items loaded so far and where the loading stands.
/// Plain immutable data: whoever loads the pages (a State, a controller, ...) swaps in a new copy.
class PagedState<T> {
  PagedState({List<T>? items, this.lastLoadedPage, this.hasMore = true, this.isLoadingFirstPage = false, this.isLoadingNextPage = false, this.error})
    : items = items ?? <T>[];

  final List<T> items;

  /// Last page that was loaded successfully (null = none yet).
  final int? lastLoadedPage;
  final bool hasMore;

  /// Loading the first page (or refreshing).
  final bool isLoadingFirstPage;

  /// Loading the page after [lastLoadedPage].
  final bool isLoadingNextPage;
  final Object? error;

  bool get hasError => error != null;

  /// A fresh state: no page was requested yet.
  bool get wasNeverRequested => lastLoadedPage == null && !isLoadingFirstPage && !hasError;

  /// Nothing to show but a spinner: the first page wasn't requested yet, or is on its way.
  bool get isWaitingForFirstPage => lastLoadedPage == null && !hasError;

  PagedState<T> copyWith({List<T>? items, bool? isLoadingFirstPage, bool? isLoadingNextPage, Object? error, bool shouldClearError = false}) => PagedState<T>(
    items: items ?? this.items,
    lastLoadedPage: lastLoadedPage,
    hasMore: hasMore,
    isLoadingFirstPage: isLoadingFirstPage ?? this.isLoadingFirstPage,
    isLoadingNextPage: isLoadingNextPage ?? this.isLoadingNextPage,
    error: shouldClearError ? null : (error ?? this.error),
  );
}
