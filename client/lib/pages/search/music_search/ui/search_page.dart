import 'package:avarim/account/user_info_notifier.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controller/music_search_controller.dart';
import '../models/load_more_mode.dart';
import '../models/search_tab.dart';
import 'search_results_list.dart';

/// Search page with:
///   - a search box (auto-searches after the user stops typing, see [kSearchInputDebounceDuration])
///   - one tab per [SearchTab] (the active tab decides which endpoint is searched)
///   - paginated results (infinite scroll OR a "Load more" button, see [LoadMoreMode])
///   - initial load with no query -> fetches the selected tab's endpoint without `search`
///   - tapping an audio plays it in the global player dock (see audio_player_service.dart)
///   - albums and playlists have an "add to queue" button (appends all their audios, the current track keeps
///     playing); tapping a playlist adds all its audios to the queue and starts with the first of them
///   - EDIT MODE: the pencil in the app bar toggles per-result edit / delete buttons
///       edit   -> pushes the edit page of the item (the list refreshes when you come back)
///       delete -> the button turns into a spinner while the request runs
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.loadMoreMode = LoadMoreMode.infiniteScroll, this.onResultTapped});

  final LoadMoreMode loadMoreMode;

  /// Called for every tapped result. (Audios additionally open the floating player.)
  final ValueChanged<WithId>? onResultTapped;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: SearchTab.values.length, vsync: this);
  final _searchTextController = TextEditingController();

  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      ref.read(musicSearchControllerProvider.notifier).selectTab(SearchTab.values[_tabController.index]);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchTextController.dispose();
    super.dispose();
  }

  Widget _buildSearchTextField(SearchTab selectedTab, MusicSearchController searchController) {
    return TextField(
      controller: _searchTextController,
      textInputAction: TextInputAction.search,
      onChanged: searchController.onSearchTextChanged,
      onSubmitted: searchController.submitSearchText,
      decoration: InputDecoration(
        hintText: 'Search ${selectedTab.displayLabel.toLowerCase()}',
        isDense: true,
        filled: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _searchTextController,
          builder: (context, textValue, child) => textValue.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchTextController.clear();
                    searchController.submitSearchText('');
                  },
                ),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userInfo = ref.watch(userInfoProvider).info;
    final selectedTab = ref.watch(musicSearchControllerProvider.select((state) => state.selectedTab));
    final isEditModeEnabled = ref.watch(musicSearchControllerProvider.select((state) => state.isEditModeEnabled));
    final searchController = ref.read(musicSearchControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: _buildSearchTextField(selectedTab, searchController),
        actions: userInfo?.role != 'admin'
            ? null
            : [
                _isRefreshing
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh),
                        selectedIcon: const Icon(Icons.check),
                        onPressed: () async {
                          setState(() {
                            _isRefreshing = true;
                          });

                          await ref.read(musicSearchControllerProvider.notifier).reloadFirstPage(selectedTab);
                          if (!mounted) return;

                          setState(() {
                            _isRefreshing = false;
                          });
                        },
                      ),
                IconButton(
                  tooltip: isEditModeEnabled ? 'Done' : 'Edit mode',
                  isSelected: isEditModeEnabled,
                  icon: const Icon(Icons.edit_outlined),
                  selectedIcon: const Icon(Icons.check),
                  onPressed: searchController.toggleEditMode,
                ),
              ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [for (final tab in SearchTab.values) Tab(text: tab.displayLabel)],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [for (final tab in SearchTab.values) SearchResultsList(tab: tab, loadMoreMode: widget.loadMoreMode, onResultTapped: widget.onResultTapped)],
      ),
    );
  }
}
