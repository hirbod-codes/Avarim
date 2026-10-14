// edit_album_state.dart
//
// State of the edit album page (see edit_album_notifier.dart).

enum EditAlbumPhase { loading, failed, editing }

class EditAlbumState {
  const EditAlbumState({
    this.phase = EditAlbumPhase.loading,
    this.id,
    this.album,
    this.error,
    this.isSaving = false,
    this.isCreating = false,
    this.revision = 0,
  });

  final EditAlbumPhase phase;

  /// Id of the album being edited: the one given to the page, or the one the server returned
  /// after creating it. Null while the page is still asking for a name to create one.
  final String? id;

  /// The album document returned by `/info` (kept up to date after saves).
  final Map<String, dynamic>? album;
  final String? error;
  final bool isSaving;

  /// The create request is in flight.
  final bool isCreating;

  /// Bumped after each successful save so the form re-initializes from the new values.
  final int revision;

  EditAlbumState copyWith({
    EditAlbumPhase? phase,
    String? id,
    Map<String, dynamic>? album,
    String? error,
    bool clearError = false,
    bool? isSaving,
    bool? isCreating,
    int? revision,
  }) => EditAlbumState(
    phase: phase ?? this.phase,
    id: id ?? this.id,
    album: album ?? this.album,
    error: clearError ? null : (error ?? this.error),
    isSaving: isSaving ?? this.isSaving,
    isCreating: isCreating ?? this.isCreating,
    revision: revision ?? this.revision,
  );
}
