// edit_album_notifier.dart
//
// Logic of the edit album page: create (when no id was given), load by id, save the name.
//
// The API methods return ApiCallResult. A failure there was already shown to the user as a
// toast (the load is silent on purpose and shown on the page), so nothing here toasts it again.

import 'package:avarim/api/api_call.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/pages/edit_album/edit_album_api.dart';
import 'package:avarim/pages/edit_album/edit_album_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditAlbumNotifier extends Notifier<EditAlbumState> {
  CancelToken? _token;
  String? _id;

  AlbumApi get _api => ref.read(albumApiProvider);

  @override
  EditAlbumState build() {
    ref.onDispose(() => _token?.cancel());
    return const EditAlbumState();
  }

  /// Creates an album called [name], then continues with the id the server returned
  /// (loads it and shows the editor).
  Future<void> create(String name) async {
    if (state.isCreating) return;
    state = state.copyWith(isCreating: true);

    final result = await _api.create(name: name);
    if (!ref.mounted) return;

    // On failure the error was already shown; stay on the create screen so the user can retry.
    if (result.isFailure) {
      state = state.copyWith(isCreating: false);
      return;
    }

    final id = extractAlbumId(result.dataOrNull);
    if (id == null) {
      state = state.copyWith(isCreating: false);
      NotificationService.showError(message: 'The server did not return the id of the new album.');
      return;
    }

    await open(id);
  }

  /// Loads the album [albumId] and shows the editor.
  Future<void> open(String albumId) async {
    _token?.cancel();
    final token = _token = CancelToken();
    _id = albumId;
    state = EditAlbumState(id: albumId);

    final result = await _api.getInfo(albumId, cancelToken: token);
    if (!ref.mounted || token.isCancelled) return;

    if (result case ApiCallFailure(:final message)) {
      state = state.copyWith(phase: EditAlbumPhase.failed, error: message);
      return;
    }

    final album = result.dataOrNull;
    if (album == null) {
      state = state.copyWith(phase: EditAlbumPhase.failed, error: 'The server did not return the album.');
      return;
    }
    state = state.copyWith(phase: EditAlbumPhase.editing, album: album);
  }

  /// "Try again" after a failed load.
  Future<void> retry() {
    final id = _id;
    if (id == null) return Future.value();
    return open(id);
  }

  /// Sends the new name. Returns true on success (on failure the error was already shown).
  Future<bool> save({required String name}) async {
    final album = state.album;
    final id = _id;
    if (album == null || id == null || state.isSaving) return false;

    state = state.copyWith(isSaving: true);
    final result = await _api.update(albumId: id, name: name);
    if (!ref.mounted) return !result.isFailure;

    if (result.isFailure) {
      state = state.copyWith(isSaving: false);
      return false;
    }

    state = state.copyWith(isSaving: false, revision: state.revision + 1, album: {...album, 'name': name});
    return true;
  }
}

/// autoDispose: leaving the page drops the loaded album.
final editAlbumProvider = NotifierProvider.autoDispose<EditAlbumNotifier, EditAlbumState>(EditAlbumNotifier.new);
