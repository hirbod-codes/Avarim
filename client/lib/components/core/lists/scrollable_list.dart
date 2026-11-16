import 'package:flutter/material.dart';

import 'load_more_mode.dart';

/// A scrollable, optionally pull-to-refresh list that can ask for more items near its end.
///
/// It knows nothing about what it lists or where the items come from:
///  - [onLoadNext] (null = never asks for more) is called when scrolled near the end with
///    [LoadMoreMode.infiniteScroll], and while the items don't fill the viewport.
///  - [onRefresh] (null = no pull-to-refresh).
class ScrollableList extends StatefulWidget {
  const ScrollableList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.onLoadNext,
    this.onRefresh,
    this.loadMoreMode = LoadMoreMode.infiniteScroll,
    this.bottomPadding,
    this.separatorBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final VoidCallback? onLoadNext;
  final RefreshCallback? onRefresh;
  final LoadMoreMode loadMoreMode;

  /// Extra space under the last item (e.g. to keep it reachable above a docked player).
  final double? bottomPadding;

  /// Defaults to a 1px [Divider].
  final IndexedWidgetBuilder? separatorBuilder;

  @override
  State<ScrollableList> createState() => _ScrollableListState();
}

class _ScrollableListState extends State<ScrollableList> {
  /// With [LoadMoreMode.infiniteScroll], the next page is requested when fewer pixels than this are left to scroll.
  static const _distanceFromEndThatTriggersNextPage = 300.0;

  final _scrollController = ScrollController();

  bool get _loadsNextAutomatically => widget.onLoadNext != null && widget.loadMoreMode == LoadMoreMode.infiniteScroll;

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
    if (!_loadsNextAutomatically) return;
    final isNearEnd = _scrollController.position.extentAfter < _distanceFromEndThatTriggersNextPage;
    if (isNearEnd) widget.onLoadNext!();
  }

  /// If the items don't fill the screen there is nothing to scroll, so keep asking for more until they do.
  void _loadNextIfViewportIsNotFilled() {
    if (!mounted || !_loadsNextAutomatically || !_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent <= 0) widget.onLoadNext!();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadNextIfViewportIsNotFilled());

    final list = ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: widget.bottomPadding == null ? null : EdgeInsets.only(bottom: widget.bottomPadding!),
      itemCount: widget.itemCount,
      separatorBuilder: widget.separatorBuilder ?? (context, index) => const Divider(height: 1),
      itemBuilder: widget.itemBuilder,
    );

    if (widget.onRefresh == null) return list;
    return RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
  }
}
