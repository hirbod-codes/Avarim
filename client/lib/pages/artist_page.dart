// artist_page.dart
//
// Artist profile page, laid out like an Instagram profile:
//
//   ┌───────────────────────────┐
//   │         banner            │
//   │  (●)                      │   circular avatar overlapping the banner's bottom edge
//   └──╰─╯──────────── [ Play ] ┘   "Play" = all of the artist's audios
//   Artist name
//   12 albums
//
//   Albums                         paginated grid (infinite scroll, pull to refresh)
//   [cover ▶] [cover ▶] [cover ▶]  tap the card -> onAlbumTap (default: play the album)
//   Name      Name      Name       tap the ▶ button -> play the album
//
// Playing uses the global player: AudioPlayerService.play(audioIds: ...).
//
// Routing (go_router) - register it like your other pages:
//
//   GoRoute(
//     path: '/artist',
//     builder: (context, state) => ArtistPage(
//       artistId: state.uri.queryParameters['artistId'],
//       artistName: state.uri.queryParameters['name'],
//     ),
//   ),
//
//   context.push(Uri(path: '/artist', queryParameters: {'artistId': artist.id}).toString());
//
// Endpoints used:
//   GET /api/artist/info?artistId=… | name=…
//   GET /api/artist/avatar/:artistId        GET /api/artist/banner/:artistId   (the banner keeps its aspect ratio)
//   GET /api/relationship/artist/album?artistId=&page=&pageSize=           the artist's albums
//   GET /api/relationship/artist/audio?artistId=&page=&pageSize=           "Play" (all of the artist's audios)
//   GET /api/relationship/artist/audio/singles?artistId=&page=&pageSize=   the "Singles" section: audios with this artist but no album
//   GET /api/relationship/album/audio?albumId=&page=&pageSize=             an album's audios (play an album / add it to the queue)
//   GET /api/album/avatar/:albumId                            album cover
//
// ASSUMPTIONS (those responses weren't visible, so they are parsed leniently):
//   - an album item is a map with `_id` (or `albumId` / `id`) and `name` (or `albumName` / `album`),
//     or just the album's name as a string
//   - audios are Audio documents (`_id`, plus `tags.trackNumber` / `tags.discNumber`, which order an
//     album's audios; without them the server order is kept)
//   - albums are looked up by id: album names are only unique together with their artist.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/models/artist.dart';
import 'package:avarim/api/models/audio.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/auth/token_storage.dart';
import 'package:avarim/components/contents/audio_row_actions.dart';
import 'package:avarim/components/global/audio_player_service.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart' hide Thumb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:avarim/pages/search/search_page.dart' show Thumb;

// ─────────────────────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────────────────────

const kArtistAlbumsPageSize = 20;
const kArtistAudiosPageSize = 50;

/// First page number the API expects.
const kArtistFirstPage = 1;

/// Height of the placeholder shown until the banner image has loaded (or when there is none);
/// the status bar area is added on top. Once loaded, the banner is as tall as its image is at full width.
const kArtistBannerHeight = 180.0;
const kArtistAvatarRadius = 48.0;

/// The banner never grows taller than this fraction of the screen height (taller images are cropped to it).
const kArtistBannerMaxHeightFactor = 0.4;

/// Artist edit page (the same route the search page pushes).
const kArtistEditRoute = '/artist/edit';

// ─────────────────────────────────────────────────────────────────────────────
// Models (lenient)
// ─────────────────────────────────────────────────────────────────────────────

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

class ArtistAlbum {
  const ArtistAlbum({this.id, required this.name});

  final String? id;
  final String name;

  /// Stable key for de-duplication / "this one is loading".
  String get key => id ?? name;

  static ArtistAlbum? tryParse(Object? e) {
    if (e is String) {
      final name = _str(e);
      return name == null ? null : ArtistAlbum(name: name);
    }
    if (e is! Map) return null;

    final name = _str(e['name']) ?? _str(e['albumName']) ?? _str(e['album']);
    if (name == null) return null;

    final rawId = e['_id'] ?? e['albumId'] ?? e['id'];
    return ArtistAlbum(id: rawId?.toString(), name: name);
  }
}

/// The few fields of an audio that are needed to queue it.
class ArtistTrack {
  const ArtistTrack({required this.id, this.disc, this.track});

  final String id;
  final int? disc;
  final int? track;

  static ArtistTrack? tryParse(Object? e) {
    if (e is! Map) return null;

    final id = (e['_id'] ?? e['audioId'] ?? e['id'])?.toString();
    if (id == null || id.isEmpty) return null;

    final tags = e['tags'] is Map ? e['tags'] as Map : const {};
    return ArtistTrack(id: id, disc: _int(tags['discNumber'] ?? e['discNumber']), track: _int(tags['trackNumber'] ?? e['trackNumber']));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class ArtistPageApi {
  ArtistPageApi(this._dio);

  final Dio _dio;

  Future<Artist?> info({String? artistId, String? name}) async {
    final res = await apiCall<Artist>(
      () => _dio.get<dynamic>('/api/artist/info', queryParameters: {if (artistId != null) 'artistId': artistId else 'name': name}),
      fromJson: (data) => Artist.fromJson(data as Map<String, dynamic>),
    );
    return res.dataOrNull;
  }

  /// null = the request failed.
  Future<List<ArtistAlbum>?> albums(String artistId, int page) async {
    final res = await apiCall<List<ArtistAlbum>>(
      () => _dio.get<dynamic>('/api/relationship/artist/album', queryParameters: {'artistId': artistId, 'page': page, 'pageSize': kArtistAlbumsPageSize}),
      fromJson: (data) => List.from(data).map(ArtistAlbum.tryParse).whereType<ArtistAlbum>().toList(),
    );
    return res.dataOrNull;
  }

  /// null = the request failed.
  Future<List<ArtistTrack>?> audios(String artistId, int page) async {
    final res = await apiCall<List<ArtistTrack>>(
      () => _dio.get<dynamic>('/api/relationship/artist/audio', queryParameters: {'artistId': artistId, 'page': page, 'pageSize': kArtistAudiosPageSize}),
      fromJson: (data) => List.from(data).map(ArtistTrack.tryParse).whereType<ArtistTrack>().toList(),
    );
    return res.dataOrNull;
  }

  /// The artist's audios that are in no album (GET /api/relationship/artist/audio/singles). null = the request failed.
  Future<List<Audio>?> singles(String artistId, int page) async {
    final res = await apiCall<List<Audio>>(
      () => _dio.get<dynamic>('/api/relationship/artist/audio/singles', queryParameters: {'artistId': artistId, 'page': page, 'pageSize': kArtistAudiosPageSize}),
      fromJson: (data) => [for (final e in List.from(data)) Audio.fromJson(Map<String, dynamic>.from(e as Map))],
    );
    return res.dataOrNull;
  }

  /// An album's audios (GET /api/relationship/album/audio). null = the request failed.
  Future<List<ArtistTrack>?> albumAudios(String albumId, int page) async {
    final res = await apiCall<List<ArtistTrack>>(
      () => _dio.get<dynamic>('/api/relationship/album/audio', queryParameters: {'albumId': albumId, 'page': page, 'pageSize': kArtistAudiosPageSize}),
      fromJson: (data) => List.from(data).map(ArtistTrack.tryParse).whereType<ArtistTrack>().toList(),
    );
    return res.dataOrNull;
  }
}

final artistPageApiProvider = Provider<ArtistPageApi>((ref) => ArtistPageApi(ref.watch(authDioProvider)));

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class ArtistPage extends ConsumerStatefulWidget {
  const ArtistPage({super.key, this.artistId, this.artistName, this.onAlbumTap})
    : assert(artistId != null || artistName != null, 'Pass artistId or artistName');

  final String? artistId;
  final String? artistName;

  /// Called when an album card is pressed. Defaults to playing the album.
  final void Function(ArtistAlbum album)? onAlbumTap;

  @override
  ConsumerState<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends ConsumerState<ArtistPage> {
  final _scroll = ScrollController();

  Map<String, String>? _headers; // Authorization header for the images

  Artist? _artist;
  bool _infoLoading = true;
  bool _infoFailed = false;

  final List<ArtistAlbum> _albums = [];
  int _nextPage = kArtistFirstPage;
  bool _hasMore = true;
  bool _loadingAlbums = false;
  bool _albumsFailed = false;

  // The "Singles" section: audios with this artist but no album. Loaded after the albums.
  final List<Audio> _singles = [];
  int _singlesNextPage = kArtistFirstPage;
  bool _singlesHasMore = true;
  bool _loadingSingles = false;
  bool _singlesFailed = false;

  Future<List<ArtistTrack>>? _artistTracks; // all of the artist's audios, loaded on the first "Play"
  final Map<String, Future<List<ArtistTrack>>> _albumTracks = {}; // album name -> its audios, loaded on first play
  String? _busyAlbumKey;
  String? _queueingAlbumKey; // the album whose audios are being loaded to add them to the queue
  bool _playingAll = false;
  int _imageEpoch = 0; // bumped after editing so that the avatar / banner are fetched again

  ArtistPageApi get _api => ref.read(artistPageApiProvider);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadToken();
    _loadInfo();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> _loadToken() async {
    try {
      final token = await ref.read(tokenStorageProvider).getAccessToken();
      if (!mounted) return;
      setState(() => _headers = (token == null || token.isEmpty) ? const {} : {'Authorization': 'Bearer $token'});
    } catch (e, st) {
      talker.error('caught error while trying to read the access token', e, st);
      if (mounted) setState(() => _headers = const {});
    }
  }

  Future<void> _loadInfo({bool showSpinner = false}) async {
    if (showSpinner) {
      setState(() {
        _infoLoading = true;
        _infoFailed = false;
      });
    }

    final known = _artist;
    final artist = await _api.info(artistId: known?.id ?? widget.artistId, name: known == null ? widget.artistName : null);
    if (!mounted) return;

    if (artist == null) {
      // Keep showing what we already have when only a refresh failed.
      if (_artist == null) {
        setState(() {
          _infoLoading = false;
          _infoFailed = true;
        });
      }
      NotificationService.showError(message: 'Could not load the artist');
      return;
    }

    setState(() {
      _artist = artist;
      _infoLoading = false;
      _infoFailed = false;
    });
    unawaited(_loadAlbums());
  }

  Future<void> _loadAlbums() async {
    final artist = _artist;
    if (artist == null || _loadingAlbums || !_hasMore) return;

    setState(() {
      _loadingAlbums = true;
      _albumsFailed = false;
    });

    final batch = await _api.albums(artist.id, _nextPage);
    if (!mounted) return;

    if (batch == null) {
      setState(() {
        _loadingAlbums = false;
        _albumsFailed = true;
      });
      return;
    }

    setState(() {
      final known = _albums.map((a) => a.key).toSet();
      final fresh = batch.where((a) => known.add(a.key)).toList();
      _albums.addAll(fresh);
      _nextPage++;
      // Stop on a short page, or when the server keeps sending what we already have.
      _hasMore = batch.length >= kArtistAlbumsPageSize && fresh.isNotEmpty;
      _loadingAlbums = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewportIfNeeded());
  }

  Future<void> _loadSingles() async {
    final artist = _artist;
    if (artist == null || _loadingSingles || !_singlesHasMore) return;

    setState(() {
      _loadingSingles = true;
      _singlesFailed = false;
    });

    final batch = await _api.singles(artist.id, _singlesNextPage);
    if (!mounted) return;

    if (batch == null) {
      setState(() {
        _loadingSingles = false;
        _singlesFailed = true;
      });
      return;
    }

    setState(() {
      final known = _singles.map((a) => a.id).toSet();
      final fresh = batch.where((a) => known.add(a.id)).toList();
      _singles.addAll(fresh);
      _singlesNextPage++;
      // Stop on a short page, or when the server keeps sending what we already have.
      _singlesHasMore = batch.length >= kArtistAudiosPageSize && fresh.isNotEmpty;
      _loadingSingles = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _fillViewportIfNeeded());
  }

  /// The next page of whatever is still loading: the albums first, then the singles.
  void _loadMore() {
    if (_hasMore) {
      if (!_albumsFailed) _loadAlbums();
    } else if (!_singlesFailed) {
      _loadSingles();
    }
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 400) _loadMore();
  }

  /// If the first page doesn't fill the screen there is nothing to scroll: keep loading until it does.
  void _fillViewportIfNeeded() {
    if (!mounted || !_scroll.hasClients) return;
    if (_scroll.position.maxScrollExtent <= 0) _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _albums.clear();
      _nextPage = kArtistFirstPage;
      _hasMore = true;
      _albumsFailed = false;
      _singles.clear();
      _singlesNextPage = kArtistFirstPage;
      _singlesHasMore = true;
      _singlesFailed = false;
      _artistTracks = null;
      _albumTracks.clear();
    });
    await _loadInfo(); // reloads the albums too
  }

  // ── Editing ────────────────────────────────────────────────────────────────

  /// Opens the artist edit page; reloads everything when the user comes back.
  Future<void> _edit() async {
    final artist = _artist;
    if (artist == null) return;

    final location = Uri(path: kArtistEditRoute, queryParameters: {'artistId': artist.id}).toString();
    await context.push(location);
    if (!mounted) return;

    // The avatar / banner may have changed: drop the cached images so that they are fetched again.
    final cache = PaintingBinding.instance.imageCache;
    for (final kind in const ['avatar', 'banner']) {
      cache.evict(NetworkImage('${AppConfig.apiUrl}/api/artist/$kind/${artist.id}'), includeLive: true);
    }
    setState(() => _imageEpoch++);

    unawaited(_refresh());
  }

  // ── Playing ────────────────────────────────────────────────────────────────

  /// Pages through [fetch] until the server runs out of audios.
  Future<List<ArtistTrack>> _loadAllPages(Future<List<ArtistTrack>?> Function(int page) fetch) async {
    final all = <ArtistTrack>[];
    final seen = <String>{};

    for (var page = kArtistFirstPage; page < kArtistFirstPage + 200; page++) {
      final batch = await fetch(page);
      if (batch == null) throw StateError('failed to load audios (page $page)');

      final fresh = batch.where((t) => seen.add(t.id)).toList();
      all.addAll(fresh);
      // Stop on a short page, or when the server keeps sending what we already have.
      if (batch.length < kArtistAudiosPageSize || fresh.isEmpty) break;
    }
    return all;
  }

  /// All of the artist's audios. Loaded once; a failure isn't cached, so it can be retried.
  Future<List<ArtistTrack>> _allArtistTracks() async {
    final artistId = _artist!.id;
    final future = _artistTracks ??= _loadAllPages((page) => _api.audios(artistId, page));
    try {
      return await future;
    } catch (_) {
      if (identical(_artistTracks, future)) _artistTracks = null;
      rethrow;
    }
  }

  /// An album's audios (GET /api/relationship/album/audio?albumId). Loaded once per album; a failure isn't cached.
  Future<List<ArtistTrack>> _audiosOf(ArtistAlbum album) async {
    final albumId = album.id;
    if (albumId == null) throw StateError('the album has no id');

    final future = _albumTracks.putIfAbsent(album.key, () => _loadAllPages((page) => _api.albumAudios(albumId, page)));
    try {
      return await future;
    } catch (_) {
      if (identical(_albumTracks[album.key], future)) _albumTracks.remove(album.key);
      rethrow;
    }
  }

  /// Disc / track order when the audios carry those numbers, otherwise the server order.
  List<String> _inAlbumOrder(List<ArtistTrack> tracks) {
    final indexed = [for (var i = 0; i < tracks.length; i++) (i, tracks[i])];
    indexed.sort((a, b) {
      final byDisc = (a.$2.disc ?? 1 << 30).compareTo(b.$2.disc ?? 1 << 30);
      if (byDisc != 0) return byDisc;
      final byTrack = (a.$2.track ?? 1 << 30).compareTo(b.$2.track ?? 1 << 30);
      return byTrack != 0 ? byTrack : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2.id];
  }

  Future<void> _playAlbum(ArtistAlbum album) async {
    if (_busyAlbumKey != null) return;
    setState(() => _busyAlbumKey = album.key);

    try {
      final ids = _inAlbumOrder(await _audiosOf(album));
      if (!mounted) return;

      if (ids.isEmpty) {
        NotificationService.showError(message: 'No audios found for this album');
        return;
      }
      AudioPlayerService.play(audioIds: ids);
    } catch (e, st) {
      talker.error('caught error while trying to play an album', e, st);
      if (mounted) NotificationService.showError(message: 'Could not load the album');
    } finally {
      if (mounted) setState(() => _busyAlbumKey = null);
    }
  }

  /// Appends the album's audios to the player queue; the current track keeps playing.
  Future<void> _addAlbumToQueue(ArtistAlbum album) async {
    if (_queueingAlbumKey != null) return;
    setState(() => _queueingAlbumKey = album.key);

    try {
      final ids = _inAlbumOrder(await _audiosOf(album));
      if (!mounted) return;

      if (ids.isEmpty) {
        NotificationService.showError(message: 'No audios found for this album');
        return;
      }
      AudioPlayerService.add(audioIds: ids, play: false);
      NotificationService.showSuccess(message: ids.length == 1 ? 'Added 1 audio to the queue' : 'Added ${ids.length} audios to the queue');
    } catch (e, st) {
      talker.error('caught error while trying to queue an album', e, st);
      if (mounted) NotificationService.showError(message: 'Could not load the album');
    } finally {
      if (mounted) setState(() => _queueingAlbumKey = null);
    }
  }

  Future<void> _playAll() async {
    if (_playingAll) return;
    setState(() => _playingAll = true);

    try {
      final tracks = await _allArtistTracks();
      if (!mounted) return;

      if (tracks.isEmpty) {
        NotificationService.showError(message: 'This artist has no audios');
        return;
      }
      AudioPlayerService.play(audioIds: [for (final t in tracks) t.id]);
    } catch (e, st) {
      talker.error('caught error while trying to play all audios of an artist', e, st);
      if (mounted) NotificationService.showError(message: 'Could not load the audios');
    } finally {
      if (mounted) setState(() => _playingAll = false);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The banner runs behind the (transparent) app bar and the status bar.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        leading: context.canPop() ? const _BackButtonOnBanner() : null,
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_infoLoading) return const Center(child: CircularProgressIndicator());

    final artist = _artist;
    if (_infoFailed || artist == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Artist not found'),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: () => _loadInfo(showSpinner: true), child: const Text('Retry')),
          ],
        ),
      );
    }

    final theme = Theme.of(context);
    final headers = _headers;
    final albumsLabel = _albums.isEmpty && !_loadingAlbums
        ? null
        : '${_albums.length}${_hasMore ? '+' : ''} ${_albums.length == 1 && !_hasMore ? 'album' : 'albums'}';

    return RefreshIndicator(
      edgeOffset: MediaQuery.paddingOf(context).top,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _ArtistHeader(
              artistId: artist.id,
              name: artist.name,
              subtitle: albumsLabel,
              headers: headers,
              imageEpoch: _imageEpoch,
              playing: _playingAll,
              onPlay: _playAll,
              onEdit: _edit,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text('Albums', style: theme.textTheme.titleLarge),
            ),
          ),
          if (_albums.isEmpty && !_loadingAlbums && !_albumsFailed)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text('No albums', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.78,
                ),
                itemCount: _albums.length,
                itemBuilder: (context, i) {
                  final album = _albums[i];
                  return _AlbumCard(
                    album: album,
                    headers: headers,
                    busy: _busyAlbumKey == album.key,
                    queueing: _queueingAlbumKey == album.key,
                    onTap: () {
                      final onAlbumTap = widget.onAlbumTap;
                      if (onAlbumTap != null) {
                        onAlbumTap(album);
                      } else {
                        _playAlbum(album);
                      }
                    },
                    onPlay: () => _playAlbum(album),
                    onAddToQueue: () => _addAlbumToQueue(album),
                  );
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _AlbumsFooter(loading: _loadingAlbums, failed: _albumsFailed, onRetry: _loadAlbums),
          ),
          // Audios with this artist but no album.
          if (_singles.isNotEmpty || _loadingSingles || _singlesFailed) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Singles', style: theme.textTheme.titleLarge),
              ),
            ),
            SliverList.builder(
              itemCount: _singles.length,
              itemBuilder: (context, i) {
                final audio = _singles[i];
                return _SingleTile(audio: audio, onPlay: () => AudioPlayerService.add(audioId: audio.id));
              },
            ),
            SliverToBoxAdapter(
              child: _AlbumsFooter(loading: _loadingSingles, failed: _singlesFailed, onRetry: _loadSingles),
            ),
          ],
          // Keeps the last row clear of the mini player.
          const SliverToBoxAdapter(child: AudioDockSpacer()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: banner + circular avatar (Instagram style)
// ─────────────────────────────────────────────────────────────────────────────

class _ArtistHeader extends StatelessWidget {
  const _ArtistHeader({
    required this.artistId,
    required this.name,
    required this.subtitle,
    required this.headers,
    required this.imageEpoch,
    required this.playing,
    required this.onPlay,
    required this.onEdit,
  });

  final String artistId;
  final String name;
  final String? subtitle;
  final Map<String, String>? headers;

  /// Part of the images' keys: bumping it makes the avatar / banner load again.
  final int imageEpoch;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    const ring = 4.0; // surface-coloured ring around the avatar, like Instagram's

    // What is shown until the banner has loaded, or when the artist has none.
    final bannerFallback = SizedBox(
      width: double.infinity,
      height: kArtistBannerHeight + media.padding.top,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [theme.colorScheme.primaryContainer, theme.colorScheme.surfaceContainerHighest],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // The banner decides the height (its image at full width, aspect ratio kept); below it
              // there is room for the avatar's lower half.
              Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: media.size.height * kArtistBannerMaxHeightFactor),
                      child: Stack(
                        children: [
                          _AuthImage(
                            key: ValueKey('banner#$artistId#$imageEpoch'),
                            url: '${AppConfig.apiUrl}/api/artist/banner/$artistId',
                            headers: headers,
                            naturalHeight: true,
                            fallback: bannerFallback,
                          ),
                          // Dim fade into the page colour: transparent at the top, surface at 70% at the bottom.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [theme.colorScheme.surface.withValues(alpha: 0), theme.colorScheme.surface.withValues(alpha: 0.7)],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: kArtistAvatarRadius + ring),
                ],
              ),
              Positioned(
                left: 16,
                bottom: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.surface),
                  child: Padding(
                    padding: const EdgeInsets.all(ring),
                    child: ClipOval(
                      child: SizedBox(
                        width: kArtistAvatarRadius * 2,
                        height: kArtistAvatarRadius * 2,
                        child: _AuthImage(
                          key: ValueKey('avatar#$artistId#$imageEpoch'),
                          url: '${AppConfig.apiUrl}/api/artist/avatar/$artistId',
                          headers: headers,
                          fallback: ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.person, size: kArtistAvatarRadius, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.outlined(tooltip: 'Edit artist', icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: playing ? null : onPlay,
                      icon: playing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow_rounded),
                      label: const Text('Play'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Back button with a dark circle behind it, readable over any banner.
class _BackButtonOnBanner extends StatelessWidget {
  const _BackButtonOnBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: DecoratedBox(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black45),
        child: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Albums
// ─────────────────────────────────────────────────────────────────────────────

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album, required this.headers, required this.busy, required this.queueing, required this.onTap, required this.onPlay, required this.onAddToQueue});

  final ArtistAlbum album;
  final Map<String, String>? headers;

  /// This album's audios are being loaded to play it.
  final bool busy;

  /// This album's audios are being loaded to add them to the queue.
  final bool queueing;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onAddToQueue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.album, size: 48, color: theme.colorScheme.onSurfaceVariant)),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: album.id == null
                      ? placeholder
                      : _AuthImage(url: '${AppConfig.apiUrl}/api/album/avatar/${album.id}', headers: headers, fallback: placeholder),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Tooltip(
                    message: 'Add to queue',
                    child: Material(
                      color: theme.colorScheme.secondaryContainer,
                      elevation: 3,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: queueing ? null : onAddToQueue,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: queueing
                              ? Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.onSecondaryContainer),
                                )
                              : Icon(Icons.playlist_add, color: theme.colorScheme.onSecondaryContainer),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Tooltip(
                    message: 'Play album',
                    child: Material(
                      color: theme.colorScheme.primary,
                      elevation: 3,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: busy ? null : onPlay,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: busy
                              ? Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.onPrimary),
                                )
                              : Icon(Icons.play_arrow_rounded, color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(album.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

/// One row of the "Singles" section: tap to play it, the buttons add it to the queue / to a playlist.
class _SingleTile extends StatelessWidget {
  const _SingleTile({required this.audio, required this.onPlay});

  final Audio audio;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onPlay,
      leading: Thumb(url: '${AppConfig.apiUrl}/api/audio/coverArt/${audio.id}', icon: Icons.music_note),
      title: Text(audio.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: AudioRowActions(audioId: audio.id, initialPlaylistName: audio.title),
    );
  }
}

class _AlbumsFooter extends StatelessWidget {
  const _AlbumsFooter({required this.loading, required this.failed, required this.onRetry});

  final bool loading;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    if (failed) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image with the Authorization header (falls back when missing / failing)
// ─────────────────────────────────────────────────────────────────────────────

class _AuthImage extends StatelessWidget {
  const _AuthImage({super.key, required this.url, required this.headers, required this.fallback, this.naturalHeight = false});

  final String url;

  /// null while the token is still being read.
  final Map<String, String>? headers;
  final Widget fallback;

  /// false: fill the space it is given (cropped, BoxFit.cover).
  /// true: full width, as tall as the image is at that width (aspect ratio kept).
  final bool naturalHeight;

  @override
  Widget build(BuildContext context) {
    if (headers == null) return fallback;

    return Image.network(
      url,
      headers: headers,
      fit: naturalHeight ? BoxFit.fitWidth : BoxFit.cover,
      width: double.infinity,
      height: naturalHeight ? null : double.infinity,
      errorBuilder: (context, error, stack) => fallback,
      // Show the fallback (not an empty box) until the first frame arrives.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) => frame == null ? fallback : child,
    );
  }
}
