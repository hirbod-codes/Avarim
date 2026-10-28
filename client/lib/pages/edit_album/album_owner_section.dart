// album_owner_section.dart
//
// The "Artist" part of the edit album page. An album belongs to zero or one artist. Changing it is saved right
// away (admin only):
//
//   set / change   PATCH /api/album/owner { albumId, newArtistId }
//   remove         PATCH /api/album/owner { albumId }               the album then has no artist
//
// The artist must already exist: pick one from the autocomplete (create new artists in the artist editor).

import 'dart:async';

import 'package:avarim/api/controllers/library_controller.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/providers/audio_links.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/pages/common/link_autocomplete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AlbumOwnerSection extends ConsumerStatefulWidget {
  const AlbumOwnerSection({super.key, required this.albumId, required this.albumName, required this.artistId});

  final String albumId;
  final String albumName;

  /// The album's artist when the page was loaded, null when it has none.
  final String? artistId;

  @override
  ConsumerState<AlbumOwnerSection> createState() => _AlbumOwnerSectionState();
}

class _AlbumOwnerSectionState extends ConsumerState<AlbumOwnerSection> {
  late String? _artistId = widget.artistId;
  bool _busy = false;

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return result ?? false;
  }

  /// Makes [artist] the album's artist, or removes the artist when it is null.
  Future<void> _setOwner(Artist? artist) async {
    if (_busy) return;

    final name = widget.albumName;
    final ok = artist == null
        ? await _confirm('Remove the artist', 'Remove the artist of "$name"? The album will have no artist.', 'Remove')
        : await _confirm('Change the artist', 'Make "${artist.name}" the artist of "$name"?', 'Change');
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    try {
      final done = await ref.read(libraryControllerProvider).setAlbumOwner(albumId: widget.albumId, artistId: artist?.id);
      if (!mounted) return;
      if (done) {
        setState(() => _artistId = artist?.id);
        NotificationService.showSuccess(message: artist == null ? 'The album has no artist now' : 'The artist is now "${artist.name}"');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.read(libraryControllerProvider);
    final currentId = _artistId;
    final current = currentId == null ? null : ref.watch(artistByIdProvider(currentId)).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Artist', style: theme.textTheme.titleLarge),
            if (_busy) ...[const SizedBox(width: 12), const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))],
          ],
        ),
        const SizedBox(height: 4),
        Text('An album belongs to zero or one artist. Changes here are saved right away.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        if (currentId == null)
          Text('No artist', style: theme.textTheme.bodyMedium)
        else
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(avatar: const Icon(Icons.person, size: 18), label: Text(current?.name ?? '...'), onDeleted: () => _setOwner(null)),
          ),
        const SizedBox(height: 8),
        LinkAutocomplete<Artist>(
          label: currentId == null ? 'Set the artist' : 'Change the artist',
          hint: 'Type a name to search',
          enabled: !_busy,
          search: library.searchArtists,
          labelOf: (a) => a.name,
          excludeIds: {if (currentId != null) currentId},
          onPick: _setOwner,
        ),
      ],
    );
  }
}
