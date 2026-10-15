// edit_audio_notifier.dart
//
// Logic behind EditAudioPage: open an existing audio, or follow a queued upload
// (poll until it is processed, then load it), and save edits.
//
// The API methods return ApiCallResult. A failure there was already shown to the user as a
// toast (or is silent on purpose and shown on the page), so nothing here toasts it again.

import 'dart:async';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/pages/edit_audio/edit_audio_api.dart';
import 'package:avarim/pages/edit_audio/edit_audio_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const kPollInterval = Duration(seconds: 5);

/// Gives up waiting after this many polls (120 x 5s = 10 minutes).
const kMaxPollAttempts = 120;

class AudioUploadNotifier extends Notifier<UploadState> {
  Timer? _timer;
  CancelToken? _token;
  bool _checking = false;
  int _attempts = 0;
  int _consecutiveErrors = 0;

  AudioUploadApi get _api => ref.read(audioUploadApiProvider);

  @override
  UploadState build() {
    ref.onDispose(_stop);
    return const UploadState();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _token?.cancel();
    _token = null;
    _checking = false;
  }

  /// Back to the start (also cancels an in-flight upload / polling; a job
  /// already queued on the server keeps running).
  void reset() {
    _stop();
    state = const UploadState();
  }

  /// Opens an existing audio for editing.
  Future<void> openExisting(String audioId) async {
    _stop();
    final token = _token = CancelToken();
    state = UploadState(phase: UploadPhase.loading, id: audioId, existing: true);

    final result = await _api.getInfo(audioId, cancelToken: token);
    if (!ref.mounted || token.isCancelled) return;
    _showInfo(result);
  }

  /// Called once the upload was accepted by the server (the dialog's result is `{ id }`).
  void startProcessing(String id) {
    _stop();
    state = UploadState(phase: UploadPhase.processing, id: id);
    _startPolling();
  }

  /// After a failure: load the audio again / check the queued job again.
  void resume() {
    final id = state.id;
    if (id == null) return reset();

    if (state.existing) {
      unawaited(openExisting(id));
      return;
    }

    state = state.copyWith(phase: UploadPhase.processing, clearError: true);
    _startPolling();
    unawaited(_poll());
  }

  void _startPolling() {
    _timer?.cancel();
    _attempts = 0;
    _consecutiveErrors = 0;
    _timer = Timer.periodic(kPollInterval, (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    final id = state.id;
    if (_checking || id == null || state.phase != UploadPhase.processing) return;

    _checking = true;
    final token = _token = CancelToken();
    try {
      _attempts++;
      final result = await _api.isUploadFinished(id, cancelToken: token);
      if (!ref.mounted || token.isCancelled) return;

      if (result case ApiCallFailure(:final message)) {
        // A flaky network gets a couple of retries before the job is reported as failed.
        _consecutiveErrors++;
        if (_consecutiveErrors >= 3) {
          _timer?.cancel();
          _fail(message);
        }
        return;
      }
      _consecutiveErrors = 0;

      if (result.isSuccess) {
        // Finished.
        _timer?.cancel();
        final info = await _api.getInfo(id, cancelToken: token);
        if (!ref.mounted || token.isCancelled) return;
        _showInfo(info);
      } else if (_attempts >= kMaxPollAttempts) {
        _timer?.cancel();
        _fail('Timed out waiting for the upload to finish processing');
      }
    } finally {
      _checking = false;
    }
  }

  /// Shows the editor for a loaded audio, or the failure.
  void _showInfo(ApiCallResult<Map<String, dynamic>> result) {
    if (result case ApiCallFailure(:final message)) {
      _fail(message);
      return;
    }

    final audio = result.dataOrNull;
    if (audio == null) {
      _fail('The server did not return the audio.');
      return;
    }
    state = state.copyWith(phase: UploadPhase.editing, audio: audio);
  }

  void _fail(String message) {
    state = state.copyWith(phase: UploadPhase.failed, error: message);
  }

  /// Sends only what changed. Returns true on success (on failure the error was already shown).
  Future<bool> save({String? title, Map<String, dynamic>? tags}) async {
    final audio = state.audio;
    if (audio == null || state.isSaving) return false;

    state = state.copyWith(isSaving: true);
    final result = await _api.update(audioId: '${audio['_id']}', title: title, tags: tags);
    if (!ref.mounted) return !result.isFailure;

    if (result.isFailure) {
      state = state.copyWith(isSaving: false);
      return false;
    }

    final oldTags = (audio['tags'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    state = state.copyWith(
      isSaving: false,
      revision: state.revision + 1,
      audio: {
        ...audio,
        if (title != null) 'title': title,
        if (tags != null) 'tags': {...oldTags, ...tags},
      },
    );
    return true;
  }
}

/// autoDispose: leaving the page cancels polling.
final audioUploadProvider = NotifierProvider.autoDispose<AudioUploadNotifier, UploadState>(AudioUploadNotifier.new);
