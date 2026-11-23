import 'dart:async';

import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:avarim/pages/search/ui/popups/entity_popups.dart';
import 'package:flutter/material.dart';

/// Asks "Delete this ...?" for [item]. Completes with true only when the user confirmed.
///
Future<bool> showDeleteConfirmationDialog({WithId? item, List<Widget>? leadings, BoxConstraints? constraints, Function? onClose}) async {
  final (dialogTitle, dialogBody) = switch (item) {
    Artist artist => (
      'Delete artist?',
      '"${artist.name}" will be permanently deleted. An artist that still has albums or audios can\'t be deleted: delete them or move them to another artist first.',
    ),
    Album album => ('Delete album?', '"${album.name}" will be permanently deleted.'),
    Audio audio => ('Delete audio?', '"${audio.title}" will be permanently deleted.'),
    Playlist playlist => ('Delete audio?', '"${playlist.name}" will be permanently deleted.'),
    _ => ('Delete?', 'It will be permanently deleted.'),
  };

  final completer = Completer<bool>();
  bool result = false;

  void close() {
    onClose?.call();
    completer.complete(result); // the awaiting caller continues here
  }

  showEntity(
    builder: (onEntityClose) =>
        (c) => AlertDialog(
          title: Text(dialogTitle),
          content: Text(dialogBody),
          actions: [
            TextButton(
              onPressed: () {
                if (completer.isCompleted) return;
                onEntityClose();
                close();
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (completer.isCompleted) return;
                onEntityClose();
                result = true;
                close();
              },
              child: const Text('Delete'),
            ),
          ],
        ),
  );

  return await completer.future;
}

/// Second confirmation when deleting an album: all of its audios are deleted too. Completes with true only when confirmed.
Future<bool> showDeleteAllAudiosOfAlbumDialog({required Album album, List<Widget>? leadings, BoxConstraints? constraints, Function? onClose}) async {
  final completer = Completer<bool>();
  bool result = false;

  void close() {
    onClose?.call();
    completer.complete(result); // the awaiting caller continues here
  }

  showEntity(
    builder: (onEntityClose) => (c) {
      final theme = Theme.of(c);

      return AlertDialog(
        title: const Text('Delete all audios?'),
        content: Text(
          'Every audio of "${album.name}" will be deleted, one by one. '
          'They disappear from every album, artist and playlist they are in. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (completer.isCompleted) return;
              onEntityClose();
              close();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError),
            onPressed: () {
              if (completer.isCompleted) return;
              onEntityClose();
              result = true;
              close();
            },
            child: const Text('Delete all'),
          ),
        ],
      );
    },
  );

  return await completer.future;
}
