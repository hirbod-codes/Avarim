/// How the next page of results is requested.
enum LoadMoreMode {
  /// Automatically loads the next page when the list is scrolled near the end.
  infiniteScroll,

  /// Shows a "Load more" button at the end of the list.
  loadMoreButton,
}
