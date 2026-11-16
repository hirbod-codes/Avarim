import 'package:flutter/material.dart';

/// A [Scaffold] whose app bar carries a [TabBar] and whose body is a [TabBarView], with one tab per entry of [tabs].
/// It owns the [TabController]; the pages come from [pageBuilder] and are built lazily by the TabBarView.
///
/// [onTabChanged] is called once each time the selected tab changes (as soon as a tap/swipe starts changing it).
class TabBarScaffold<T> extends StatefulWidget {
  const TabBarScaffold({
    super.key,
    required this.tabs,
    required this.tabLabel,
    required this.pageBuilder,
    this.title,
    this.actions,
    this.initialTab,
    this.onTabChanged,
    this.isTabBarScrollable = false,
  });

  final List<T> tabs;
  final String Function(T tab) tabLabel;
  final Widget Function(BuildContext context, T tab) pageBuilder;

  final Widget? title;
  final List<Widget>? actions;
  final T? initialTab;
  final ValueChanged<T>? onTabChanged;
  final bool isTabBarScrollable;

  @override
  State<TabBarScaffold<T>> createState() => _TabBarScaffoldState<T>();
}

class _TabBarScaffoldState<T> extends State<TabBarScaffold<T>> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late int _lastReportedIndex;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTab == null ? 0 : widget.tabs.indexOf(widget.initialTab as T).clamp(0, widget.tabs.length - 1).toInt();
    _lastReportedIndex = initialIndex;
    _tabController = TabController(length: widget.tabs.length, vsync: this, initialIndex: initialIndex)..addListener(_onTabControllerChanged);
  }

  void _onTabControllerChanged() {
    final index = _tabController.index;
    if (index == _lastReportedIndex) return;
    _lastReportedIndex = index;
    widget.onTabChanged?.call(widget.tabs[index]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.title,
        actions: widget.actions,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: widget.isTabBarScrollable,
          tabs: [for (final tab in widget.tabs) Tab(text: widget.tabLabel(tab))],
        ),
      ),
      body: TabBarView(controller: _tabController, children: [for (final tab in widget.tabs) widget.pageBuilder(context, tab)]),
    );
  }
}
