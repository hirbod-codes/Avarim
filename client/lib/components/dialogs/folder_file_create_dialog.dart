import 'package:avarim/components/button.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderFileCreateDialog extends ConsumerStatefulWidget {
  const FolderFileCreateDialog({super.key});

  @override
  ConsumerState<FolderFileCreateDialog> createState() => _FolderFileCreateDialogState();
}

class _FolderFileCreateDialogState extends ConsumerState<FolderFileCreateDialog> {
  final titleController = TextEditingController();

  @override
  void dispose() {
    titleController.dispose();
    super.dispose();
  }

  bool isButtonDisabled() => titleController.text.trim().isEmpty;

  Future<void> _upload() async {
    if (isButtonDisabled()) return;

    Navigator.pop(context, titleController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(labelText: l10n.title),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),

                  const SizedBox(width: 8),

                  Button(type: ButtonType.elevated, color: theme.colorScheme.secondary, onPressed: isButtonDisabled() ? null : _upload, label: l10n.upload),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
