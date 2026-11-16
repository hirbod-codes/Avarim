import 'package:flutter/material.dart';

/// Text that never wraps: one line, ellipsis when it doesn't fit.
class SingleLineText extends StatelessWidget {
  const SingleLineText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}
