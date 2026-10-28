import 'dart:async';

import 'package:avarim/api/controllers/audio_controller.dart';
import 'package:avarim/api/controllers/library_controller.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// An audio's artists and albums are not stored on the audio document. They are resolved from the
// artist-album-audio links (GET /api/audio/artist, GET /api/audio/album), so every place that shows them
// watches these providers instead of reading `audio.tags`.
//
// Results are kept for a few minutes so scrolling a list (or switching between the mini bar and the queue)
// doesn't refetch every row; a failure isn't kept. After changing the links, invalidate both providers.

const _kKeepFor = Duration(minutes: 5);

Future<T> _keepFor<T>(Ref ref, Future<T> Function() fetch) async {
  final link = ref.keepAlive();
  final timer = Timer(_kKeepFor, link.close);
  ref.onDispose(timer.cancel);

  try {
    return await fetch();
  } catch (_) {
    link.close(); // don't keep failures around
    rethrow;
  }
}

/// The artists the audio is linked to (with or without an album).
final audioArtistsProvider = FutureProvider.autoDispose.family<List<Artist>, String>((ref, audioId) {
  return _keepFor(ref, () => ref.read(audioControllerProvider).artists(audioId: audioId));
});

/// The albums the audio is linked to.
final audioAlbumsProvider = FutureProvider.autoDispose.family<List<Album>, String>((ref, audioId) {
  return _keepFor(ref, () => ref.read(audioControllerProvider).albums(audioId: audioId));
});

/// One artist by id (to show the artist next to an album). null when it can't be found.
final artistByIdProvider = FutureProvider.autoDispose.family<Artist?, String>((ref, artistId) {
  return _keepFor(ref, () => ref.read(libraryControllerProvider).artistById(artistId));
});

/// "Artist A, Artist B", or null when there is none (or they aren't loaded yet).
String? artistsLabel(List<Artist>? artists) {
  if (artists == null) return null;
  final names = artists.map((a) => a.name.trim()).where((n) => n.isNotEmpty);
  final label = names.join(', ');
  return label.isEmpty ? null : label;
}

/// "Album A, Album B", or null when there is none (or they aren't loaded yet).
String? albumsLabel(List<Album>? albums) {
  if (albums == null) return null;
  final names = albums.map((a) => a.name.trim()).where((n) => n.isNotEmpty);
  final label = names.join(', ');
  return label.isEmpty ? null : label;
}
