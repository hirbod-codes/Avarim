// picked_audio.dart
//
// A file chosen for upload, and the file picker call that produces them.
// This is the ONLY place that depends on file_picker: if your AudioUploadDialog picks files differently,
// adapt `pickAudioFiles` (the rest of the batch upload only sees PickedAudio).

import 'package:avarim/components/dialogs/upload/audio_upload_dialog.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class PickedAudio {
  const PickedAudio({required this.name, required this.size, required this.toMultipart});

  final String name;
  final int size;

  /// Builds the multipart part. Called once per upload attempt, so a retry re-reads the file.
  final Future<MultipartFile> Function() toMultipart;
}

/// Lets the user pick one or more audio files. Empty list = cancelled.
///
/// Native: streams from the file path (no whole-file copy in memory).
/// Web: there is no path, so the bytes are loaded (`withData`).
Future<List<PickedAudio>> pickAudioFiles() async {
  final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: audioExtensions, allowMultiple: true, withData: kIsWeb);
  if (result == null) return const [];

  return [
    for (final f in result.files)
      if (kIsWeb ? f.bytes != null : f.path != null)
        PickedAudio(
          name: f.name,
          size: f.size,
          toMultipart: () async {
            if (kIsWeb) return MultipartFile.fromBytes(f.bytes!, filename: f.name);
            return MultipartFile.fromFile(f.path!, filename: f.name);
          },
        ),
  ];
}
