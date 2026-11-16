import 'package:flutter/material.dart';

import '../lists/load_more_mode.dart';
import '../lists/scrollable_list.dart';
import '../widgets/list_footer.dart';
import '../widgets/status_message.dart';
import 'paged_state.dart';

/// Shows a [PagedState]: a spinner for the first load, an error with a retry button, an empty message, or the
/// items (with infinite scroll or a "Load more" button, pull-to-refresh and a footer).
///
/// Purely presentational: it loads nothing itself; pass the state and the callbacks of
/// whatever loads your pages. What a row looks like is up to [itemBuilder].
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.state,
    required this.itemBuilder,
    required this.onLoadNext,
    required this.onRetryNext,
    required this.onReload,
    this.loadMoreMode = LoadMoreMode.infiniteScroll,
    this.bottomPadding,
    this.itemPadding = const EdgeInsets.symmetric(vertical: 8),
    this.keepAlive = true,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
  });

  final PagedState<T> state;
  final Widget Function(BuildContext context, T item) itemBuilder;

  final VoidCallback onLoadNext;
  final VoidCallback onRetryNext;
  final Future<void> Function() onReload;

  final LoadMoreMode loadMoreMode;
  final double? bottomPadding;
  final EdgeInsetsGeometry itemPadding;

  /// Keeps the list (and its scroll position) alive inside a TabBarView / PageView when it is swiped away.
  final bool keepAlive;

  /// Replace the default first-load spinner / error message / empty message.
  final WidgetBuilder? loadingBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final WidgetBuilder? emptyBuilder;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final state = widget.state;

    if (state.isWaitingForFirstPage) {
      return widget.loadingBuilder?.call(context) ?? const Center(child: CircularProgressIndicator());
    }

    if (state.hasError && state.items.isEmpty) {
      return widget.errorBuilder?.call(context, state.error!) ??
          StatusMessage(icon: Icons.error_outline, message: 'Something went wrong', actionLabel: 'Retry', onActionPressed: widget.onReload);
    }

    if (state.items.isEmpty) {
      return widget.emptyBuilder?.call(context) ?? const StatusMessage(icon: Icons.search_off, message: 'No results');
    }

    final showsFooter = state.isLoadingNextPage || state.hasError || (state.hasMore && widget.loadMoreMode == LoadMoreMode.loadMoreButton);
    final itemCount = state.items.length + (showsFooter ? 1 : 0);

    return ScrollableList(
      itemCount: itemCount,
      loadMoreMode: widget.loadMoreMode,
      onLoadNext: widget.onLoadNext,
      onRefresh: widget.onReload,
      bottomPadding: widget.bottomPadding,
      itemBuilder: (context, index) {
        if (index >= state.items.length) {
          return ListFooter(isLoading: state.isLoadingNextPage, hasError: state.hasError, onLoadMore: widget.onLoadNext, onRetry: widget.onRetryNext);
        }
        return Padding(padding: widget.itemPadding, child: widget.itemBuilder(context, state.items[index]));
      },
    );
  }
}
