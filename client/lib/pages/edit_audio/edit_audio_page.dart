// edit_audio_page.dart
//
// Two ways in (decided by the `audioId` query parameter):
//
//   EditAudioPage(audioId: 'abc')  -> edit an existing audio
//       GET  /api/audio/info?audioId=...  => { status: 'success', data: audio }
//
//   EditAudioPage()                -> upload a new audio, then edit it
//       1. AudioUploadDialog      -> POST /api/audio/  (multipart)   => { status: 'queued', data: { id } }
//       2. poll every 5 seconds   -> GET  /api/audio/is_upload_finished
//       3. when finished          -> GET  /api/audio/info?audioId=...
//
// Editing (both ways):
//   - cover art               -> GET / PUT /api/audio/coverArt/:audioId   (cover_art_section.dart)
//   - title + tags            (everything else is shown read-only)
//        title uniqueness     -> GET  /api/audio/is_title_unique (204 = free, 400 TITLE_NOT_UNIQUE)
//   - "Update"                -> POST /api/audio/  { updates: { audioId, title?, tags? } }
//
// Where things live (all in this folder, except the shared widgets in pages/common/):
//   edit_audio_api.dart       endpoints
//   edit_audio_state.dart     UploadState / UploadPhase
//   edit_audio_notifier.dart  polling, loading, saving
//   edit_audio_form.dart      the form (+ audio_tag_specs.dart, chip_list_field.dart)
//   cover_art_section.dart    cover art (GET / PUT)
//   pages/common/             error helpers, read-only details, image section

import 'dart:async';

import 'package:avarim/components/dialogs/upload/audio_upload_dialog.dart';
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/pages/edit_audio/batch_upload/batch_upload_notifier.dart';
import 'package:avarim/pages/edit_audio/batch_upload/batch_upload_view.dart';
import 'package:avarim/pages/edit_audio/batch_upload/picked_audio.dart';
import 'package:avarim/pages/edit_audio/cover_art_section.dart';
import 'package:avarim/pages/edit_audio/edit_audio_form.dart';
import 'package:avarim/pages/edit_audio/edit_audio_notifier.dart';
import 'package:avarim/pages/edit_audio/edit_audio_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class EditAudioPage extends ConsumerStatefulWidget {
  const EditAudioPage({super.key, this.audioId});

  /// The `audioId` query parameter. With an id the page edits that audio;
  /// without one it starts the upload flow.
  final String? audioId;

  @override
  ConsumerState<EditAudioPage> createState() => _EditAudioPageState();
}

class _EditAudioPageState extends ConsumerState<EditAudioPage> {
  bool get _hasId => widget.audioId != null && widget.audioId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(EditAudioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioId != widget.audioId) _open();
  }

  void _open() {
    final id = widget.audioId;
    // After the first build: providers can't be modified while the tree is building.
    Future.microtask(() {
      if (!mounted) return;
      final notifier = ref.read(audioUploadProvider.notifier);
      if (id != null && id.isNotEmpty) {
        unawaited(notifier.openExisting(id));
      } else {
        notifier.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(audioUploadProvider);
    final batch = ref.watch(batchUploadProvider);

    // A batch upload (batch_upload_notifier.dart) owns the page until the user opens one of its audios
    // with "Edit"; "Back to uploads" returns to it.
    final batchActive = !_hasId && batch.isActive;
    final showBatch = batchActive && s.phase == UploadPhase.idle;

    final Widget body = showBatch
        ? const BatchUploadView()
        : switch (s.phase) {
            // With an id, `idle` is only the frame before loading starts.
            UploadPhase.idle => _hasId ? const _LoadingStep() : const _StartStep(),
            UploadPhase.processing => _ProcessingStep(state: s),
            UploadPhase.loading => const _LoadingStep(),
            UploadPhase.failed => _FailedStep(state: s),
            UploadPhase.editing => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CoverArtSection(key: ValueKey('${s.audio!['_id']}'), audioId: '${s.audio!['_id']}'),
                const SizedBox(height: 24),
                EditAudioForm(key: ValueKey(s.revision), audio: s.audio!, isSaving: s.isSaving, isExisting: s.existing),
              ],
            ),
          };

    return Scaffold(
      appBar: AppBar(title: Text(_hasId ? 'Edit audio' : 'Upload audio')),
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight > 48 ? c.maxHeight - 48 : 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (batchActive && !showBatch)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: ref.read(audioUploadProvider.notifier).reset,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Back to uploads'),
                        ),
                      ),
                    body,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Steps: start / processing / loading / failed
// ─────────────────────────────────────────────────────────────────────────────

class _StartStep extends ConsumerWidget {
  const _StartStep();

  Future<void> _openDialog(BuildContext context, WidgetRef ref) async {
    // Not dismissible by tapping outside: that would drop the result of an upload still in flight.
    final result = await showDialog<dynamic>(context: context, barrierDismissible: false, builder: (_) => const AudioUploadDialog());
    if (!context.mounted) return;
    if (result == null) {
      NotificationService.showError(message: 'Id not found');
      return;
    }

    // The dialog pops with the response's `data`, i.e. `{ id }`.
    final id = result is Map ? result['id'] : null;
    if (id is! String || id.isEmpty) {
      NotificationService.showError(message: 'The upload was accepted, but the server did not return a id');
      return;
    }
    ref.read(audioUploadProvider.notifier).startProcessing(id);
  }

  /// Pick several files and upload them one after the other.
  Future<void> _uploadMany(BuildContext context, WidgetRef ref) async {
    final files = await pickAudioFiles();
    if (!context.mounted || files.isEmpty) return;
    unawaited(ref.read(batchUploadProvider.notifier).start(files));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.upload_file, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('Upload an audio file', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'The file is processed on the server. When it is done you can review and edit its title and tags.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: () => _openDialog(context, ref), icon: const Icon(Icons.upload), label: const Text('Upload audio')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _uploadMany(context, ref),
          icon: const Icon(Icons.library_music_outlined),
          label: const Text('Upload multiple audios'),
        ),
      ],
    );
  }
}

class _ProcessingStep extends ConsumerWidget {
  const _ProcessingStep({required this.state});
  final UploadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text('Processing audio…', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(state.id ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Text('Checking every ${kPollInterval.inSeconds} seconds. Keep this page open.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 24),
        OutlinedButton(onPressed: ref.read(audioUploadProvider.notifier).reset, child: const Text('Cancel')),
      ],
    );
  }
}

class _LoadingStep extends StatelessWidget {
  const _LoadingStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text('Loading audio…', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _FailedStep extends ConsumerWidget {
  const _FailedStep({required this.state});
  final UploadState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(audioUploadProvider.notifier);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text('Something went wrong', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(state.error ?? 'Unknown error', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [
            // A queued job can simply be checked again; an existing audio can be loaded again.
            if (state.id != null) FilledButton(onPressed: notifier.resume, child: Text(state.existing ? 'Try again' : 'Check again')),
            if (!state.existing) OutlinedButton(onPressed: notifier.reset, child: const Text('Start over')),
          ],
        ),
      ],
    );
  }
}
