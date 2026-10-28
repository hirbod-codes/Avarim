// audio_row_actions.dart
//
// The two icon buttons at the end of an audio row (search results, an artist's singles, ...):
//   - "Add to queue":    appends the audio to the player queue, the current track keeps playing
//   - "Add to playlist": add it to an existing playlist, or save it as a new one (AudioPlaylistMenu)

import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/pages/search/album_playlist_menu.dart';
import 'package:flutter/material.dart';

class AudioRowActions extends StatelessWidget {
  const AudioRowActions({super.key, required this.audioId, this.initialPlaylistName = ''});

  final String audioId;

  /// Suggested name when the audio is saved as a new playlist (e.g. its title).
  final String initialPlaylistName;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Add to queue',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.playlist_add),
          onPressed: () {
            // The player is global, so this keeps working even if the page is left.
            AudioPlayerService.add(audioId: audioId, play: false);
            NotificationService.showSuccess(message: 'Added 1 audio to the queue');
          },
        ),
        AudioPlaylistMenu(audioIds: () => [audioId], initialName: initialPlaylistName),
      ],
    );
  }
}
