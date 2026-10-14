// chip_list_field.dart
//
// Text field that turns entries into deletable chips (artists, genres, ISRCs, ...).

import 'package:flutter/material.dart';

class ChipListField extends StatefulWidget {
  const ChipListField({
    required this.label,
    required this.values,
    required this.onChanged,
    required this.maxItems,
    required this.maxItemLength,
    this.itemPattern,
    this.itemPatternMessage,
    this.normalize,
  });

  final String label;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final int maxItems;
  final int maxItemLength;
  final String? itemPattern;
  final String? itemPatternMessage;
  final String Function(String)? normalize;

  @override
  State<ChipListField> createState() => _ChipListFieldState();
}

class _ChipListFieldState extends State<ChipListField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    // Text typed but not confirmed with Enter is added when the field loses focus.
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) _add();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    var v = _controller.text.trim();
    if (v.isEmpty) {
      if (_error != null) setState(() => _error = null);
      return;
    }
    if (widget.normalize != null) v = widget.normalize!(v);

    String? error;
    if (v.length > widget.maxItemLength) {
      error = 'Too long (max ${widget.maxItemLength})';
    } else if (widget.itemPattern != null && !RegExp(widget.itemPattern!).hasMatch(v)) {
      error = widget.itemPatternMessage ?? 'Invalid value';
    } else if (widget.values.length >= widget.maxItems) {
      error = 'At most ${widget.maxItems} items';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    if (!widget.values.contains(v)) widget.onChanged([...widget.values, v]);
    _controller.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            _add();
            _focus.requestFocus();
          },
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: 'Press Enter to add',
            errorText: _error,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(tooltip: 'Add', icon: const Icon(Icons.add), onPressed: _add),
          ),
        ),
        if (widget.values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (i, v) in widget.values.indexed) InputChip(label: Text(v), onDeleted: () => widget.onChanged([...widget.values]..removeAt(i))),
              ],
            ),
          ),
      ],
    );
  }
}
