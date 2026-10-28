// audio_links_section.dart
//
// The "Artists & albums" part of EditAudioPage. An audio isn't stored with its artists / albums: it is LINKED
// to them (artist-album-audio links). A link is added / removed right away, one request per change
// (admin only). The artist / album must already exist, so the autocomplete suggests the existing ones and
// offers to create a new one first ("Create ...", then it is added).
//
//   artist  GET /api/artist?search   POST /api/artist?name           POST / DELETE /api/audio/artist
//   album   GET /api/album?search    POST /api/album?name&artistId   POST / DELETE /api/audio/album
//   lists   GET /api/audio/artist?audioId   GET /api/audio/album?audioId   (audioArtistsProvider / audioAlbumsProvider)
//
// An album belongs to zero or one artist and adding it links that artist too. Removing an artist also removes
// that artist's albums on THIS audio (they would keep the artist on it).

import 'dart:async';

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/api/controllers/library_controller.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/providers/audio_links.dart';
import 'package:avarim/pages/common/link_autocomplete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AudioLinksSection extends ConsumerStatefulWidget {
  const AudioLinksSection({super.key, required this.audioId});

  final String audioId;

  @override
  ConsumerState<AudioLinksSection> createState() => _AudioLinksSectionState();
}

class _AudioLinksSectionState extends ConsumerState<AudioLinksSection> {
  bool _busy = false;

  String get _id => widget.audioId;

  void _refresh() {
    ref.invalidate(audioArtistsProvider(_id));
    ref.invalidate(audioAlbumsProvider(_id));
  }

  /// Runs one change. The lists are reloaded afterwards, also when it failed half-way.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh();
      }
    }
  }

  // ---- artists -------------------------------------------------------------

  Future<void> _addArtist(Artist artist) => _run(() async {
    await ref.read(audioControllerProvider).addArtist(audioId: _id, artistId: artist.id);
  });

  Future<void> _createArtist(String name) async {
    if (_busy) return;
    final ok = await _confirm(context, title: 'Create artist', body: 'Create the artist "$name" and add it to this audio?', action: 'Create');
    if (!ok || !mounted) return;

    await _run(() async {
      final artist = await ref.read(libraryControllerProvider).createArtist(name);
      if (artist == null) return; // a toast says why (e.g. the name is taken)
      await ref.read(audioControllerProvider).addArtist(audioId: _id, artistId: artist.id);
    });
  }

  Future<void> _removeArtist(Artist artist, List<Album> albums) async {
    if (_busy) return;
    final owned = albums.where((a) => a.artistId == artist.id).toList();
    final extra = owned.isEmpty ? '' : ' Its albums on this audio (${owned.map((a) => a.name).join(', ')}) are removed too.';
    final ok = await _confirm(context, title: 'Remove artist', body: 'Remove "${artist.name}" from this audio?$extra', action: 'Remove');
    if (!ok || !mounted) return;

    await _run(() async {
      final controller = ref.read(audioControllerProvider);
      // The artist's own link first, then the links of its albums (they would keep the artist on the audio).
      if (!await controller.removeArtist(audioId: _id, artistId: artist.id)) return;
      for (final album in owned) {
        if (!await controller.removeAlbum(audioId: _id, albumId: album.id, artistId: artist.id)) return;
      }
    });
  }

  // ---- albums --------------------------------------------------------------

  Future<void> _addAlbum(Album album) => _run(() async {
    await ref.read(audioControllerProvider).addAlbum(audioId: _id, albumId: album.id);
  });

  Future<void> _createAlbum(String name) async {
    if (_busy) return;
    final result = await showDialog<_NewAlbum>(context: context, builder: (_) => _NewAlbumDialog(initialName: name));
    if (result == null || !mounted) return;

    await _run(() async {
      final album = await ref.read(libraryControllerProvider).createAlbum(name: result.name, artistId: result.artist?.id);
      if (album == null) return; // a toast says why
      await ref.read(audioControllerProvider).addAlbum(audioId: _id, albumId: album.id);
    });
  }

  Future<void> _removeAlbum(Album album) async {
    if (_busy) return;
    final ok = await _confirm(context, title: 'Remove album', body: 'Remove "${album.name}" from this audio?', action: 'Remove');
    if (!ok || !mounted) return;

    await _run(() async {
      await ref.read(audioControllerProvider).removeAlbum(audioId: _id, albumId: album.id, artistId: album.artistId);
    });
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.read(libraryControllerProvider);
    final artists = ref.watch(audioArtistsProvider(_id));
    final albums = ref.watch(audioAlbumsProvider(_id));

    final artistList = artists.value ?? const <Artist>[];
    final albumList = albums.value ?? const <Album>[];
    final loading = _busy || artists.isLoading || albums.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Artists & albums', style: theme.textTheme.titleLarge),
            if (loading) ...[const SizedBox(width: 12), const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))],
          ],
        ),
        const SizedBox(height: 4),
        Text('Changes here are saved right away.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),

        Text('Artists', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (artists.hasError)
          _LoadError(onRetry: _refresh)
        else if (artistList.isEmpty)
          Text(artists.isLoading ? 'Loading...' : 'No artists', style: theme.textTheme.bodyMedium)
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final a in artistList)
                InputChip(key: ValueKey('artist-${a.id}'), avatar: const Icon(Icons.person, size: 18), label: Text(a.name), onDeleted: () => _removeArtist(a, albumList)),
            ],
          ),
        const SizedBox(height: 8),
        LinkAutocomplete<Artist>(
          label: 'Add an artist',
          hint: 'Type a name to search',
          enabled: !_busy,
          search: library.searchArtists,
          labelOf: (a) => a.name,
          excludeIds: {for (final a in artistList) a.id},
          onPick: _addArtist,
          onCreate: _createArtist,
          createLabel: 'Create artist',
        ),

        const SizedBox(height: 24),
        Text('Albums', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (albums.hasError)
          _LoadError(onRetry: _refresh)
        else if (albumList.isEmpty)
          Text(albums.isLoading ? 'Loading...' : 'No albums', style: theme.textTheme.bodyMedium)
        else
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final a in albumList)
                InputChip(key: ValueKey('album-${a.id}'), avatar: const Icon(Icons.album, size: 18), label: _AlbumLabel(a), onDeleted: () => _removeAlbum(a)),
            ],
          ),
        const SizedBox(height: 8),
        LinkAutocomplete<Album>(
          label: 'Add an album',
          hint: 'Type a name to search',
          enabled: !_busy,
          search: library.searchAlbums,
          labelOf: (a) => a.name,
          excludeIds: {for (final a in albumList) a.id},
          onPick: _addAlbum,
          onCreate: _createAlbum,
          createLabel: 'Create album',
          // album names repeat (they are only unique per artist), so creating one is always offered
          alwaysOfferCreate: true,
          optionSubtitle: (a) => a.artistId == null ? const Text('No artist') : _ArtistName(a.artistId!),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text("Couldn't load", style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(width: 8),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

/// "Album - Artist" (just "Album" when it has no artist).
class _AlbumLabel extends ConsumerWidget {
  const _AlbumLabel(this.album);

  final Album album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistId = album.artistId;
    final artist = artistId == null ? null : ref.watch(artistByIdProvider(artistId)).value;
    return Text(artist == null ? album.name : '${album.name} - ${artist.name}');
  }
}

class _ArtistName extends ConsumerWidget {
  const _ArtistName(this.artistId);

  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = ref.watch(artistByIdProvider(artistId)).value;
    return Text(artist?.name ?? '...');
  }
}

Future<bool> _confirm(BuildContext context, {required String title, required String body, required String action}) async {
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

// ---------------------------------------------------------------------------
// Create album dialog
// ---------------------------------------------------------------------------

class _NewAlbum {
  const _NewAlbum(this.name, this.artist);

  final String name;
  final Artist? artist;
}

/// Asks for the new album's name and (optionally) its artist. Pops with a [_NewAlbum].
class _NewAlbumDialog extends ConsumerStatefulWidget {
  const _NewAlbumDialog({required this.initialName});

  final String initialName;

  @override
  ConsumerState<_NewAlbumDialog> createState() => _NewAlbumDialogState();
}

class _NewAlbumDialogState extends ConsumerState<_NewAlbumDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  Artist? _artist;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.read(libraryControllerProvider);
    final name = _name.text.trim();

    return AlertDialog(
      title: const Text('Create album'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Album name', border: OutlineInputBorder()),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            if (_artist != null)
              InputChip(avatar: const Icon(Icons.person, size: 18), label: Text(_artist!.name), onDeleted: () => setState(() => _artist = null))
            else
              LinkAutocomplete<Artist>(
                label: 'Artist (optional)',
                hint: 'Leave empty for an album without an artist',
                search: library.searchArtists,
                labelOf: (a) => a.name,
                onPick: (a) async => setState(() => _artist = a),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: name.isEmpty ? null : () => Navigator.pop(context, _NewAlbum(name, _artist)), child: const Text('Create and add')),
      ],
    );
  }
}
