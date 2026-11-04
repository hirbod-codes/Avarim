import 'dart:async';

import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/save_to_playlist_actions.dart';
import 'create_playlist_dialog.dart';
import 'playlist_picker_dialog.dart';
import 'save_to_playlist_menu_choice.dart';

/// "Save to playlist" button for an album (put it next to the search page):
///
///   - Add to a playlist…        pick one of the playlists; the album's audios that aren't in it yet are added
///   - Save as a new playlist…   ask for a name, create the playlist, add all of the album's audios to it
class AddAlbumToPlaylistMenu extends ConsumerStatefulWidget {
  const AddAlbumToPlaylistMenu({super.key, required this.album, this.onPlaylistCreated});

  final Album album;

  /// Called after a new playlist was created (e.g. to refresh a list of playlists).
  final VoidCallback? onPlaylistCreated;

  @override
  ConsumerState<AddAlbumToPlaylistMenu> createState() => _AddAlbumToPlaylistMenuState();
}

class _AddAlbumToPlaylistMenuState extends ConsumerState<AddAlbumToPlaylistMenu> {
  bool _isAddingToPlaylist = false;

  Future<void> _chooseExistingPlaylistAndAddAlbum() async {
    final chosenPlaylist = await showDialog<Playlist>(context: context, builder: (_) => const PlaylistPickerDialog());
    if (chosenPlaylist == null || !mounted) return;

    setState(() => _isAddingToPlaylist = true);
    try {
      await ref.read(saveToPlaylistActionsProvider).addAlbumAudiosToPlaylist(widget.album, chosenPlaylist);
    } finally {
      if (mounted) setState(() => _isAddingToPlaylist = false);
    }
  }

  Future<void> _askForNameAndSaveAlbumAsNewPlaylist() async {
    final saveToPlaylistActions = ref.read(saveToPlaylistActionsProvider);
    final album = widget.album;

    final wasPlaylistCreated = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // the request may be running
      builder: (_) => CreatePlaylistDialog(
        suggestedPlaylistName: album.name,
        onSubmitPlaylistName: (playlistName) => saveToPlaylistActions.saveAlbumAsNewPlaylist(album, playlistName),
      ),
    );
    if (wasPlaylistCreated == true) widget.onPlaylistCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isAddingToPlaylist) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return PopupMenuButton<SaveToPlaylistMenuChoice>(
      tooltip: 'Save to playlist',
      icon: const Icon(Icons.library_add_outlined),
      onSelected: (choice) {
        switch (choice) {
          case SaveToPlaylistMenuChoice.addToExistingPlaylist:
            unawaited(_chooseExistingPlaylistAndAddAlbum());
          case SaveToPlaylistMenuChoice.saveAsNewPlaylist:
            unawaited(_askForNameAndSaveAlbumAsNewPlaylist());
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: SaveToPlaylistMenuChoice.addToExistingPlaylist, child: Text('Add to a playlist…')),
        PopupMenuItem(value: SaveToPlaylistMenuChoice.saveAsNewPlaylist, child: Text('Save as a new playlist…')),
      ],
    );
  }
}
