import 'dart:async';

import 'package:flutter/material.dart';

/// A search box that reports the text after the user stops typing.
///
/// [onSearch] is called with the text:
///  - [debounce] after the last keystroke,
///  - immediately when the keyboard's search/submit action is pressed,
///  - immediately when the clear button is pressed (with '').
/// It is NOT called again for text equal to the one it last reported, so callers can wire it straight to a
/// provider without extra checks.
///
/// Everything else is configurable through the constructor; the widget knows nothing about what is searched.
/// Call [DebouncedSearchFieldState.flush] (through a `GlobalKey<DebouncedSearchFieldState>`) to report a pending
/// debounced text right now, e.g. before switching tabs.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.onSearch,
    this.debounce = const Duration(milliseconds: 500),
    this.controller,
    this.focusNode,
    this.initialText = '',
    this.onChanged,
    this.trimText = true,
    this.hintText,
    this.autofocus = false,
    this.enabled = true,
    this.textInputAction = TextInputAction.search,
    this.keyboardType,
    this.prefixIcon = const Icon(Icons.search),
    this.showClearButton = true,
    this.clearIcon = const Icon(Icons.clear),
    this.clearTooltip,
    this.borderRadius = 28,
    this.filled = true,
    this.isDense = true,
  });

  /// Receives the text to search for (trimmed, unless [trimText] is false).
  final ValueChanged<String> onSearch;

  /// How long to wait after the last keystroke before calling [onSearch].
  final Duration debounce;

  /// Provide your own to read/set the text from outside. You then own it (it is not disposed here).
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Initial text when no [controller] is given. It counts as already reported.
  final String initialText;

  /// Called on every keystroke with the raw text (not debounced), e.g. to show a "typing…" hint.
  final ValueChanged<String>? onChanged;
  final bool trimText;

  final String? hintText;
  final bool autofocus;
  final bool enabled;
  final TextInputAction textInputAction;
  final TextInputType? keyboardType;

  /// Null = no prefix icon.
  final Widget? prefixIcon;
  final bool showClearButton;
  final Widget clearIcon;
  final String? clearTooltip;
  final double borderRadius;
  final bool filled;
  final bool isDense;

  @override
  State<DebouncedSearchField> createState() => DebouncedSearchFieldState();
}

class DebouncedSearchFieldState extends State<DebouncedSearchField> {
  late final TextEditingController _controller = widget.controller ?? TextEditingController(text: widget.initialText);
  Timer? _debounceTimer;
  late String _lastReportedText = _normalize(_controller.text);

  String _normalize(String text) => widget.trimText ? text.trim() : text;

  void _onChanged(String text) {
    widget.onChanged?.call(text);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, () => _report(text));
  }

  void _report(String text) {
    _debounceTimer?.cancel();
    final normalized = _normalize(text);
    if (normalized == _lastReportedText) return;
    _lastReportedText = normalized;
    widget.onSearch(normalized);
  }

  /// Reports the current text now if it wasn't reported yet (cancels the pending debounce).
  void flush() => _report(_controller.text);

  /// Empties the field and reports '' immediately.
  void clear() {
    _controller.clear();
    _report('');
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onChanged: _onChanged,
      onSubmitted: _report,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: widget.isDense,
        filled: widget.filled,
        prefixIcon: widget.prefixIcon,
        suffixIcon: !widget.showClearButton
            ? null
            : ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) =>
                    value.text.isEmpty ? const SizedBox.shrink() : IconButton(tooltip: widget.clearTooltip, icon: widget.clearIcon, onPressed: clear),
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.borderRadius), borderSide: BorderSide.none),
      ),
    );
  }
}
