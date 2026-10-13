import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:file_picker/file_picker.dart';

class AudioUploadDialog extends ConsumerStatefulWidget {
  const AudioUploadDialog({super.key});

  @override
  ConsumerState<AudioUploadDialog> createState() => _AudioUploadDialogState();
}

class _AudioUploadDialogState extends ConsumerState<AudioUploadDialog> {
  final titleController = TextEditingController();
  Player? _player;
  XFile? _audioFile;
  String? _fileName;

  bool _picking = false;
  bool _loading = false;
  bool _playing = false;

  @override
  void dispose() {
    titleController.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    setState(() => _picking = true);
    final result = await FilePicker.pickFiles(type: FileType.audio, allowMultiple: false, withData: kIsWeb);
    if (!mounted) return;
    setState(() => _picking = false);
    if (result == null) return;

    final picked = result.files.single;

    final XFile xFile;
    if (kIsWeb) {
      final bytes = picked.bytes;
      if (bytes == null) return;
      xFile = XFile.fromData(bytes, name: picked.name, length: bytes.length);
    } else {
      final path = picked.path;
      if (path == null) return;
      xFile = XFile(path, name: picked.name);
    }

    await _player?.dispose();
    final player = Player();
    await player.open(Media(xFile.path), play: false);

    player.stream.playing.listen((playing) {
      if (mounted) setState(() => _playing = playing);
    });

    setState(() {
      _audioFile = xFile;
      _fileName = picked.name;
      _player = player;

      List<String> split = picked.name.split('.');
      split.removeLast();
      titleController.text = split.join(' ');
    });
  }

  bool isButtonDisabled() => _audioFile == null || titleController.text.trim().isEmpty;

  Future<void> _upload() async {
    if (isButtonDisabled()) return;
    setState(() => _loading = true);

    try {
      final form = FormData.fromMap({'file': MultipartFile.fromStream(() => _audioFile!.openRead(), await _audioFile!.length(), filename: _audioFile!.name)});
      final result = await apiCall(() => ref.read(authDioProvider).post('/api/audio/', data: form, queryParameters: {'title': titleController.text.trim()}));
      if (!mounted) return;
      if (result.isFailure || result.dataOrNull == null) return;

      Navigator.pop(context, result.dataOrNull);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _togglePlay() async {
    if (_player == null) return;

    if (_playing) {
      await _player!.pause();
    } else {
      await _player!.play();
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
              const Text('Upload Audio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

              const SizedBox(height: 20),

              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: l10n.title),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _audioFile == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _picking
                              ? SizedBox(height: 40, width: 40, child: CircularProgressIndicator(strokeWidth: 2))
                              : Center(child: Text(l10n.audio_not_selected)),
                        ],
                      )
                    : Column(
                        children: [
                          const Icon(Icons.audio_file, size: 48),

                          const SizedBox(height: 12),

                          Text(_fileName ?? '', textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),

                          const SizedBox(height: 12),

                          IconButton(onPressed: _togglePlay, icon: Icon(_playing ? Icons.pause : Icons.play_arrow)),
                        ],
                      ),
              ),

              const SizedBox(height: 16),

              TextButton.icon(onPressed: _pickAudio, icon: const Icon(Icons.library_music), label: Text(l10n.choose_audio)),

              const SizedBox(height: 16),

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
