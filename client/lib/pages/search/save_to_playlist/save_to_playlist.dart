// "Save to playlist" feature.
//
//   - AddAlbumToPlaylistMenu          button for an album: add it to a playlist, or save it as a new playlist
//   - AddAudiosToPlaylistMenu         the same two choices for any list of audio ids (one result row, the queue)
//   - SaveAudiosAsNewPlaylistButton   one button that only saves a list of audios as a NEW playlist
//   - PlaylistPickerDialog / CreatePlaylistDialog   the dialogs the menus open
//
// Backend (playlist routes):
//   GET  /api/playlist?page&pageSize&search                       playlists (for the picker)
//   POST /api/playlist  { name }                                  create -> { playlistId }
//   GET  /api/playlist/audio?playlistId=&page&pageSize            audios already in a playlist
//   GET  /api/relationship/album/audio?albumId=&page&pageSize     the album's audios
//   POST /api/playlist/audio  { playlistId, audioIds }            add audios (in chunks, JSON body)
//
// The backend doesn't reject duplicates, so adding to an existing playlist first looks up what is
// already in it and only sends the rest.
//
// Folder layout:
//   save_to_playlist_config.dart          page sizes and chunk size
//   data/save_to_playlist_api.dart        HTTP calls
//   logic/save_to_playlist_actions.dart   what happens after the user chose (fetch ids, call the API, show a toast)
//   ui/                                   the buttons and dialogs
//
// Import this file from outside the feature; it exposes only what other code needs.

export 'ui/add_album_to_playlist_menu.dart';
export 'ui/add_audios_to_playlist_menu.dart';
export 'ui/create_playlist_dialog.dart';
export 'ui/playlist_picker_dialog.dart';
export 'ui/save_audios_as_new_playlist_button.dart';
