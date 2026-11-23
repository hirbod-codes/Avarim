import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/api/root_navigator_key.dart';
import 'package:avarim/components/core/paged/self_managed_paged_list_view.dart';
import 'package:avarim/components/popup.dart';
import 'package:avarim/pages/edit_album/edit_album_page.dart';
import 'package:avarim/pages/edit_artist/edit_artist_page.dart';
import 'package:avarim/pages/edit_audio/edit_audio_page.dart';
import 'package:avarim/pages/search/data/music_search_api.dart';
import 'package:avarim/pages/search/music_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showAlbumAudiosPopup(BuildContext context, WidgetRef ref, Album album, bool isEditMode, {ValueChanged<String>? onDeleted}) async {
  showEntityPopup(
    leadings: [
      const Icon(Icons.album),
      Builder(builder: (context) => Text(album.name, style: Theme.of(context).textTheme.titleMedium)),
    ],
    child: SelfManagedPagedListView<Audio>(
      loadPage: (int page) {
        return ref.read(musicSearchApiProvider).fetchAudiosOfAlbum(album.id, page);
      },
      itemBuilder: (context, item, _) => AudioListItem(key: ValueKey(item.id), audio: item, isEditMode: isEditMode, onDeleted: onDeleted),
    ),
  );
}

Future<void> showPlaylistAudiosPopup(
  BuildContext context,
  WidgetRef ref,
  Playlist playlist,
  bool isEditMode, {
  Function? onClose,
  ValueChanged<String>? onDeleted,
  BoxConstraints? constraints,
}) async {
  showEntityPopup(
    constraints: constraints,
    onClose: onClose,
    leadings: [
      const Icon(Icons.playlist_play),
      Builder(builder: (context) => Text(playlist.name, style: Theme.of(context).textTheme.titleMedium)),
    ],
    child: SelfManagedPagedListView<Audio>(
      loadPage: (int page) {
        return ref.read(musicSearchApiProvider).fetchAudiosOfPlaylist(playlist.id, page);
      },
      itemBuilder: (context, item, _) => AudioListItem(key: ValueKey(item.id), audio: item, isEditMode: isEditMode, onDeleted: onDeleted),
    ),
  );
}

void showEntity({required WidgetBuilder Function(Function onCLose) builder, Function? onClose}) {
  final overlay = rootNavigatorKey.currentState?.overlay;
  if (overlay == null) return;

  late final OverlayEntry entry;
  entry = OverlayEntry(builder: builder(() => entry.remove()));
  overlay.insert(entry);
}

/// Shows [child] in a [Popup] on the root overlay (above the whole app). The popup removes itself when closed.
void showEntityPopup({List<Widget>? leadings, required Widget child, BoxConstraints? constraints, Function? onClose}) {
  showEntity(
    builder: (onEntityClose) =>
        (context) => Popup(
          constraints: constraints ?? const BoxConstraints(maxWidth: 1000),
          leadings: leadings,
          onClose: () {
            onEntityClose();
            onClose?.call();
          },
          child: child,
        ),
  );
}

/// Opens the edit page of an audio / artist / album in a popup. Does nothing for other kinds of items.
void showEditPopup(WithId item) {
  switch (item) {
    case Audio audio:
      showEntityPopup(
        leadings: [Text(audio.title)],
        child: EditAudioPage(audioId: audio.id),
      );
    case Artist artist:
      showEntityPopup(
        leadings: [Text(artist.name)],
        child: EditArtistPage(artistId: artist.id),
      );
    case Album album:
      showEntityPopup(
        leadings: [Text(album.name)],
        child: EditAlbumPage(albumId: album.id),
      );
    default:
      break;
  }
}
