import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoUploadDialog extends ConsumerStatefulWidget {
  const VideoUploadDialog({super.key});

  @override
  ConsumerState<VideoUploadDialog> createState() => _VideoUploadDialogState();
}

class _VideoUploadDialogState extends ConsumerState<VideoUploadDialog> {
  final ImagePicker _picker = ImagePicker();
  final titleController = TextEditingController();
  final ValueNotifier<bool> _titleHasText = ValueNotifier(false);

  Player? _player;
  VideoController? _controller;

  XFile? _videoFile; // replaces both _videoFile (File) and _videoBytes

  bool _picking = false;
  bool _loading = false;

  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    titleController.addListener(() {
      _titleHasText.value = titleController.text.trim().isNotEmpty;
    });
  }

  @override
  void dispose() {
    titleController.dispose();
    _titleHasText.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo(ImageSource source) async {
    if (_picking) return;

    setState(() => _picking = true);

    try {
      final XFile? picked = await _picker
          .pickVideo(source: source, maxDuration: const Duration(minutes: 10))
          .timeout(const Duration(minutes: 2), onTimeout: () => null);
      if (!mounted || picked == null) return;

      final player = Player();
      final controller = VideoController(player);
      await player.open(Media(picked.path)); // blob: URL on web, file path on native

      if (!mounted) {
        await player.dispose();
        return;
      }

      final oldPlayer = _player;

      setState(() {
        _videoFile = picked;
        _player = player;
        _controller = controller;
        List<String> split = picked.name.split('.');
        split.removeLast();
        titleController.text = split.join(' ');
      });

      await oldPlayer?.dispose();
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  bool isButtonDisabled() => _videoFile == null || titleController.text.trim().isEmpty;

  Future<void> _upload() async {
    if (isButtonDisabled()) return;

    setState(() {
      _loading = true;
      _uploadProgress = 0;
    });

    try {
      final form = FormData.fromMap({'file': MultipartFile.fromStream(() => _videoFile!.openRead(), await _videoFile!.length(), filename: _videoFile!.name)});
      final result = await apiCall(
        () => ref.read(authDioProvider).post('/api/video/', data: form, queryParameters: {'title': titleController.text.trim(), 'fileName': _videoFile!.name}),
      );
      if (!mounted) return;
      if (result.isFailure || result.dataOrNull == null) return;

      Navigator.pop(context, result.dataOrNull);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _uploadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_uploadProgress != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: _uploadProgress! > 0 ? _uploadProgress : null, minHeight: 6),
                ),
                const SizedBox(height: 12),
              ],

              Text(l10n.upload_video, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              const SizedBox(height: 16),

              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: l10n.title),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 16),

              // Preview
              Container(
                height: 260,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _controller == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _picking
                              ? SizedBox(height: 40, width: 40, child: CircularProgressIndicator(strokeWidth: 2))
                              : Center(child: Text(l10n.video_not_selected)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Video(controller: _controller!, fit: BoxFit.contain),
                      ),
              ),

              const SizedBox(height: 16),

              // Pick buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(
                    onPressed: _loading ? null : () => _pickVideo(ImageSource.gallery),
                    icon: const Icon(Icons.video_library),
                    label: Text(l10n.gallery),
                  ),

                  TextButton.icon(
                    onPressed: _loading ? null : () => _pickVideo(ImageSource.camera),
                    icon: const Icon(Icons.videocam),
                    label: Text(l10n.cancel),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: Text(l10n.cancel)),

                  const SizedBox(width: 8),

                  ValueListenableBuilder<bool>(
                    valueListenable: _titleHasText,
                    builder: (context, hasText, _) {
                      return Button(
                        type: ButtonType.elevated,
                        color: theme.colorScheme.secondary,
                        onPressed: isButtonDisabled() ? null : _upload,
                        isLoading: _loading,
                        label: l10n.upload,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
