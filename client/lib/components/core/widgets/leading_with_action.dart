import 'package:flutter/material.dart';

/// A list tile's leading: an optional action button (default: play) placed before [child] (e.g. a thumbnail).
class LeadingWithAction extends StatelessWidget {
  const LeadingWithAction({super.key, required this.child, this.onAction, this.actionIcon = Icons.play_arrow, this.actionTooltip = 'Play'});

  final Widget child;

  /// The action button is only shown when this is set.
  final VoidCallback? onAction;
  final IconData actionIcon;
  final String actionTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 5,
      children: [
        if (onAction != null) IconButton(tooltip: actionTooltip, icon: Icon(actionIcon), onPressed: onAction),
        child,
      ],
    );
  }
}
