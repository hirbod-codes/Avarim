// album_playlist_menu.dart
//
// "Save to playlist" button for an album (put it next to the search page):
//
//   - Add to a playlist…        pick one of the playlists; the album's audios that aren't in it yet are added
//   - Save as a new playlist…   ask for a name, create the playlist, add all of the album's audios to it
//
// Backend (playlist routes):
//   GET  /api/playlist?page&pageSize&search                       playlists (for the picker)
//   POST /api/playlist  { name }                                  create -> { playlistId }
//   GET  /api/playlist/audio?playlistId=&page&pageSize            audios already in a playlist
//   GET  /api/album/audio?albumId=&page&pageSize                  the album's audios
//   POST /api/playlist/audio  { playlistId, audioIds }            add audios (in chunks, JSON body)
//
// The same actions also work for any list of audio ids (one audio of a result row, the whole queue):
// see AudioPlaylistMenu at the end of the file.
//
// The backend doesn't reject duplicates, so adding to an existing playlist first looks up what is
// already in it and only sends the rest.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

/// Page size when fetching ALL the audios of an album / playlist.
const _kAudioPageSize = 50;

/// Page size of the playlist picker.
const _kPickerPageSize = 20;

/// The audio ids travel in the request body, in chunks of this size.
const _kAddChunkSize = 200;

const _kFirstPage = 1; // pages are 1-based

/// Requests whose failure the UI shows itself (inline), so no error toast.
final _silent = Options(extra: {GlobalErrorInterceptor.silentErrorsKey: true});

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class AlbumPlaylistApi {
  AlbumPlaylistApi(this._dio);
  final Dio _dio;

  /// Playlists for the picker. A failure was already shown as a toast.
  Future<ApiCallResult<List<Playlist>>> searchPlaylists({required String query, required int page}) {
    return apiCall<List<Playlist>>(
      () => _dio.get<dynamic>('/api/playlist', queryParameters: {'page': page, 'pageSize': _kPickerPageSize, if (query.isNotEmpty) 'search': query}),
      fromJson: (data) => List.from(data).map((e) => Playlist.fromJson(e)).toList(),
    );
  }

  /// Ids of every audio of the album [albumId]. Null when a request failed (already shown).
  Future<List<String>?> albumAudioIds(String albumId) => _allAudioIds('/api/album/audio', {'albumId': albumId});

  /// Ids of every audio in a playlist. Null when a request failed (already shown).
  Future<List<String>?> playlistAudioIds(String playlistId) => _allAudioIds('/api/playlist/audio', {'playlistId': playlistId});

  /// Pages through [path] until the last page (same idea as MusicSearchApi's queue helper).
  Future<List<String>?> _allAudioIds(String path, Map<String, dynamic> params) async {
    final ids = <String>{}; // keeps the order, drops duplicates
    for (var page = _kFirstPage; ; page++) {
      final res = await apiCall<List<String>>(
        () => _dio.get<dynamic>(path, queryParameters: {...params, 'page': page, 'pageSize': _kAudioPageSize}),
        fromJson: (data) => List.from(data).map(_audioIdOf).whereType<String>().toList(),
      );
      if (res.isFailure) return null;

      final pageIds = res.dataOrNull ?? const <String>[];
      final before = ids.length;
      ids.addAll(pageIds);

      // A short page is the last one. No NEW ids means the server ignored `page`: stop instead of looping forever.
      if (pageIds.length < _kAudioPageSize || ids.length == before) return ids.toList();
    }
  }

  static String? _audioIdOf(dynamic e) {
    if (e is! Map) return null;
    return (e['_id'] ?? e['audioId'])?.toString();
  }

  /// POST /api/playlist { name } -> `{ playlistId }` (every user can create playlists; names are unique).
  /// Silent: the caller shows a failure (e.g. "name already taken") inline in the dialog.
  Future<ApiCallResult<String>> createPlaylist(String name) {
    return apiCall<String>(
      () => _dio.post<dynamic>('/api/playlist', data: {'name': name}, options: _silent),
      fromJson: (data) => (data as Map)['playlistId'].toString(),
    );
  }

  /// Adds audios to a playlist, a chunk per request, stopping at the first failure (already shown).
  /// Returns how many were added.
  Future<int> addAudios(String playlistId, List<String> audioIds) async {
    var added = 0;
    for (var i = 0; i < audioIds.length; i += _kAddChunkSize) {
      final end = i + _kAddChunkSize > audioIds.length ? audioIds.length : i + _kAddChunkSize;
      final chunk = audioIds.sublist(i, end);

      final res = await apiCall<dynamic>(() => _dio.post<dynamic>('/api/playlist/audio', data: {'playlistId': playlistId, 'audioIds': chunk}));
      if (res.isFailure) break;
      added += chunk.length;
    }
    return added;
  }
}

final albumPlaylistApiProvider = Provider<AlbumPlaylistApi>((ref) => AlbumPlaylistApi(ref.watch(authDioProvider)));

// ─────────────────────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────────────────────

class AlbumPlaylistActions {
  AlbumPlaylistActions(this._api);
  final AlbumPlaylistApi _api;

  /// Adds the album's audios that aren't in [playlist] yet. The outcome is shown as a toast.
  Future<void> addToPlaylist(Album album, Playlist playlist) async {
    final ids = await _api.albumAudioIds(album.id);
    if (ids == null) return; // a request failed and its error was already shown
    await addIdsToPlaylist(ids, playlist, emptyMessage: 'This album has no audios');
  }

  /// Adds the audios in [audioIds] that aren't in [playlist] yet. The outcome is shown as a toast.
  Future<void> addIdsToPlaylist(List<String> audioIds, Playlist playlist, {String emptyMessage = 'There are no audios to add'}) async {
    if (audioIds.isEmpty) {
      NotificationService.showError(message: emptyMessage);
      return;
    }

    final existing = await _api.playlistAudioIds(playlist.id);
    if (existing == null) return; // a request failed and its error was already shown

    final inPlaylist = existing.toSet();
    final wanted = audioIds.toSet().toList(); // no duplicates, order kept
    final missing = [
      for (final id in wanted)
        if (!inPlaylist.contains(id)) id,
    ];
    if (missing.isEmpty) {
      NotificationService.showSuccess(message: wanted.length == 1 ? 'It is already in "${playlist.name}"' : 'All of the audios are already in "${playlist.name}"');
      return;
    }

    final added = await _api.addAudios(playlist.id, missing);
    _report(playlist.name, added, missing.length, alreadyThere: wanted.length - missing.length);
  }

  /// Creates a playlist called [name] with all of the album's audios.
  ///
  /// Returns an error text for the dialog when NOTHING was created (the user can fix it and retry), or null
  /// when the playlist exists. If adding some audios failed after that, a toast says so.
  Future<String?> saveAsNewPlaylist(Album album, String name) async {
    final ids = await _api.albumAudioIds(album.id);
    if (ids == null) return "Couldn't load the album's audios.";
    if (ids.isEmpty) return 'This album has no audios.';
    return saveIdsAsNewPlaylist(ids, name);
  }

  /// Creates a playlist called [name] with [audioIds] (same result convention as [saveAsNewPlaylist]).
  Future<String?> saveIdsAsNewPlaylist(List<String> audioIds, String name) async {
    final ids = audioIds.toSet().toList();
    if (ids.isEmpty) return 'There are no audios to save.';

    final created = await _api.createPlaylist(name);
    if (created case ApiCallFailure(:final message)) return message;

    final playlistId = created.dataOrNull;
    if (playlistId == null) {
      NotificationService.showError(message: 'Playlist "$name" was created, but its audios could not be added');
      return null;
    }

    final added = await _api.addAudios(playlistId, ids);
    _report(name, added, ids.length);
    return null;
  }

  void _report(String playlistName, int added, int wanted, {int alreadyThere = 0}) {
    if (added == wanted) {
      final extra = alreadyThere > 0 ? ' ($alreadyThere already there)' : '';
      NotificationService.showSuccess(message: 'Added ${_audios(added)} to "$playlistName"$extra');
    } else if (added == 0) {
      NotificationService.showError(message: 'No audios were added to "$playlistName"');
    } else {
      NotificationService.showError(message: 'Only $added of $wanted audios were added to "$playlistName"');
    }
  }

  String _audios(int n) => n == 1 ? '1 audio' : '$n audios';
}

final albumPlaylistActionsProvider = Provider<AlbumPlaylistActions>((ref) => AlbumPlaylistActions(ref.watch(albumPlaylistApiProvider)));

// ─────────────────────────────────────────────────────────────────────────────
// Menu button
// ─────────────────────────────────────────────────────────────────────────────

enum _AlbumPlaylistAction { addToPlaylist, saveAsNewPlaylist }

class AlbumPlaylistMenu extends ConsumerStatefulWidget {
  const AlbumPlaylistMenu({super.key, required this.album, this.onPlaylistCreated});

  final Album album;

  /// Called after a new playlist was created (e.g. to refresh a list of playlists).
  final VoidCallback? onPlaylistCreated;

  @override
  ConsumerState<AlbumPlaylistMenu> createState() => _AlbumPlaylistMenuState();
}

class _AlbumPlaylistMenuState extends ConsumerState<AlbumPlaylistMenu> {
  bool _busy = false;

  Future<void> _addToPlaylist() async {
    final playlist = await showDialog<Playlist>(context: context, builder: (_) => const PlaylistPickerDialog());
    if (playlist == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(albumPlaylistActionsProvider).addToPlaylist(widget.album, playlist);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAsNewPlaylist() async {
    final actions = ref.read(albumPlaylistActionsProvider);
    final album = widget.album;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // the request may be running
      builder: (_) => NewPlaylistDialog(initialName: album.name, onSubmit: (name) => actions.saveAsNewPlaylist(album, name)),
    );
    if (created == true) widget.onPlaylistCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return PopupMenuButton<_AlbumPlaylistAction>(
      tooltip: 'Save to playlist',
      icon: const Icon(Icons.library_add_outlined),
      onSelected: (action) {
        switch (action) {
          case _AlbumPlaylistAction.addToPlaylist:
            unawaited(_addToPlaylist());
          case _AlbumPlaylistAction.saveAsNewPlaylist:
            unawaited(_saveAsNewPlaylist());
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: _AlbumPlaylistAction.addToPlaylist, child: Text('Add to a playlist…')),
        PopupMenuItem(value: _AlbumPlaylistAction.saveAsNewPlaylist, child: Text('Save as a new playlist…')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialogs
// ─────────────────────────────────────────────────────────────────────────────

/// Searchable list of playlists; pops with the chosen [Playlist].
class PlaylistPickerDialog extends ConsumerStatefulWidget {
  const PlaylistPickerDialog({super.key});

  @override
  ConsumerState<PlaylistPickerDialog> createState() => _PlaylistPickerDialogState();
}

class _PlaylistPickerDialogState extends ConsumerState<PlaylistPickerDialog> {
  final _search = TextEditingController();
  final _items = <Playlist>[];
  Timer? _debounce;

  int _page = 0; // last page loaded
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;
  int _generation = 0; // answers of outdated searches are dropped

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || !_hasMore)) return;

    final generation = ++_generation;
    final page = reset ? _kFirstPage : _page + 1;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) {
        _items.clear();
        _page = 0;
        _hasMore = true;
      }
    });

    final result = await ref.read(albumPlaylistApiProvider).searchPlaylists(query: _search.text.trim(), page: page);
    if (!mounted || generation != _generation) return;

    setState(() {
      _loading = false;
      if (result case ApiCallFailure()) {
        _failed = true; // the error was already shown as a toast
        return;
      }
      final fetched = result.dataOrNull ?? const <Playlist>[];
      _items.addAll(fetched);
      _page = page;
      _hasMore = fetched.length >= _kPickerPageSize;
    });
  }

  Widget _body() {
    if (_items.isEmpty && _loading) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    if (_items.isEmpty && _failed) {
      return SizedBox(
        height: 120,
        child: Center(
          child: TextButton(onPressed: () => _load(reset: true), child: const Text("Couldn't load playlists. Retry")),
        ),
      );
    }
    if (_items.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('No playlists found')));
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _items.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i < _items.length) {
          final playlist = _items[i];
          return ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => Navigator.pop(context, playlist),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: _loading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : TextButton(onPressed: () => _load(reset: false), child: const Text('Load more')),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add to a playlist', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: _onChanged,
                decoration: const InputDecoration(hintText: 'Search playlists', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              Flexible(child: _body()),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a playlist name and runs [onSubmit]. [onSubmit] returns an error text to show under the field
/// (the dialog stays open so the name can be changed), or null when it worked (the dialog pops `true`).
class NewPlaylistDialog extends StatefulWidget {
  const NewPlaylistDialog({super.key, required this.initialName, required this.onSubmit});

  final String initialName;
  final Future<String?> Function(String name) onSubmit;

  @override
  State<NewPlaylistDialog> createState() => _NewPlaylistDialogState();
}

class _NewPlaylistDialogState extends State<NewPlaylistDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialName.length);

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;

    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await widget.onSubmit(name);
    if (!mounted) return;

    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as a new playlist'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _name,
          autofocus: true,
          enabled: !_loading,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Playlist name',
            helperText: "All of the album's audios will be added to it",
            errorText: _error,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _loading ? null : _submit,
          icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ],
    );
  }
}

// ?????????????????????????????????????????????????????????????????????????????
// Menu button for a list of audios
// ?????????????????????????????????????????????????????????????????????????????

/// "Add to playlist" button for a list of audio ids: one audio of a result row, or the whole queue.
/// Same two choices as [AlbumPlaylistMenu]: add them to an existing playlist, or save them as a new one.
class AudioPlaylistMenu extends ConsumerStatefulWidget {
  const AudioPlaylistMenu({super.key, required this.audioIds, this.initialName = '', this.tooltip = 'Add to playlist', this.onPlaylistCreated});

  /// The audios to save. A function so that a changing list (the queue) is read when the user picks.
  final List<String> Function() audioIds;

  /// Suggested name of a new playlist.
  final String initialName;
  final String tooltip;

  /// Called after a new playlist was created (e.g. to refresh a list of playlists).
  final VoidCallback? onPlaylistCreated;

  @override
  ConsumerState<AudioPlaylistMenu> createState() => _AudioPlaylistMenuState();
}

class _AudioPlaylistMenuState extends ConsumerState<AudioPlaylistMenu> {
  bool _busy = false;

  Future<void> _addToPlaylist() async {
    final ids = widget.audioIds();
    final playlist = await showDialog<Playlist>(context: context, builder: (_) => const PlaylistPickerDialog());
    if (playlist == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(albumPlaylistActionsProvider).addIdsToPlaylist(ids, playlist);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAsNewPlaylist() async {
    final actions = ref.read(albumPlaylistActionsProvider);
    final ids = widget.audioIds();

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // the request may be running
      builder: (_) => NewPlaylistDialog(initialName: widget.initialName, onSubmit: (name) => actions.saveIdsAsNewPlaylist(ids, name)),
    );
    if (created == true) widget.onPlaylistCreated?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return PopupMenuButton<_AlbumPlaylistAction>(
      tooltip: widget.tooltip,
      icon: const Icon(Icons.library_add_outlined),
      onSelected: (action) {
        switch (action) {
          case _AlbumPlaylistAction.addToPlaylist:
            unawaited(_addToPlaylist());
          case _AlbumPlaylistAction.saveAsNewPlaylist:
            unawaited(_saveAsNewPlaylist());
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: _AlbumPlaylistAction.addToPlaylist, child: Text('Add to a playlist')),
        PopupMenuItem(value: _AlbumPlaylistAction.saveAsNewPlaylist, child: Text('Save as a new playlist')),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Save as a new playlist (one button)
// ---------------------------------------------------------------------------

/// An icon button that saves a list of audios (e.g. the player queue) as a NEW playlist: it asks for a name,
/// a taken name is reported inside the dialog so the user can pick another one, and a toast confirms the
/// result.
class SaveAsPlaylistButton extends ConsumerWidget {
  const SaveAsPlaylistButton({super.key, required this.audioIds, this.tooltip = 'Save as a playlist', this.initialName = '', this.onPlaylistCreated});

  /// The audios to save. A function so that a changing list (the queue) is read when the button is pressed.
  final List<String> Function() audioIds;
  final String tooltip;

  /// Suggested name of the playlist.
  final String initialName;

  /// Called after the playlist was created.
  final VoidCallback? onPlaylistCreated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.library_add_outlined),
      onPressed: () async {
        final ids = audioIds();
        if (ids.isEmpty) {
          NotificationService.showError(message: 'There are no audios to save');
          return;
        }

        final actions = ref.read(albumPlaylistActionsProvider);
        final created = await showDialog<bool>(
          context: context,
          barrierDismissible: false, // the request may be running
          builder: (_) => NewPlaylistDialog(initialName: initialName, onSubmit: (name) => actions.saveIdsAsNewPlaylist(ids, name)),
        );
        if (created == true) onPlaylistCreated?.call();
      },
    );
  }
}
