// edit_album_page.dart
//
// Edit page of an album. The id comes from the `albumId` query parameter; without one the page first
// asks for a name, creates the album, and continues with the id the server returns:
//
//   GoRoute(path: '/album/edit', builder: (context, state) => EditAlbumPage(albumId: state.uri.queryParameters['albumId']))
//
//   - images        -> GET / PUT /api/album/avatar/:albumId   (pages/common/image_section.dart)
//   - name          -> PATCH /api/album/name  { albumId, albumName }
//   - "Danger zone" -> delete all the album's audios, one by one (delete_album_audios_section.dart)
//   - everything else is shown read-only
//
// Where things live (all in this folder, except the shared widgets in pages/common/):
//   edit_album_api.dart       endpoints
//   edit_album_state.dart     EditAlbumState / EditAlbumPhase
//   edit_album_notifier.dart  load + save
//   edit_album_form.dart      name field, read-only details, Update button

import 'dart:async';

import 'package:avarim/pages/common/image_section.dart';
import 'package:avarim/pages/edit_album/delete_album_audios_section.dart';
import 'package:avarim/pages/edit_album/edit_album_api.dart';
import 'package:avarim/pages/edit_album/edit_album_form.dart';
import 'package:avarim/pages/edit_album/edit_album_notifier.dart';
import 'package:avarim/pages/edit_album/edit_album_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class EditAlbumPage extends ConsumerStatefulWidget {
  const EditAlbumPage({super.key, this.albumId});

  /// The `albumId` query parameter. Without one there is nothing to edit.
  final String? albumId;

  @override
  ConsumerState<EditAlbumPage> createState() => _EditAlbumPageState();
}

class _EditAlbumPageState extends ConsumerState<EditAlbumPage> {
  bool get _hasId => widget.albumId != null && widget.albumId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(EditAlbumPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.albumId != widget.albumId) _open();
  }

  void _open() {
    final id = widget.albumId;
    if (id == null || id.isEmpty) return;

    // After the first build: providers can't be modified while the tree is building.
    Future.microtask(() {
      if (!mounted) return;
      unawaited(ref.read(editAlbumProvider.notifier).open(id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(editAlbumProvider);

    final Widget body;
    if (!_hasId && s.id == null) {
      // No id was given and none was created yet: ask for a name and create it.
      body = const _CreateStep();
    } else {
      body = switch (s.phase) {
        EditAlbumPhase.loading => const _LoadingStep(),
        EditAlbumPhase.failed => _FailedStep(error: s.error),
        EditAlbumPhase.editing => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ImageSection(path: albumAvatarPath(s.id!), title: 'Avatar', hint: 'Shown next to this album in lists.'),
            const SizedBox(height: 24),
            EditAlbumForm(key: ValueKey(s.revision), album: s.album!, isSaving: s.isSaving),
            const SizedBox(height: 32),
            DeleteAlbumAudiosSection(albumId: s.id!, albumName: '${s.album!['name'] ?? ''}'),
          ],
        ),
      };
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit album')),
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight > 48 ? c.maxHeight - 48 : 0),
            child: Center(
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Steps: loading / failed / create
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingStep extends StatelessWidget {
  const _LoadingStep();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 48, height: 48, child: CircularProgressIndicator()),
        const SizedBox(height: 24),
        Text('Loading album…', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _FailedStep extends ConsumerWidget {
  const _FailedStep({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text('Something went wrong', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(error ?? 'Unknown error', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        FilledButton(onPressed: () => ref.read(editAlbumProvider.notifier).retry(), child: const Text('Try again')),
      ],
    );
  }
}

class _CreateStep extends ConsumerStatefulWidget {
  const _CreateStep();

  @override
  ConsumerState<_CreateStep> createState() => _CreateStepState();
}

class _CreateStepState extends ConsumerState<_CreateStep> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(editAlbumProvider.notifier).create(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creating = ref.watch(editAlbumProvider.select((s) => s.isCreating));

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_add, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Create an album', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Give the album a name. You can add images and edit the details right after.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _name,
            enabled: !creating,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _create(),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Name is required' : null,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: creating ? null : _create,
            icon: creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
            label: const Text('Create album'),
          ),
        ],
      ),
    );
  }
}
