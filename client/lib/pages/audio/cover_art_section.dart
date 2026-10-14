// cover_art_section.dart
//
// Shows an audio's cover art and lets the user replace it.
//
//   GET /api/audio/coverArt/:audioId   -> image bytes (404 / empty body = no cover art yet)
//   PUT /api/audio/coverArt/:audioId   -> multipart, field [kCoverArtFieldName]
//
// Picking / previewing the image is done by ImageUploadDialog (gallery / camera); its upload step
// is replaced by the PUT above. Requests go through authDioProvider (base URL + auth), and the
// current image is shown with Image.memory (no auth headers needed on the image).

import 'dart:async';
import 'dart:typed_data';

import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/components/dialogs/upload/image_upload_dialog.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/lib/talker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

String coverArtPath(String audioId) => '/api/audio/coverArt/$audioId';

/// Name of the multipart field that carries the image on PUT.
const kCoverArtFieldName = 'file';

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class CoverArtApi {
  CoverArtApi(this._dio);
  final Dio _dio;

  /// The current cover art, or null when the audio has none.
  Future<Uint8List?> get(String audioId, {CancelToken? cancelToken}) async {
    final res = await _dio.get<List<int>>(
      coverArtPath(audioId),
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.bytes, validateStatus: (s) => s != null && (s < 300 || s == 404)),
    );

    final data = res.data;
    if (res.statusCode == 404 || data == null || data.isEmpty) return null;
    return Uint8List.fromList(data);
  }

  Future<void> put(String audioId, XFile image) async {
    final part = MultipartFile.fromStream(() => image.openRead(), await image.length(), filename: image.name);

    await _dio.put<dynamic>(
      coverArtPath(audioId),
      data: FormData.fromMap({kCoverArtFieldName: part}),
      options: Options(sendTimeout: Duration.zero, receiveTimeout: const Duration(minutes: 2)),
    );
  }
}

final coverArtApiProvider = Provider<CoverArtApi>((ref) => CoverArtApi(ref.watch(authDioProvider)));

String _errorText(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'] ?? data['error'] ?? data['error_code'];
      if (message is String && message.isNotEmpty) return message;
    }
    return e.message ?? 'Request failed';
  }
  return e.toString();
}

bool _isCancel(Object e) => e is DioException && CancelToken.isCancel(e);

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class CoverArtSection extends ConsumerStatefulWidget {
  const CoverArtSection({super.key, required this.audioId});

  final String audioId;

  @override
  ConsumerState<CoverArtSection> createState() => _CoverArtSectionState();
}

class _CoverArtSectionState extends ConsumerState<CoverArtSection> {
  static const double _size = 120;

  Uint8List? _bytes;
  bool _loading = true;
  bool _failed = false;
  CancelToken? _token;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(CoverArtSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioId != widget.audioId) unawaited(_load());
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _token?.cancel();
    final token = _token = CancelToken();
    setState(() {
      _loading = true;
      _failed = false;
    });

    try {
      final bytes = await ref.read(coverArtApiProvider).get(widget.audioId, cancelToken: token);
      if (!mounted || token.isCancelled) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted || _isCancel(e)) return;
      talker.error('cover art fetch failed', e, st);
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _change() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(coverArtApiProvider);

    // ImageUploadDialog does the picking (gallery / camera), the preview and the loading state.
    // Its default upload (POST /api/image/) is replaced by the cover art PUT; the dialog closes
    // once this returns a non-null value.
    final uploaded = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageUploadDialog(
        showTitle: false,
        onUpload: (image, title) async {
          try {
            await api.put(widget.audioId, image);
            return true;
          } catch (e, st) {
            talker.error('cover art update failed', e, st);
            NotificationService.showError(message: _errorText(e));
            return null; // keep the dialog open so the user can retry
          }
        },
      ),
    );
    if (uploaded == null || !mounted) return;

    // Thumbnails elsewhere (search list) load this same URL; drop their cached copy.
    await NetworkImage(coverArtPath(widget.audioId)).evict();

    messenger.showSnackBar(const SnackBar(content: Text('Cover art updated')));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _loading;

    final String hint;
    if (_failed) {
      hint = "Couldn't load the cover art.";
    } else if (_bytes == null && !_loading) {
      hint = 'No cover art yet.';
    } else {
      hint = 'Shown next to this audio in lists and in the player.';
    }

    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.album, size: 48, color: theme.colorScheme.onSurfaceVariant)),
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _size,
              height: _size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_bytes != null)
                      Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (context, error, stack) => placeholder)
                    else
                      placeholder,
                    if (busy)
                      const ColoredBox(
                        color: Colors.black38,
                        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cover art', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(hint, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: busy ? null : _change,
                        icon: const Icon(Icons.image_outlined),
                        label: Text(_bytes == null ? 'Add cover art' : 'Change cover art'),
                      ),
                      if (_failed) TextButton(onPressed: _loading ? null : _load, child: const Text('Retry')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
