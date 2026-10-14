// edit_artist_state.dart
//
// State of the edit artist page (see edit_artist_notifier.dart).

enum EditArtistPhase { loading, failed, editing }

class EditArtistState {
  const EditArtistState({
    this.phase = EditArtistPhase.loading,
    this.id,
    this.artist,
    this.error,
    this.isSaving = false,
    this.isCreating = false,
    this.revision = 0,
  });

  final EditArtistPhase phase;

  /// Id of the artist being edited: the one given to the page, or the one the server returned
  /// after creating it. Null while the page is still asking for a name to create one.
  final String? id;

  /// The artist document returned by `/info` (kept up to date after saves).
  final Map<String, dynamic>? artist;
  final String? error;
  final bool isSaving;

  /// The create request is in flight.
  final bool isCreating;

  /// Bumped after each successful save so the form re-initializes from the new values.
  final int revision;

  EditArtistState copyWith({
    EditArtistPhase? phase,
    String? id,
    Map<String, dynamic>? artist,
    String? error,
    bool clearError = false,
    bool? isSaving,
    bool? isCreating,
    int? revision,
  }) => EditArtistState(
    phase: phase ?? this.phase,
    id: id ?? this.id,
    artist: artist ?? this.artist,
    error: clearError ? null : (error ?? this.error),
    isSaving: isSaving ?? this.isSaving,
    isCreating: isCreating ?? this.isCreating,
    revision: revision ?? this.revision,
  );
}
