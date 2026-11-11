import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/load_more_mode.dart';
import '../models/search_tab.dart';

/// The scrollable results of ONE tab (the page builds one per [SearchTab]).
class ScrollableList extends ConsumerStatefulWidget {
  const ScrollableList({
    super.key,
    required this.loadNextPage,
    required this.onRefresh,
    this.bottomPaddingAbovePlayerDock,
    required this.itemCount,
    required this.itemBuilder,
    required this.loadMoreMode,
  });

  final void Function({bool retryAfterError}) loadNextPage;
  final RefreshCallback onRefresh;
  final double? bottomPaddingAbovePlayerDock;
  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final LoadMoreMode loadMoreMode;

  @override
  ConsumerState<ScrollableList> createState() => _ScrollableListState();
}

class _ScrollableListState extends ConsumerState<ScrollableList> with AutomaticKeepAliveClientMixin {
  /// With [LoadMoreMode.infiniteScroll], the next page is requested when fewer pixels than this are left to scroll.
  static const _distanceFromEndThatTriggersNextPage = 300.0;

  final _scrollController = ScrollController();

  // Keeps scroll position when switching tabs.
  @override
  bool get wantKeepAlive => true;

  bool get _loadsNextPageAutomatically => widget.loadMoreMode == LoadMoreMode.infiniteScroll;

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

  void _onScrollPositionChanged() {
    if (!_loadsNextPageAutomatically) return;

    final isNearEnd = _scrollController.position.extentAfter < _distanceFromEndThatTriggersNextPage;
    if (isNearEnd) widget.loadNextPage();
  }

  /// If the first page doesn't fill the screen there is nothing to scroll,
  /// so keep loading pages until it does (or the server runs out).
  void _loadNextPageIfViewportIsNotFilled() {
    if (!mounted || !_loadsNextPageAutomatically || !_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0) widget.loadNextPage();
  }

  // ── Building ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextPageIfViewportIsNotFilled());

    return RefreshIndicator(
      onRefresh: widget.onRefresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: widget.bottomPaddingAbovePlayerDock == null ? null : EdgeInsets.only(bottom: widget.bottomPaddingAbovePlayerDock!),
        itemCount: widget.itemCount,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}
