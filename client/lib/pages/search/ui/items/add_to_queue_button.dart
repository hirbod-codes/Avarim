import 'package:avarim/components/core/core.dart';
import 'package:flutter/material.dart';

/// "Add to queue" icon button that spins while the audios to add are being fetched.
class AddToQueueButton extends StatelessWidget {
  const AddToQueueButton({super.key, required this.onPressed, this.isBusy = false});

  final VoidCallback onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return BusyIconButton(tooltip: 'Add to queue', icon: const Icon(Icons.playlist_add), isBusy: isBusy, onPressed: onPressed);
  }
}
