import 'package:avarim/components/global/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/save_to_playlist_actions.dart';
import 'create_playlist_dialog.dart';

/// An icon button that saves a list of audios (e.g. the player queue) as a NEW playlist: it asks for a name,
/// a taken name is reported inside the dialog so the user can pick another one, and a toast confirms the
/// result.
class SaveAudiosAsNewPlaylistButton extends ConsumerWidget {
  const SaveAudiosAsNewPlaylistButton({
    super.key,
    required this.readAudioIds,
    this.tooltip = 'Save as a playlist',
    this.suggestedPlaylistName = '',
    this.onPlaylistCreated,
  });

  /// Returns the audios to save. A function so that a changing list (the queue) is read when the button is pressed.
  final List<String> Function() readAudioIds;
  final String tooltip;

  /// Suggested name of the playlist.
  final String suggestedPlaylistName;

  /// Called after the playlist was created.
  final VoidCallback? onPlaylistCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.library_add_outlined),
      onPressed: () async {
        final audioIds = readAudioIds();
        if (audioIds.isEmpty) {
          NotificationService.showError(message: 'There are no audios to save');
          return;
        }

        final saveToPlaylistActions = ref.read(saveToPlaylistActionsProvider);
        final wasPlaylistCreated = await showDialog<bool>(
          context: context,
          barrierDismissible: false, // the request may be running
          builder: (_) => CreatePlaylistDialog(
            suggestedPlaylistName: suggestedPlaylistName,
            onSubmitPlaylistName: (playlistName) => saveToPlaylistActions.saveAudiosAsNewPlaylist(audioIds, playlistName),
          ),
        );
        if (wasPlaylistCreated == true) onPlaylistCreated?.call();
      },
    );
  }
}
