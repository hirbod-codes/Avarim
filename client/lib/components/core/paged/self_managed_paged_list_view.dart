import 'package:avarim/components/core/core.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/search/music_search_config.dart';
import 'package:flutter/material.dart';

class SelfManagedPagedListView<T> extends StatefulWidget {
  const SelfManagedPagedListView({super.key, required this.loadPage, required this.itemBuilder});

  final Future<List<T>?> Function(int page) loadPage;

  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  State<StatefulWidget> createState() => _SelfManagedPagedListView<T>();
}

class _SelfManagedPagedListView<T> extends State<SelfManagedPagedListView<T>> {
  PagedState<T> _pageState = PagedState<T>(hasMore: true, isLoadingFirstPage: true, isLoadingNextPage: true, lastLoadedPage: null, items: []);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _onLoadPage(_pageState.lastLoadedPage ?? kFirstPageNumber);
  }

  Future<void>? _onLoadPage(int page) async {
    try {
      final items = await widget.loadPage(page);
      if (!mounted) return;

      setState(() {
        _pageState = PagedState<T>(
          error: items != null ? null : Error(),
          isLoadingFirstPage: false,
          isLoadingNextPage: false,
          items: [..._pageState.items, ...(items ?? [])],
          hasMore: items == null ? true : !(items.isEmpty || items.length < kQueuePageSize),
          lastLoadedPage: page + 1,
        );
      });
    } catch (err) {
      talker.error('error caught in _onLoadPage method of _SelfManagedPagedListView class', {err});

      if (mounted) {
        setState(() {
          _pageState = _pageState.copyWith(error: err, isLoadingFirstPage: false, isLoadingNextPage: false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PagedListView<T>(
      state: _pageState,
      onLoadNext: () {
        _onLoadPage((_pageState.lastLoadedPage ?? kFirstPageNumber) + 1);
      },
      onRetryNext: () => _onLoadPage((_pageState.lastLoadedPage ?? kFirstPageNumber) + 1),
      onReload: () async {
        _onLoadPage((_pageState.lastLoadedPage ?? kFirstPageNumber) + 1);
      },
      itemBuilder: widget.itemBuilder,
    );
  }
}
