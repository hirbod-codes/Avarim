import 'dart:async';

import 'package:avarim/api/models/album.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/pages/search/ui/items/item_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DeleteAlbumSection extends ConsumerStatefulWidget {
  const DeleteAlbumSection({super.key, required this.album, this.onDeleted});

  final Album album;
  final Function? onDeleted;

  @override
  ConsumerState<DeleteAlbumSection> createState() => _DeleteAlbumSectionState();
}

class _DeleteAlbumSectionState extends ConsumerState<DeleteAlbumSection> {
  bool _running = false; // deleting

  Future<void> _start() async {
    setState(() {
      _running = true;
    });

    bool result = false;
    await onDeleteAlbum(
      context,
      ref,
      widget.album,
      onDeleted: (id) {
        result = true;
        NotificationService.showSuccess(message: 'successfully deleted the album');
      },
    );
    if (!mounted) return;

    if (result) widget.onDeleted?.call();

    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Danger zone', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error)),
        const SizedBox(height: 8),
        Text('Deletes this album.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error),
          ),
          onPressed: busy ? null : _start,
          icon: _running ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_sweep_outlined),
          label: const Text('Delete this album'),
        ),
      ],
    );
  }
}
