// image_section.dart
//
// Card that shows an image and lets the user replace it. Used for an audio's cover art,
// and an artist's / album's avatar and an artist's banner:
//
//   GET {path}   -> image bytes (404 / empty body = no image yet)
//   PUT {path}   -> multipart, field [kImageFieldName]
//
// Picking / previewing is done by ImageUploadDialog (gallery / camera); its default upload
// is replaced by the PUT above. Requests go through authDioProvider (base URL + auth).
//
//   - PUT goes through apiCall: a failure is already shown to the user (GlobalErrorInterceptor).
//   - GET returns raw image bytes, which apiCall's `{ status, data }` envelope can't represent,
//     so it stays a plain Dio call; its errors are shown inline on the card
//     and marked silent so cancelled / failed loads don't toast.

import 'dart:async';
import 'dart:typed_data';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/api/dio/global_error_interceptor.dart';
import 'package:avarim/components/dialogs/upload/image_upload_dialog.dart';
import 'package:avarim/lib/talker.dart';
import 'package:avarim/pages/common/edit_errors.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config (assumptions - customize)
// ─────────────────────────────────────────────────────────────────────────────

/// Name of the multipart field that carries the image on PUT.
const kImageFieldName = 'file';

// ─────────────────────────────────────────────────────────────────────────────
// API
// ─────────────────────────────────────────────────────────────────────────────

class ImageApi {
  ImageApi(this._dio);
  final Dio _dio;

  /// The current image, or null when there is none.
  Future<Uint8List?> get(String path, {CancelToken? cancelToken}) async {
    final res = await _dio.get<List<int>>(
      path,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (s) => s != null && (s < 300 || s == 404),
        extra: {GlobalErrorInterceptor.silentErrorsKey: true},
      ),
    );

    final data = res.data;
    if (res.statusCode == 404 || data == null || data.isEmpty) return null;
    return Uint8List.fromList(data);
  }

  /// Replaces the image. On failure the error was already shown (see the header).
  Future<ApiCallResult<dynamic>> put(String path, XFile image) {
    return apiCall<dynamic>(() async {
      final part = MultipartFile.fromStream(() => image.openRead(), await image.length(), filename: image.name);

      return _dio.put<dynamic>(
        path,
        data: FormData.fromMap({kImageFieldName: part}),
        options: Options(sendTimeout: Duration.zero, receiveTimeout: const Duration(minutes: 2)),
      );
    });
  }
}

final imageApiProvider = Provider<ImageApi>((ref) => ImageApi(ref.watch(authDioProvider)));

// ─────────────────────────────────────────────────────────────────────────────
// Widget
// ─────────────────────────────────────────────────────────────────────────────

class ImageSection extends ConsumerStatefulWidget {
  const ImageSection({super.key, required this.path, required this.title, this.hint, this.aspectRatio = 1});

  /// GET / PUT path of the image, e.g. `/api/audio/coverArt/:audioId`.
  final String path;

  /// Card title, e.g. "Cover art", "Avatar", "Banner".
  final String title;
  final String? hint;

  /// 1 = square preview next to the buttons; wider images get a full-width preview above them.
  final double aspectRatio;

  @override
  ConsumerState<ImageSection> createState() => _ImageSectionState();
}

class _ImageSectionState extends ConsumerState<ImageSection> {
  static const double _squareSize = 120;

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
  void didUpdateWidget(ImageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) unawaited(_load());
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
      final bytes = await ref.read(imageApiProvider).get(widget.path, cancelToken: token);
      if (!mounted || token.isCancelled) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e, st) {
      if (!mounted || isCancel(e)) return;
      talker.error('image fetch failed (${widget.path})', e, st);
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _change() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(imageApiProvider);
    final path = widget.path;
    final title = widget.title;

    // ImageUploadDialog does the picking (gallery / camera), the preview and the loading state.
    // Its default upload (POST /api/image/) is replaced by the PUT; the dialog closes once
    // this returns a non-null value.
    final uploaded = await showDialog<dynamic>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageUploadDialog(
        showTitle: false,
        onUpload: (image, _) async {
          final result = await api.put(path, image);
          // On failure the error was already shown: keep the dialog open so the user can retry.
          return result.isFailure ? null : true;
        },
      ),
    );
    if (uploaded == null || !mounted) return;

    // Thumbnails elsewhere (search list) load this same URL; drop their cached copy.
    await NetworkImage(path).evict();

    messenger.showSnackBar(SnackBar(content: Text('$title updated')));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final square = widget.aspectRatio == 1;
    final name = widget.title.toLowerCase();

    final String? hint = _failed ? "Couldn't load the image." : (_bytes == null && !_loading ? 'Nothing here yet.' : widget.hint);

    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.image_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant)),
    );

    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_bytes != null) Image.memory(_bytes!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (context, error, stack) => placeholder) else placeholder,
          if (_loading)
            const ColoredBox(
              color: Colors.black38,
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: theme.textTheme.titleMedium),
        if (hint != null && hint.isNotEmpty) ...[const SizedBox(height: 4), Text(hint, style: theme.textTheme.bodySmall)],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _loading ? null : _change,
              icon: const Icon(Icons.image_outlined),
              label: Text(_bytes == null ? 'Add $name' : 'Change $name'),
            ),
            if (_failed) TextButton(onPressed: _loading ? null : _load, child: const Text('Retry')),
          ],
        ),
      ],
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: square
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: _squareSize, height: _squareSize, child: preview),
                  const SizedBox(width: 16),
                  Expanded(child: info),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(aspectRatio: widget.aspectRatio, child: preview),
                  const SizedBox(height: 16),
                  info,
                ],
              ),
      ),
    );
  }
}
