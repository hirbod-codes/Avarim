import 'package:flutter/material.dart';

/// A centered icon with a message (and optionally an action button) shown instead of an empty list.
class ResultsListMessage extends StatelessWidget {
  const ResultsListMessage({super.key, required this.icon, required this.message, this.actionLabel, this.onActionPressed});

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 8),
          Text(message),
          if (actionLabel != null) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(onPressed: onActionPressed, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
