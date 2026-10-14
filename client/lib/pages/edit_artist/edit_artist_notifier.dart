// edit_artist_notifier.dart
//
// Logic of the edit artist page: create (when no id was given), load by id, save the name.

import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/common/edit_errors.dart';
import 'package:avarim/pages/edit_artist/edit_artist_api.dart';
import 'package:avarim/pages/edit_artist/edit_artist_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditArtistNotifier extends Notifier<EditArtistState> {
  CancelToken? _token;
  String? _id;

  ArtistApi get _api => ref.read(artistApiProvider);

  @override
  EditArtistState build() {
    ref.onDispose(() => _token?.cancel());
    return const EditArtistState();
  }

  /// Creates an artist called [name], then continues with the id the server returned
  /// (loads it and shows the editor).
  Future<void> create(String name) async {
    if (state.isCreating) return;
    state = state.copyWith(isCreating: true);

    final String id;
    try {
      id = await _api.create(name: name);
    } catch (e) {
      talker.error('creating artist failed', e);
      if (ref.mounted) state = state.copyWith(isCreating: false);
      NotificationService.showError(message: describeError(e));
      return;
    }
    if (!ref.mounted) return;

    await open(id);
  }

  /// Loads the artist [artistId] and shows the editor.
  Future<void> open(String artistId) async {
    _token?.cancel();
    final token = _token = CancelToken();
    _id = artistId;
    state = EditArtistState(id: artistId);

    try {
      final artist = await _api.getInfo(artistId, cancelToken: token);
      if (!ref.mounted || token.isCancelled) return;
      state = state.copyWith(phase: EditArtistPhase.editing, artist: artist);
    } catch (e) {
      if (!ref.mounted || isCancel(e)) return;
      talker.error('loading artist failed', e);
      state = state.copyWith(phase: EditArtistPhase.failed, error: describeError(e));
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
    final artist = state.artist;
    final id = _id;
    if (artist == null || id == null || state.isSaving) return false;

    state = state.copyWith(isSaving: true);
    try {
      await _api.update(artistId: id, name: name);
      if (!ref.mounted) return true;

      state = state.copyWith(isSaving: false, revision: state.revision + 1, artist: {...artist, 'name': name});
      return true;
    } catch (e) {
      talker.error('updating artist failed', e);
      if (ref.mounted) state = state.copyWith(isSaving: false);
      NotificationService.showError(message: describeError(e));
      return false;
    }
  }
}

/// autoDispose: leaving the page drops the loaded artist.
final editArtistProvider = NotifierProvider.autoDispose<EditArtistNotifier, EditArtistState>(EditArtistNotifier.new);
