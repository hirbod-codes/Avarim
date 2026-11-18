import 'package:avarim/api/models/album.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/core/core.dart';
import 'package:avarim/pages/search/save_to_playlist/ui/save_audios_as_new_playlist_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/music_search_api.dart';
import '../artists_subtitles.dart';
import '../authenticated_thumbnail.dart';
import '../popups/entity_popups.dart';
import 'add_to_queue_button.dart';
import 'item_actions.dart';

/// A list row for an [Album]: tap lists its audios in a popup, the play button replaces the player queue with them,
/// the trailing button appends them. In edit mode it has edit / delete buttons (deleting an album deletes its audios too).
class AlbumListItem extends ConsumerStatefulWidget {
  const AlbumListItem({super.key, required this.album, this.onTap, this.isEditMode = false, this.onDeleted});

  final Album album;

  /// Called on tap, before the album's audios open.
  final VoidCallback? onTap;

  /// Shows edit / delete buttons.
  final bool isEditMode;

  /// Called with the id of everything that was deleted: each audio of the album, then the album itself.
  final ValueChanged<String>? onDeleted;

  @override
  ConsumerState<AlbumListItem> createState() => _AlbumListItemState();
}

class _AlbumListItemState extends ConsumerState<AlbumListItem> {
  bool _isAddingToQueue = false;
  bool _isDeleting = false;

  Future<void> _showAudios() async {
    widget.onTap?.call();

    showAlbumAudiosPopup(context, ref, widget.album, widget.isEditMode, onDeleted: widget.onDeleted);
  }

  Future<void> _queueAudios({required bool replaceQueue, required bool playImmediately}) async {
    if (_isAddingToQueue) return;
    setState(() => _isAddingToQueue = true);

    final api = ref.read(musicSearchApiProvider);
    await queueAudios(fetchAudios: () => api.fetchAllAudiosOfAlbum(widget.album.id), replaceQueue: replaceQueue, playImmediately: playImmediately);

    if (mounted) setState(() => _isAddingToQueue = false);
  }

  Future<void> _delete() async {
    setState(() => _isDeleting = true);

    await onDeleteAlbum(context, ref, widget.album, onDeleted: widget.onDeleted);

    if (mounted) setState(() => _isDeleting = false);
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.album;

    return ListTile(
      onTap: _showAudios,
      leading: FittedBox(
        child: LeadingWithAction(
          onAction: () => _queueAudios(replaceQueue: true, playImmediately: true),
          child: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/album/avatar/${album.id}', placeholderIcon: Icons.album),
        ),
      ),
      title: SingleLineText(album.name),
      // an album's artists are resolved from its links (they aren't part of the album document)
      subtitle: AlbumArtistsSubtitle(albumId: album.id),
      trailing: widget.isEditMode
          ? EditDeleteActions(isBusy: _isDeleting, onEdit: () => showEditPopup(album), onDelete: _delete)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SaveAudiosAsNewPlaylistButton(
                  readAudioIds: () async {
                    final api = ref.read(musicSearchApiProvider);
                    final audios = await api.fetchAllAudiosOfAlbum(widget.album.id);
                    if (audios == null) return null;

                    return audios.map((m) => m.id).toList();
                  },
                ),
                AddToQueueButton(isBusy: _isAddingToQueue, onPressed: () => _queueAudios(replaceQueue: false, playImmediately: false)),
              ],
            ),
    );
  }
}
