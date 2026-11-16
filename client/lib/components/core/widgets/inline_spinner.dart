import 'package:flutter/material.dart';

/// A small circular progress indicator for inside buttons, list rows and footers.
class InlineSpinner extends StatelessWidget {
  const InlineSpinner({super.key, this.size = 24, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth),
    );
  }
}
