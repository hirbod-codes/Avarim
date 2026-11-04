import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/api/models/with_id.dart';
import 'package:flutter/material.dart';

/// Asks "Delete this ...?" for [item]. Completes with true only when the user confirmed.
Future<bool> showDeleteConfirmationDialog(BuildContext context, {required WithId item}) async {
  final (dialogTitle, dialogBody) = switch (item) {
    Artist artist => (
      'Delete artist?',
      '"${artist.name}" will be permanently deleted. An artist that still has albums or audios can\'t be deleted: delete them or move them to another artist first.',
    ),
    Album album => ('Delete album?', '"${album.name}" will be permanently deleted. Its audios are kept.'),
    Audio audio => ('Delete audio?', '"${audio.title}" will be permanently deleted.'),
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
