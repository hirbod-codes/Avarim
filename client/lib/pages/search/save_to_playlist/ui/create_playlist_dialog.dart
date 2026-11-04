import 'package:flutter/material.dart';

/// Asks for a playlist name and runs [onSubmitPlaylistName]. It returns an error text to show under the field
/// (the dialog stays open so the name can be changed), or null when it worked (the dialog pops `true`).
class CreatePlaylistDialog extends StatefulWidget {
  const CreatePlaylistDialog({super.key, required this.suggestedPlaylistName, required this.onSubmitPlaylistName});

  /// Pre-filled (and selected) in the text field.
  final String suggestedPlaylistName;
  final Future<String?> Function(String playlistName) onSubmitPlaylistName;

  @override
  State<CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<CreatePlaylistDialog> {
  late final TextEditingController _playlistNameController = TextEditingController(text: widget.suggestedPlaylistName)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.suggestedPlaylistName.length);

  bool _isSubmitting = false;
  String? _errorText;

  @override
  void dispose() {
    _playlistNameController.dispose();
    super.dispose();
  }

  Future<void> _submitPlaylistName() async {
    if (_isSubmitting) return;

    final playlistName = _playlistNameController.text.trim();
    if (playlistName.isEmpty) {
      setState(() => _errorText = 'Name is required');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    final errorMessage = await widget.onSubmitPlaylistName(playlistName);
    if (!mounted) return;

    if (errorMessage == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _isSubmitting = false;
      _errorText = errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save as a new playlist'),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: _playlistNameController,
          autofocus: true,
          enabled: !_isSubmitting,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitPlaylistName(),
          decoration: InputDecoration(
            labelText: 'Playlist name',
            helperText: "All of the album's audios will be added to it",
            errorText: _errorText,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSubmitting ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _isSubmitting ? null : _submitPlaylistName,
          icon: _isSubmitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ],
    );
  }
}
