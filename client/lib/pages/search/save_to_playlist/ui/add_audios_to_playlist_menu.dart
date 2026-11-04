import 'dart:async';

import 'package:avarim/api/models/playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/save_to_playlist_actions.dart';
import 'create_playlist_dialog.dart';
import 'playlist_picker_dialog.dart';
import 'save_to_playlist_menu_choice.dart';

/// "Add to playlist" button for a list of audio ids: one audio of a result row, or the whole queue.
/// Same two choices as [AddAlbumToPlaylistMenu]: add them to an existing playlist, or save them as a new one.
class AddAudiosToPlaylistMenu extends ConsumerStatefulWidget {
  const AddAudiosToPlaylistMenu({
    super.key,
    required this.readAudioIds,
    this.suggestedPlaylistName = '',
    this.tooltip = 'Add to playlist',
    this.onPlaylistCreated,
  });

  /// Returns the audios to save. A function so that a changing list (the queue) is read when the user picks.
  final List<String> Function() readAudioIds;

  /// Suggested name of a new playlist.
  final String suggestedPlaylistName;
  final String tooltip;

  /// Called after a new playlist was created (e.g. to refresh a list of playlists).
  final VoidCallback? onPlaylistCreated;

  @override
  ConsumerState<AddAudiosToPlaylistMenu> createState() => _AddAudiosToPlaylistMenuState();
}

class _AddAudiosToPlaylistMenuState extends ConsumerState<AddAudiosToPlaylistMenu> {
  bool _isAddingToPlaylist = false;

  Future<void> _chooseExistingPlaylistAndAddAudios() async {
    final audioIds = widget.readAudioIds();
    final chosenPlaylist = await showDialog<Playlist>(context: context, builder: (_) => const PlaylistPickerDialog());
    if (chosenPlaylist == null || !mounted) return;

    setState(() => _isAddingToPlaylist = true);
    try {
      await ref.read(saveToPlaylistActionsProvider).addAudiosToPlaylist(audioIds, chosenPlaylist);
    } finally {
      if (mounted) setState(() => _isAddingToPlaylist = false);
    }
  }

  Future<void> _askForNameAndSaveAudiosAsNewPlaylist() async {
    final saveToPlaylistActions = ref.read(saveToPlaylistActionsProvider);
    final audioIds = widget.readAudioIds();

    final wasPlaylistCreated = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // the request may be running
      builder: (_) => CreatePlaylistDialog(
        suggestedPlaylistName: widget.suggestedPlaylistName,
        onSubmitPlaylistName: (playlistName) => saveToPlaylistActions.saveAudiosAsNewPlaylist(audioIds, playlistName),
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
      tooltip: widget.tooltip,
      icon: const Icon(Icons.library_add_outlined),
      onSelected: (choice) {
        switch (choice) {
          case SaveToPlaylistMenuChoice.addToExistingPlaylist:
            unawaited(_chooseExistingPlaylistAndAddAudios());
          case SaveToPlaylistMenuChoice.saveAsNewPlaylist:
            unawaited(_askForNameAndSaveAudiosAsNewPlaylist());
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: SaveToPlaylistMenuChoice.addToExistingPlaylist, child: Text('Add to a playlist')),
        PopupMenuItem(value: SaveToPlaylistMenuChoice.saveAsNewPlaylist, child: Text('Save as a new playlist')),
      ],
    );
  }
}
