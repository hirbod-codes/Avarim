// Reusable building blocks (no feature code in here). Import this file, or the individual files.
//
//   lists/     ScrollableList (infinite scroll / load-more button / pull-to-refresh), LoadMoreMode
//   paged/     PagedState (data), PagedListView (shows a PagedState)
//   search/    DebouncedSearchField
//   tabs/      TabBarScaffold
//   widgets/   small pieces: spinner, busy/async icon buttons, edit+delete actions, list footer, status message, ...
//
// Everything here is presentational: no controllers, no Riverpod.

export 'lists/load_more_mode.dart';
export 'lists/scrollable_list.dart';
export 'paged/paged_list_view.dart';
export 'paged/paged_state.dart';
export 'search/debounced_search_field.dart';
export 'tabs/tab_bar_scaffold.dart';
export 'widgets/async_icon_button.dart';
export 'widgets/busy_icon_button.dart';
export 'widgets/edit_delete_actions.dart';
export 'widgets/inline_spinner.dart';
export 'widgets/leading_with_action.dart';
export 'widgets/list_footer.dart';
export 'widgets/single_line_text.dart';
export 'widgets/status_message.dart';
export './auto_scroll_box.dart';
export './relative_box.dart';
