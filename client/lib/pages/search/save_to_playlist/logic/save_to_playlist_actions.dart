import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/save_to_playlist_api.dart';

/// What the menus do once the user has chosen: fetch the audios, talk to the API and tell the user the outcome.
class SaveToPlaylistActions {
  SaveToPlaylistActions(this._api);

  final SaveToPlaylistApi _api;

  // ── Adding to an existing playlist ─────────────────────────────────────────

  /// Adds the album's audios that aren't in [playlist] yet. The outcome is shown as a toast.
  Future<void> addAlbumAudiosToPlaylist(Album album, Playlist playlist) async {
    final albumAudioIds = await _api.fetchAllAudioIdsOfAlbum(album.id);
    if (albumAudioIds == null) return; // a request failed and its error was already shown

    await addAudiosToPlaylist(albumAudioIds, playlist, emptyListMessage: 'This album has no audios');
  }

  /// Adds the audios in [audioIds] that aren't in [playlist] yet. The outcome is shown as a toast.
  Future<void> addAudiosToPlaylist(
    List<String> audioIds,
    Playlist playlist, {
    String emptyListMessage = 'There are no audios to add',
  }) async {
    if (audioIds.isEmpty) {
      NotificationService.showError(message: emptyListMessage);
      return;
    }

    final audioIdsAlreadyInPlaylist = await _api.fetchAllAudioIdsOfPlaylist(playlist.id);
    if (audioIdsAlreadyInPlaylist == null) return; // a request failed and its error was already shown

    final alreadyInPlaylist = audioIdsAlreadyInPlaylist.toSet();
    final requestedAudioIds = audioIds.toSet().toList(); // no duplicates, order kept
    final audioIdsToAdd = [
      for (final audioId in requestedAudioIds)
        if (!alreadyInPlaylist.contains(audioId)) audioId,
    ];

    if (audioIdsToAdd.isEmpty) {
      NotificationService.showSuccess(
        message: requestedAudioIds.length == 1
            ? 'It is already in "${playlist.name}"'
            : 'All of the audios are already in "${playlist.name}"',
      );
      return;
    }

    final addedCount = await _api.addAudiosToPlaylist(playlist.id, audioIdsToAdd);
    _showAddResultNotification(
      playlistName: playlist.name,
      addedCount: addedCount,
      requestedCount: audioIdsToAdd.length,
      alreadyInPlaylistCount: requestedAudioIds.length - audioIdsToAdd.length,
    );
  }

  // ── Saving as a new playlist ───────────────────────────────────────────────

  /// Creates a playlist called [playlistName] with all of the album's audios.
  ///
  /// Returns an error text for the dialog when NOTHING was created (the user can fix it and retry), or null
  /// when the playlist exists. If adding some audios failed after that, a toast says so.
  Future<String?> saveAlbumAsNewPlaylist(Album album, String playlistName) async {
    final albumAudioIds = await _api.fetchAllAudioIdsOfAlbum(album.id);
    if (albumAudioIds == null) return "Couldn't load the album's audios.";
    if (albumAudioIds.isEmpty) return 'This album has no audios.';

    return saveAudiosAsNewPlaylist(albumAudioIds, playlistName);
  }

  /// Creates a playlist called [playlistName] with [audioIds] (same result convention as [saveAlbumAsNewPlaylist]).
  Future<String?> saveAudiosAsNewPlaylist(List<String> audioIds, String playlistName) async {
    final uniqueAudioIds = audioIds.toSet().toList();
    if (uniqueAudioIds.isEmpty) return 'There are no audios to save.';

    final createPlaylistResult = await _api.createPlaylist(playlistName);
    if (createPlaylistResult case ApiCallFailure(message: final failureMessage)) return failureMessage;

    final createdPlaylistId = createPlaylistResult.dataOrNull;
    if (createdPlaylistId == null) {
      NotificationService.showError(message: 'Playlist "$playlistName" was created, but its audios could not be added');
      return null;
    }

    final addedCount = await _api.addAudiosToPlaylist(createdPlaylistId, uniqueAudioIds);
    _showAddResultNotification(playlistName: playlistName, addedCount: addedCount, requestedCount: uniqueAudioIds.length);
    return null;
  }

  // ── Notifications ──────────────────────────────────────────────────────────

  void _showAddResultNotification({
    required String playlistName,
    required int addedCount,
    required int requestedCount,
    int alreadyInPlaylistCount = 0,
  }) {
    if (addedCount == requestedCount) {
      final alreadyThereSuffix = alreadyInPlaylistCount > 0 ? ' ($alreadyInPlaylistCount already there)' : '';
      NotificationService.showSuccess(message: 'Added ${_formatAudioCount(addedCount)} to "$playlistName"$alreadyThereSuffix');
    } else if (addedCount == 0) {
      NotificationService.showError(message: 'No audios were added to "$playlistName"');
    } else {
      NotificationService.showError(message: 'Only $addedCount of $requestedCount audios were added to "$playlistName"');
    }
  }

  String _formatAudioCount(int count) => count == 1 ? '1 audio' : '$count audios';
}

final saveToPlaylistActionsProvider = Provider<SaveToPlaylistActions>(
  (ref) => SaveToPlaylistActions(ref.watch(saveToPlaylistApiProvider)),
);
