// edit_artist_form.dart
//
// Form of the edit artist page: the name, the read-only details and the Update button
// (enabled only when the name changed).

import 'package:avarim/pages/common/read_only_details.dart';
import 'package:avarim/pages/edit_artist/edit_artist_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditArtistForm extends ConsumerStatefulWidget {
  const EditArtistForm({super.key, required this.artist, required this.isSaving});

  final Map<String, dynamic> artist;
  final bool isSaving;

  @override
  ConsumerState<EditArtistForm> createState() => _EditArtistFormState();
}

class _EditArtistFormState extends ConsumerState<EditArtistForm> {
  final _formKey = GlobalKey<FormState>();

  late final String _baseName;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _baseName = (widget.artist['name'] as String? ?? '').trim();
    _name = TextEditingController(text: _baseName)..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Only a changed, non-empty name is sent.
  bool get _dirty {
    final n = _name.text.trim();
    return n.isNotEmpty && n != _baseName;
  }

  String? _validateName(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Name is required';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // The form is rebuilt after a successful save, so grab the messenger first.
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref.read(editArtistProvider.notifier).save(name: _name.text.trim());
    if (ok) messenger.showSnackBar(const SnackBar(content: Text('Artist updated')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _dirty && !widget.isSaving;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review & edit', style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            validator: _validateName,
            decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          ReadOnlyDetails(
            data: widget.artist,
            // `name` is editable above; the schema bookkeeping isn't useful here.
            hiddenKeys: const {'name', 'schemaVersion', 'deletionQueued'},
            title: 'Artist details (read-only)',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: canSave ? _save : null,
            icon: widget.isSaving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
            label: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
