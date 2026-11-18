import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/music_search_api.dart';
import '../../music_search_config.dart';
import '../delete_confirmation_dialog.dart';

Future<void> onDeleteAudio(BuildContext context, WidgetRef ref, Audio audio, {Function(String id)? onDeleted}) async {
  if (!await confirmDelete(context, audio)) return;

  final wasDeleted = await deleteAudio(ref.read(musicSearchApiProvider), audio.id);
  if (wasDeleted) onDeleted?.call(audio.id);
}

Future<void> onDeleteArtist(BuildContext context, WidgetRef ref, Artist artist, {Function(String id)? onDeleted}) async {
  if (!await confirmDelete(context, artist)) return;

  final wasDeleted = await deleteArtist(ref.read(musicSearchApiProvider), artist.id);
  if (wasDeleted) onDeleted?.call(artist.id);
}

Future<void> onDeleteAlbum(BuildContext context, WidgetRef ref, Album album, {bool deleteAllAudio = true, Function(String id)? onDeleted}) async {
  if (!await confirmDelete(context, album)) return;
  if (!context.mounted) return;

  final api = ref.read(musicSearchApiProvider);

  if (await deleteAlbum(api, album.id, deleteAllAudio: deleteAllAudio)) onDeleted?.call(album.id);
}

Future<void> onDeletePlaylist(BuildContext context, WidgetRef ref, Playlist playlist, {Function(String id)? onDeleted}) async {
  if (!await confirmDelete(context, playlist)) return;
  if (!context.mounted) return;

  final api = ref.read(musicSearchApiProvider);

  if (await deletePlaylist(api, playlist.id)) onDeleted?.call(playlist.id);
}

// What the rows do besides showing themselves. Plain functions: no state, so any row can use them.
// Each tells the user why it failed, so callers only need the returned bool.

/// True if the user may go on: no confirmation is configured ([kShouldConfirmBeforeDelete]) or they confirmed.
Future<bool> confirmDelete(BuildContext context, WithId item) async {
  if (!kShouldConfirmBeforeDelete) return true;
  return showDeleteConfirmationDialog(context, item: item);
}

/// Puts the audios from [fetchAudioIds] in the player queue (see AudioPlayerService):
///  - [replaceQueue]: they replace the queue, otherwise they are appended
///  - [playImmediately]: the first of them starts playing right away, otherwise the current track keeps playing
/// The player is global, so this works even if the user already left the page.
Future<void> queueAudios({required Future<List<Audio>?> Function() fetchAudios, required bool replaceQueue, required bool playImmediately}) async {
  List<Audio>? audios;
  try {
    audios = await fetchAudios();
  } catch (error, stackTrace) {
    talker.error('fetching the audios to queue failed', error, stackTrace);
  }

  // null: a request failed and its error was already shown.
  if (audios == null) return;

  if (audios.isEmpty) {
    NotificationService.showError(message: 'There are no audios to add');
    return;
  }
  final List<String> audioIds = audios.map((m) => m.id).toList();

  if (replaceQueue) {
    AudioPlayerService.replace(audioIds: audioIds, play: playImmediately);
  } else {
    AudioPlayerService.add(audioIds: audioIds, play: playImmediately);
  }
  if (!playImmediately) {
    NotificationService.showSuccess(message: audios.length == 1 ? 'Added 1 audio to the queue' : 'Added ${audios.length} audios to the queue');
  }
}

/// Deletes an audio, and drops it from the player queue.
Future<bool> deleteAudio(MusicSearchApi api, String audioId) async {
  var wasDeleted = false;
  try {
    wasDeleted = await api.deleteAudioById(audioId);
  } catch (error, stackTrace) {
    talker.error('deleting audio failed', error, stackTrace);
  }

  if (!wasDeleted) {
    NotificationService.showError(message: 'Could not delete the audio');
    return false;
  }

  // No-op if it isn't queued; closes the dock if it was the last track.
  AudioPlayerService.remove(audioId);
  return true;
}

/// Deletes an artist. One that still has albums or audios can't go; the message says so.
Future<bool> deleteArtist(MusicSearchApi api, String artistId) async {
  ApiCallResult<dynamic>? result;
  try {
    result = await api.deleteArtistById(artistId);
  } catch (error, stackTrace) {
    talker.error('deleting artist failed', error, stackTrace);
  }
  if (result != null && result.isSuccess) return true;

  final artistStillHasAlbumsOrAudios = switch (result) {
    ApiCallFailure(:final errorCode) => errorCode == 'UNRESOLVED_ALBUMS_AUDIOS',
    _ => false,
  };
  NotificationService.showError(
    message: artistStillHasAlbumsOrAudios
        ? 'This artist still has albums or audios. Delete them or move them to another artist first.'
        : 'Could not delete the artist',
  );
  return false;
}

/// Deletes an album (not its audios).
Future<bool> deleteAlbum(MusicSearchApi api, String albumId, {bool deleteAllAudio = false}) async {
  ApiCallResult<dynamic>? result;
  try {
    result = await api.deleteAlbumById(albumId, deleteAllAudio: deleteAllAudio);
  } catch (error, stackTrace) {
    talker.error('deleting album failed', error, stackTrace);
  }
  if (result != null && result.isSuccess) return true;

  NotificationService.showError(message: 'Could not delete the album');
  return false;
}

/// Deletes an album (not its audios).
Future<bool> deletePlaylist(MusicSearchApi api, String albumId) async {
  ApiCallResult<dynamic>? result;
  try {
    result = await api.deletePlaylistById(albumId);
  } catch (error, stackTrace) {
    talker.error('deleting album failed', error, stackTrace);
  }
  if (result != null && result.isSuccess) return true;

  NotificationService.showError(message: 'Could not delete the album');
  return false;
}
