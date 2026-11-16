import 'package:flutter/material.dart';

import 'inline_spinner.dart';

/// An [IconButton] that turns into a spinner (same footprint) while [isBusy].
class BusyIconButton extends StatelessWidget {
  const BusyIconButton({super.key, required this.icon, this.onPressed, this.tooltip, this.isBusy = false});

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    if (isBusy) {
      return const Padding(padding: EdgeInsets.all(12), child: InlineSpinner());
    }
    return IconButton(tooltip: tooltip, icon: icon, onPressed: onPressed);
  }
}
