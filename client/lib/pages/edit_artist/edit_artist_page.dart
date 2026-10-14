// edit_artist_page.dart
//
// Edit page of an artist. The id comes from the `artistId` query parameter; without one the page first
// asks for a name, creates the artist, and continues with the id the server returns:
//
//   GoRoute(path: '/artist/edit', builder: (context, state) => EditArtistPage(artistId: state.uri.queryParameters['artistId']))
//
//   - images        -> GET / PUT /api/artist/avatar/:artistId and /api/artist/banner/:artistId   (pages/common/image_section.dart)
//   - name          -> POST /api/artist/  { updates: { artistId, name } }
//   - everything else is shown read-only
//
// Where things live (all in this folder, except the shared widgets in pages/common/):
//   edit_artist_api.dart       endpoints
//   edit_artist_state.dart     EditArtistState / EditArtistPhase
//   edit_artist_notifier.dart  load + save
//   edit_artist_form.dart      name field, read-only details, Update button

import 'dart:async';

import 'package:avarim/pages/common/image_section.dart';
import 'package:avarim/pages/edit_artist/edit_artist_api.dart';
import 'package:avarim/pages/edit_artist/edit_artist_form.dart';
import 'package:avarim/pages/edit_artist/edit_artist_notifier.dart';
import 'package:avarim/pages/edit_artist/edit_artist_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class EditArtistPage extends ConsumerStatefulWidget {
  const EditArtistPage({super.key, this.artistId});

  /// The `artistId` query parameter. Without one there is nothing to edit.
  final String? artistId;

  @override
  ConsumerState<EditArtistPage> createState() => _EditArtistPageState();
}

class _EditArtistPageState extends ConsumerState<EditArtistPage> {
  bool get _hasId => widget.artistId != null && widget.artistId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(EditArtistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistId != widget.artistId) _open();
  }

  void _open() {
    final id = widget.artistId;
    if (id == null || id.isEmpty) return;

    // After the first build: providers can't be modified while the tree is building.
    Future.microtask(() {
      if (!mounted) return;
      unawaited(ref.read(editArtistProvider.notifier).open(id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(editArtistProvider);

    final Widget body;
    if (!_hasId && s.id == null) {
      // No id was given and none was created yet: ask for a name and create it.
      body = const _CreateStep();
    } else {
      body = switch (s.phase) {
        EditArtistPhase.loading => const _LoadingStep(),
        EditArtistPhase.failed => _FailedStep(error: s.error),
        EditArtistPhase.editing => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ImageSection(path: artistAvatarPath(s.id!), title: 'Avatar', hint: 'Shown next to this artist in lists.'),
            const SizedBox(height: 24),
            ImageSection(path: artistBannerPath(s.id!), title: 'Banner', hint: 'Wide image shown at the top of the artist.', aspectRatio: 3),
            const SizedBox(height: 24),
            EditArtistForm(key: ValueKey(s.revision), artist: s.artist!, isSaving: s.isSaving),
          ],
        ),
      };
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit artist')),
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
        Text('Loading artist…', style: Theme.of(context).textTheme.titleLarge),
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
        FilledButton(onPressed: () => ref.read(editArtistProvider.notifier).retry(), child: const Text('Try again')),
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
    await ref.read(editArtistProvider.notifier).create(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creating = ref.watch(editArtistProvider.select((s) => s.isCreating));

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_add_alt_1, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Create an artist', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Give the artist a name. You can add images and edit the details right after.',
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
            label: const Text('Create artist'),
          ),
        ],
      ),
    );
  }
}
