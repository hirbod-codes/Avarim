// edit_audio_state.dart
//
// State of EditAudioPage (see edit_audio_notifier.dart).

enum UploadPhase { idle, processing, loading, failed, editing }

class UploadState {
  const UploadState({this.phase = UploadPhase.idle, this.id, this.audio, this.error, this.isSaving = false, this.revision = 0, this.existing = false});

  final UploadPhase phase;

  /// Id of the audio being uploaded / edited (used for polling / info).
  final String? id;

  /// The audio document returned by `/info` (kept up to date after saves).
  final Map<String, dynamic>? audio;
  final String? error;
  final bool isSaving;

  /// Bumped after each successful save so the form re-initializes from the new values.
  final int revision;

  /// True when an existing audio was opened by id (no upload flow).
  final bool existing;

  UploadState copyWith({
    UploadPhase? phase,
    String? id,
    Map<String, dynamic>? audio,
    String? error,
    bool clearError = false,
    bool? isSaving,
    int? revision,
    bool? existing,
  }) => UploadState(
    phase: phase ?? this.phase,
    id: id ?? this.id,
    audio: audio ?? this.audio,
    error: clearError ? null : (error ?? this.error),
    isSaving: isSaving ?? this.isSaving,
    revision: revision ?? this.revision,
    existing: existing ?? this.existing,
  );
}
