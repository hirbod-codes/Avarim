// edit_album_notifier.dart
//
// Logic of the edit album page: create (when no id was given), load by id, save the name.

import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/common/edit_errors.dart';
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

    final String id;
    try {
      id = await _api.create(name: name);
    } catch (e) {
      talker.error('creating album failed', e);
      if (ref.mounted) state = state.copyWith(isCreating: false);
      NotificationService.showError(message: describeError(e));
      return;
    }
    if (!ref.mounted) return;

    await open(id);
  }

  /// Loads the album [albumId] and shows the editor.
  Future<void> open(String albumId) async {
    _token?.cancel();
    final token = _token = CancelToken();
    _id = albumId;
    state = EditAlbumState(id: albumId);

    try {
      final album = await _api.getInfo(albumId, cancelToken: token);
      if (!ref.mounted || token.isCancelled) return;
      state = state.copyWith(phase: EditAlbumPhase.editing, album: album);
    } catch (e) {
      if (!ref.mounted || isCancel(e)) return;
      talker.error('loading album failed', e);
      state = state.copyWith(phase: EditAlbumPhase.failed, error: describeError(e));
    }
  }

  /// "Try again" after a failed load.
  Future<void> retry() {
    final id = _id;
    if (id == null) return Future.value();
    return open(id);
  }

  /// Sends the new name. Returns true on success.
  Future<bool> save({required String name}) async {
    final album = state.album;
    final id = _id;
    if (album == null || id == null || state.isSaving) return false;

    state = state.copyWith(isSaving: true);
    try {
      await _api.update(albumId: id, name: name);
      if (!ref.mounted) return true;

      state = state.copyWith(isSaving: false, revision: state.revision + 1, album: {...album, 'name': name});
      return true;
    } catch (e) {
      talker.error('updating album failed', e);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      NotificationService.showError(message: describeError(e));
      return false;
    }
  }
}

/// autoDispose: leaving the page drops the loaded album.
final editAlbumProvider = NotifierProvider.autoDispose<EditAlbumNotifier, EditAlbumState>(EditAlbumNotifier.new);
