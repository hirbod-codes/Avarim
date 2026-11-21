import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:flutter/material.dart';

/// Asks "Delete this ...?" for [item]. Completes with true only when the user confirmed.
Future<bool> showDeleteConfirmationDialog(BuildContext context, {WithId? item}) async {
  final (dialogTitle, dialogBody) = switch (item) {
    Artist artist => (
      'Delete artist?',
      '"${artist.name}" will be permanently deleted. An artist that still has albums or audios can\'t be deleted: delete them or move them to another artist first.',
    ),
    Album album => ('Delete album?', '"${album.name}" will be permanently deleted. Its audios are kept.'),
    Audio audio => ('Delete audio?', '"${audio.title}" will be permanently deleted.'),
    Playlist playlist => ('Delete audio?', '"${playlist.name}" will be permanently deleted.'),
    _ => ('Delete?', 'It will be permanently deleted.'),
  };

  final wasConfirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(dialogTitle),
      content: Text(dialogBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
      ],
    ),
  );

  return wasConfirmed == true;
}

/// Second confirmation when deleting an album: all of its audios are deleted too. Completes with true only when confirmed.
Future<bool> showDeleteAllAudiosOfAlbumDialog(BuildContext context, {required Album album}) async {
  final wasConfirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);

      return AlertDialog(
        title: const Text('Delete all audios?'),
        content: Text(
          'Every audio of "${album.name}" will be deleted, one by one. '
          'They disappear from every album, artist and playlist they are in. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete all'),
          ),
        ],
      );
    },
  );

  return wasConfirmed == true;
}
