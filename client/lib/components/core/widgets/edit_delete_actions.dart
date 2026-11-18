import 'package:flutter/material.dart';

import 'busy_icon_button.dart';

/// "Edit" and "Delete" icon buttons side by side. While [isBusy] (a delete is running) edit is disabled and the
/// delete button shows a spinner. A button whose callback is null is disabled.
class EditDeleteActions extends StatelessWidget {
  const EditDeleteActions({
    super.key,
    this.onEdit,
    this.onDelete,
    this.isBusy = false,
    this.editTooltip = 'Edit',
    this.deleteTooltip = 'Delete',
    this.leadings,
    this.trailing,
  });

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool isBusy;
  final String editTooltip;
  final String deleteTooltip;

  final List<Widget>? leadings;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 3,
      children: [
        ...(leadings ?? []),
        IconButton(tooltip: editTooltip, icon: const Icon(Icons.edit_outlined), onPressed: isBusy ? null : onEdit),
        BusyIconButton(
          isBusy: isBusy,
          tooltip: deleteTooltip,
          icon: Icon(Icons.delete_outline, color: errorColor),
          onPressed: onDelete,
        ),
        ...(trailing ?? []),
      ],
    );
  }
}
