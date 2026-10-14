import 'dart:io';
import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class ImageUploadDialog extends ConsumerStatefulWidget {
  const ImageUploadDialog({super.key, this.showTitle = true, this.onUpload});

  /// Show the title field and require it before uploading. Turn off when the image
  /// has no title of its own (e.g. an audio's cover art).
  final bool showTitle;

  /// Replaces the default upload (`POST /api/image/`). Receives the picked image and the
  /// title (empty when [showTitle] is false). Return a non-null value to close the dialog
  /// with it, or null to keep the dialog open (e.g. after showing your own error).
  final Future<Object?> Function(XFile image, String title)? onUpload;

  @override
  ConsumerState<ImageUploadDialog> createState() => _ImageUploadDialogState();
}

class _ImageUploadDialogState extends ConsumerState<ImageUploadDialog> {
  final titleController = TextEditingController();
  XFile? _image;
  bool _loading = false;

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();

    final XFile? picked = await picker.pickImage(source: source, imageQuality: 85);

    if (picked == null) return;

    setState(() {
      _image = picked;
      List<String> split = picked.name.split('.');
      split.removeLast();
      titleController.text = split.join(' ');
    });
  }

  bool isButtonDisabled() => _image == null || (widget.showTitle && titleController.text.trim().isEmpty);

  Future<void> _upload() async {
    if (isButtonDisabled()) return;

    setState(() => _loading = true);

    try {
      final title = titleController.text.trim();

      final Object? data;
      if (widget.onUpload != null) {
        data = await widget.onUpload!(_image!, title);
      } else {
        final form = FormData.fromMap({'file': MultipartFile.fromStream(() => _image!.openRead(), await _image!.length(), filename: _image!.name)});
        final result = await apiCall(
          () => ref.read(authDioProvider).post('/api/image/', data: form, queryParameters: {'title': title, 'fileName': _image!.name}),
        );
        data = result.isFailure ? null : result.dataOrNull;
      }

      if (!mounted || data == null) return;

      Navigator.pop(context, data);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.upload_image, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              const SizedBox(height: 16),

              if (widget.showTitle) ...[
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: l10n.title),
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: 16),
              ],

              // Preview
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outline),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _image == null
                    ? Center(child: Text(l10n.image_not_selected))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb ? Image.network(_image!.path, fit: BoxFit.fitWidth) : Image.file(File(_image!.path), fit: BoxFit.fitWidth),
                      ),
              ),

              const SizedBox(height: 16),

              // Buttons: pick image
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton.icon(onPressed: () => _pickImage(ImageSource.gallery), icon: const Icon(Icons.photo), label: Text(l10n.gallery)),

                  TextButton.icon(onPressed: () => _pickImage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: Text(l10n.camera)),
                ],
              ),

              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: _loading ? null : () => Navigator.pop(context), child: Text(l10n.cancel)),

                  const SizedBox(width: 8),

                  Button(
                    type: ButtonType.elevated,
                    color: theme.colorScheme.secondary,
                    onPressed: isButtonDisabled() ? null : _upload,
                    isLoading: _loading,
                    label: l10n.upload,
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
