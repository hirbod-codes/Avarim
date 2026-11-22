import 'package:avarim/components/core/core.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/search/music_search_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SelfManagedPagedListView<T> extends ConsumerStatefulWidget {
  const SelfManagedPagedListView({
    super.key,
    required this.loadPage,
    required this.itemBuilder,
    this.state,
    this.onPagedStateUpdate,
    this.bottomPadding,
    this.itemPadding,
    this.emptyBuilder,
    this.errorBuilder,
  });

  final Future<List<T>?> Function(int page) loadPage;
  final Widget Function(BuildContext context, T item, WidgetRef ref) itemBuilder;
  final PagedState<T>? state;
  final void Function(PagedState<T> pagedState)? onPagedStateUpdate;

  final double? bottomPadding;
  final EdgeInsetsGeometry? itemPadding;
  final WidgetBuilder? emptyBuilder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  @override
  ConsumerState<SelfManagedPagedListView> createState() => _SelfManagedPagedListView<T>();
}

class _SelfManagedPagedListView<T> extends ConsumerState<SelfManagedPagedListView<T>> {
  PagedState<T> _pageState = PagedState<T>(hasMore: true, isLoadingFirstPage: false, isLoadingNextPage: false, lastLoadedPage: null, items: []);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    Future.microtask(() => _onLoadPage(_resolveState().lastLoadedPage ?? kFirstPageNumber));
  }

  bool isStateControlled() => widget.onPagedStateUpdate != null && widget.state != null;

  PagedState<T> _resolveState() {
    return isStateControlled() ? widget.state! : _pageState;
  }

  void _updateState(PagedState<T> pagedState) {
    if (isStateControlled()) {
      widget.onPagedStateUpdate?.call(pagedState);
    } else if (mounted) {
      setState(() {
        _pageState = pagedState;
      });
    }
  }

  Future<void>? _onLoadPage(int page) async {
    try {
      if (!_resolveState().hasMore || _resolveState().isLoadingFirstPage || _resolveState().isLoadingNextPage) return;

      if (!mounted) return;

      _updateState(_resolveState().copyWith(isLoadingNextPage: true, isLoadingFirstPage: _resolveState().items.isEmpty));

      final items = await widget.loadPage(page);
      if (!mounted) return;

      _updateState(
        PagedState<T>(
          error: items != null ? null : Error(),
          isLoadingFirstPage: false,
          isLoadingNextPage: false,
          items: [..._resolveState().items, ...(items ?? [])],
          hasMore: items == null ? true : items.isEmpty || (items.isNotEmpty && items.length == kQueuePageSize),
          lastLoadedPage: page,
        ),
      );
    } catch (err) {
      talker.error('error caught in _onLoadPage method of _SelfManagedPagedListView class', {err});

      if (mounted) _updateState(_resolveState().copyWith(error: err, isLoadingFirstPage: false, isLoadingNextPage: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PagedListView<T>(
      state: _resolveState(),
      bottomPadding: widget.bottomPadding,
      itemPadding: widget.itemPadding ?? const EdgeInsets.symmetric(vertical: 8),
      emptyBuilder: widget.emptyBuilder,
      errorBuilder: widget.errorBuilder,
      onLoadNext: () {
        _onLoadPage((_resolveState().lastLoadedPage ?? kFirstPageNumber) + 1);
      },
      onRetryNext: () => _onLoadPage((_resolveState().lastLoadedPage ?? kFirstPageNumber) + 1),
      onReload: () async {
        _onLoadPage((_resolveState().lastLoadedPage ?? kFirstPageNumber));
      },
      itemBuilder: (context, item) => widget.itemBuilder(context, item, ref),
    );
  }
}
