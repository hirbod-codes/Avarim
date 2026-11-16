import 'package:flutter/material.dart';

import 'busy_icon_button.dart';

/// An icon button for an async action: it shows a spinner until the future returned by [onPressed] completes.
/// Ignores presses while the action is running.
class AsyncIconButton extends StatefulWidget {
  const AsyncIconButton({super.key, required this.icon, required this.onPressed, this.tooltip});

  final Widget icon;
  final Future<void> Function() onPressed;
  final String? tooltip;

  @override
  State<AsyncIconButton> createState() => _AsyncIconButtonState();
}

class _AsyncIconButtonState extends State<AsyncIconButton> {
  bool _isRunning = false;

  Future<void> _run() async {
    if (_isRunning) return;
    setState(() => _isRunning = true);
    try {
      await widget.onPressed();
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BusyIconButton(icon: widget.icon, tooltip: widget.tooltip, isBusy: _isRunning, onPressed: _run);
  }
}
