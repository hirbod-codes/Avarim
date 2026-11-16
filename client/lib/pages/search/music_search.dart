// Music search feature.
//
//   - search box + one tab per SearchTab (artists / albums / audios / audios without an artist / playlists)
//   - paginated results (infinite scroll or a "Load more" button), see LoadMoreMode
//   - tap an audio to play it, add albums / playlists to the player queue
//   - edit mode with per-item edit / delete buttons
//
// pubspec.yaml:
//   flutter_riverpod: ^3.0.0   (only to reach the API provider and the user info; there are no controllers)
//   dio: ^5.4.0
//   go_router
//
// Folder layout:
//   music_search_config.dart       tunable constants (debounce, page sizes, routes)
//   models/search_tab.dart         the tabs and the endpoint each one searches
//   data/music_search_api.dart     HTTP calls (see the endpoint list at the top of that file)
//   ui/search_page.dart            the page: search field, tabs, list; owns the open tab, the query and the paging
//   ui/items/                      one row widget per kind of result; each handles its own actions and spinners
//   ui/popups/, ui/*.dart          popup helper, delete dialogs, thumbnails, subtitles
//
// Generic parts (paged list, debounced search field, tab scaffold, small widgets) live in lib/components/core
// and know nothing about music.
//
// Import this file from outside the feature; it exposes only what other code needs.

export 'models/load_more_mode.dart';
export 'models/search_tab.dart';
export 'ui/authenticated_thumbnail.dart';
export 'ui/items/items.dart';
export 'ui/search_page.dart';
