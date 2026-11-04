import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/models/playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/save_to_playlist_api.dart';
import '../save_to_playlist_config.dart';

/// Searchable list of playlists; pops with the chosen [Playlist].
class PlaylistPickerDialog extends ConsumerStatefulWidget {
  const PlaylistPickerDialog({super.key});

  @override
  ConsumerState<PlaylistPickerDialog> createState() => _PlaylistPickerDialogState();
}

class _PlaylistPickerDialogState extends ConsumerState<PlaylistPickerDialog> {
  static const _searchDebounceDuration = Duration(milliseconds: 500);

  /// Height of the loading / error / empty states, so the dialog doesn't collapse while they show.
  static const _statusAreaHeight = 120.0;

  final _searchTextController = TextEditingController();
  final _loadedPlaylists = <Playlist>[];
  Timer? _searchDebounceTimer;

  int _lastLoadedPageNumber = 0;
  bool _isLoading = false;
  bool _hasMorePages = true;
  bool _hasLoadingFailed = false;

  /// Incremented by every request; answers of outdated searches are dropped.
  int _latestRequestGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPlaylists(restartFromFirstPage: true));
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchTextController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged(String _) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(_searchDebounceDuration, () => _loadPlaylists(restartFromFirstPage: true));
  }

  Future<void> _loadPlaylists({required bool restartFromFirstPage}) async {
    if (!restartFromFirstPage && (_isLoading || !_hasMorePages)) return;

    final requestGeneration = ++_latestRequestGeneration;
    final pageNumber = restartFromFirstPage ? kFirstPageNumber : _lastLoadedPageNumber + 1;
    setState(() {
      _isLoading = true;
      _hasLoadingFailed = false;
      if (restartFromFirstPage) {
        _loadedPlaylists.clear();
        _lastLoadedPageNumber = 0;
        _hasMorePages = true;
      }
    });

    final searchResult = await ref
        .read(saveToPlaylistApiProvider)
        .searchPlaylists(searchText: _searchTextController.text.trim(), pageNumber: pageNumber);
    if (!mounted || requestGeneration != _latestRequestGeneration) return;

    setState(() {
      _isLoading = false;
      if (searchResult case ApiCallFailure()) {
        _hasLoadingFailed = true; // the error was already shown as a toast
        return;
      }
      final fetchedPlaylists = searchResult.dataOrNull ?? const <Playlist>[];
      _loadedPlaylists.addAll(fetchedPlaylists);
      _lastLoadedPageNumber = pageNumber;
      _hasMorePages = fetchedPlaylists.length >= kPlaylistPickerPageSize;
    });
  }

  Widget _buildBody() {
    if (_loadedPlaylists.isEmpty && _isLoading) {
      return const SizedBox(height: _statusAreaHeight, child: Center(child: CircularProgressIndicator()));
    }
    if (_loadedPlaylists.isEmpty && _hasLoadingFailed) {
      return SizedBox(
        height: _statusAreaHeight,
        child: Center(
          child: TextButton(
            onPressed: () => _loadPlaylists(restartFromFirstPage: true),
            child: const Text("Couldn't load playlists. Retry"),
          ),
        ),
      );
    }
    if (_loadedPlaylists.isEmpty) {
      return const SizedBox(height: _statusAreaHeight, child: Center(child: Text('No playlists found')));
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _loadedPlaylists.length + (_hasMorePages ? 1 : 0),
      itemBuilder: (context, index) {
        final isLoadMoreRow = index >= _loadedPlaylists.length;
        if (isLoadMoreRow) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: _isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton(onPressed: () => _loadPlaylists(restartFromFirstPage: false), child: const Text('Load more')),
            ),
          );
        }

        final playlist = _loadedPlaylists[index];
        return ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.pop(context, playlist),
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
                controller: _searchTextController,
                autofocus: true,
                onChanged: _onSearchTextChanged,
                decoration: const InputDecoration(
                  hintText: 'Search playlists',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: _buildBody()),
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
