// Music search feature.
//
//   - search box + one tab per SearchTab (artists / albums / audios / audios without an artist / playlists)
//   - paginated results (infinite scroll or a "Load more" button), see LoadMoreMode
//   - tap an audio to play it, add albums / playlists to the player queue
//   - edit mode with per-item edit / delete buttons
//
// pubspec.yaml:
//   flutter_riverpod: ^3.0.0   (plain Notifier API, no code-gen needed)
//   dio: ^5.4.0
//   go_router
//
// Folder layout:
//   music_search_config.dart             tunable constants (debounce, page sizes, routes)
//   models/                              SearchTab, LoadMoreMode, SearchTabResults, MusicSearchState
//   data/music_search_api.dart           HTTP calls (see the endpoint list at the top of that file)
//   controller/music_search_controller   Riverpod notifier: searching, paging, queueing, deleting
//   ui/                                  SearchPage and the widgets it is built from
//
// Import this file from outside the feature; it exposes only what other code needs.

export 'models/load_more_mode.dart';
export 'models/search_tab.dart';
export 'ui/authenticated_thumbnail.dart';
export 'ui/search_page.dart';
