import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A numeric input box that reports the number after the user stops typing, and rolls back if saving it fails.
///
/// [onValueChanged] is called with the parsed number, or null when the field is empty or holds only a partial entry
/// such as "-" or ".":
///  - [debounce] after the last keystroke,
///  - immediately when the keyboard's submit action is pressed,
///  - immediately when the field loses focus (the iOS number pad has no submit key),
///  - immediately when the clear button is pressed (with null).
///
/// [onValueChanged] may be async. If it throws (or its future fails):
///  - the field is rolled back to the last value that succeeded, unless the user has already typed something newer;
///    newer text is never overwritten, it is sent next instead,
///  - [onError] is called (without one, the error goes to [FlutterError.reportError]).
///
/// Only one call is in flight at a time. Typing while a call is pending is sent once it finishes. Values are
/// compared with the last SUCCESSFUL one, so an unchanged value is not sent again, and a value that failed can be
/// retried by typing it again. The initial value counts as successful.
///
/// Typing is restricted to what can form a valid number: digits, one decimal point (only with [allowDecimal]) and a
/// leading minus (only when [min] is null or negative). A comma is accepted as a decimal point. Pasting text that
/// is not a valid number is rejected as a whole.
///
/// Values outside [min]..[max] are clamped when reported. The text itself is only rewritten to the clamped value on
/// submit / focus loss, so the user can still type "50" when [min] is 10 without being fought on the "5".
///
/// Reported values are [double] when [allowDecimal] is true and [int] otherwise.
///
/// Call [DebouncedNumberFieldState.flush] (through a `GlobalKey<DebouncedNumberFieldState>`) to report a pending
/// debounced value right now, e.g. before switching tabs. It returns a future that completes when saving is done.
class DebouncedNumberField extends StatefulWidget {
  const DebouncedNumberField({
    super.key,
    required this.onValueChanged,
    this.onError,
    this.debounce = const Duration(milliseconds: 500),
    this.controller,
    this.focusNode,
    this.initialValue,
    this.onTextChanged,
    this.min,
    this.max,
    this.allowDecimal = false,
    this.maxDecimalDigits,
    this.hintText,
    this.suffixText,
    this.autofocus = false,
    this.enabled = true,
    this.disableWhileSaving = false,
    this.textInputAction = TextInputAction.done,
    this.prefixIcon,
    this.showClearButton = true,
    this.clearIcon = const Icon(Icons.clear),
    this.clearTooltip,
    this.borderRadius = 28,
    this.filled = true,
    this.isDense = true,
  });

  /// Receives the parsed (and clamped) number, or null when the field is empty.
  ///
  /// Return the future of the operation and let it throw on failure; an error that is caught inside and swallowed
  /// looks like a success and is not rolled back.
  final FutureOr<void> Function(num? value) onValueChanged;

  /// Called after a failed [onValueChanged] and after the rollback, e.g. to show a snackbar.
  /// [attemptedValue] is the value that failed.
  final void Function(Object error, StackTrace stackTrace, num? attemptedValue)? onError;

  /// How long to wait after the last keystroke before calling [onValueChanged].
  final Duration debounce;

  /// Provide your own to read/set the text from outside. You then own it (it is not disposed here).
  final TextEditingController? controller;

  /// Provide your own to control focus from outside. You then own it (it is not disposed here).
  final FocusNode? focusNode;

  /// Initial value when no [controller] is given. It counts as already saved.
  final num? initialValue;

  /// Called on every keystroke with the raw text (not debounced), e.g. to show a "typing…" hint.
  final ValueChanged<String>? onTextChanged;

  /// Lower bound. Also decides whether a minus sign can be typed: only when this is null or negative.
  final num? min;

  /// Upper bound.
  final num? max;

  /// Allow a decimal point. Reported values are then [double], otherwise [int].
  final bool allowDecimal;

  /// Maximum digits after the decimal point. Null = unlimited. Only used when [allowDecimal] is true.
  final int? maxDecimalDigits;

  final String? hintText;

  /// Shown after the text, e.g. a unit like "kg" or "%".
  final String? suffixText;
  final bool autofocus;
  final bool enabled;

  /// Disables the field (and its clear button) while [onValueChanged] is running, so you don't need a flag of your own.
  /// The state lives inside the field, so it works even when the field sits in a popup/route that your own
  /// `setState` doesn't rebuild. Disabling drops focus, so the keyboard closes when saving starts.
  final bool disableWhileSaving;
  final TextInputAction textInputAction;

  /// Null = no prefix icon.
  final Widget? prefixIcon;
  final bool showClearButton;
  final Widget clearIcon;
  final String? clearTooltip;
  final double borderRadius;
  final bool filled;
  final bool isDense;

  @override
  State<DebouncedNumberField> createState() => DebouncedNumberFieldState();
}

class DebouncedNumberFieldState extends State<DebouncedNumberField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: widget.initialValue == null ? '' : _format(widget.initialValue!));
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  Timer? _debounceTimer;

  // The last value onValueChanged accepted. Set in initState, NOT as a lazy `late` initializer: a lazy one would first
  // run inside _report, after the controller already holds the typed text, and the first report would be compared
  // with itself and dropped.
  num? _committed;

  // The running save loop, if any. Everything that wants to save joins it instead of starting a second call.
  Future<void>? _running;

  bool _saving = false;

  bool get _effectiveEnabled => widget.enabled && !(widget.disableWhileSaving && _saving);

  bool get _allowNegative => widget.min == null || widget.min! < 0;

  @override
  void initState() {
    super.initState();
    _committed = _parse(_controller.text);
    _focusNode.addListener(_onFocusChange);
  }

  // --- parsing -------------------------------------------------------------------------------------------------

  num? _parseRaw(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return widget.allowDecimal ? double.tryParse(trimmed) : int.tryParse(trimmed);
  }

  num _clamp(num value) {
    final min = widget.min, max = widget.max;
    if (min != null && value < min) return min;
    if (max != null && value > max) return max;
    return value;
  }

  num? _parse(String text) {
    final raw = _parseRaw(text);
    return raw == null ? null : _clamp(raw);
  }

  String _format(num value) => value == value.truncate() ? value.truncate().toString() : value.toString();

  RegExp get _pattern {
    final sign = _allowNegative ? '-?' : '';
    final digits = widget.maxDecimalDigits;
    final fraction = !widget.allowDecimal
        ? ''
        : digits == null
        ? r'(\.\d*)?'
        : '(\\.\\d{0,$digits})?';
    return RegExp('^$sign\\d*$fraction\$');
  }

  // --- saving --------------------------------------------------------------------------------------------------

  void _onChanged(String text) {
    widget.onTextChanged?.call(text);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounce, () => unawaited(_report()));
  }

  /// Saves the current text if it differs from the last saved value. Joins the running save if there is one.
  Future<void> _report() {
    _debounceTimer?.cancel();
    return _running ??= _drain().whenComplete(() {
      _running = null;
      _setSaving(false);
    });
  }

  /// Sends the current value, and keeps going while the text has moved on in the meantime.
  Future<void> _drain() async {
    while (mounted) {
      final value = _parse(_controller.text);
      if (value == _committed) return;
      _setSaving(true);
      try {
        await widget.onValueChanged(value);
        _committed = value;
      } catch (error, stackTrace) {
        if (!mounted) return;
        // Roll back only if the field still shows the value that failed. If the user has typed something newer,
        // leave it alone: the next loop iteration sends it.
        final stillShowsFailedValue = _parse(_controller.text) == value;
        if (stillShowsFailedValue) _setText(_committed == null ? '' : _format(_committed!));
        _reportError(error, stackTrace, value);
        if (stillShowsFailedValue) return;
      }
    }
  }

  void _reportError(Object error, StackTrace stackTrace, num? attemptedValue) {
    final onError = widget.onError;
    if (onError != null) {
      onError(error, stackTrace, attemptedValue);
    } else {
      FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stackTrace, library: 'DebouncedNumberField'));
    }
  }

  void _setSaving(bool saving) {
    if (!widget.disableWhileSaving || _saving == saving || !mounted) return;
    setState(() => _saving = saving);
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Makes the text show exactly what gets reported: a clamped value is written back, a partial entry ("-", ".")
  /// is emptied.
  void _syncTextToValue() {
    final raw = _parseRaw(_controller.text);
    if (raw == null) {
      if (_controller.text.isNotEmpty) _setText('');
      return;
    }
    final clamped = _clamp(raw);
    if (clamped != raw) _setText(_format(clamped));
  }

  Future<void> _commit() {
    _syncTextToValue();
    return _report();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) unawaited(_commit());
  }

  /// Saves the current value now if it wasn't saved yet (cancels the pending debounce). The future completes when
  /// saving is done, including a rollback after a failure.
  Future<void> flush() => _report();

  /// Empties the field and saves null immediately.
  Future<void> clear() {
    _controller.clear();
    return _report();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _focusNode.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      enabled: _effectiveEnabled,
      keyboardType: TextInputType.numberWithOptions(decimal: widget.allowDecimal, signed: _allowNegative),
      textInputAction: widget.textInputAction,
      inputFormatters: [_NumberInputFormatter(_pattern, commaAsDecimal: widget.allowDecimal)],
      onChanged: _onChanged,
      onSubmitted: (_) => unawaited(_commit()),
      decoration: InputDecoration(
        hintText: widget.hintText,
        suffixText: widget.suffixText,
        isDense: widget.isDense,
        filled: widget.filled,
        prefixIcon: widget.prefixIcon,
        suffixIcon: !widget.showClearButton
            ? null
            : ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, child) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: widget.clearTooltip,
                        icon: widget.clearIcon,
                        // A null onPressed makes the button inert and greyed out while the field is disabled.
                        onPressed: _effectiveEnabled ? () => unawaited(clear()) : null,
                      ),
              ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(widget.borderRadius), borderSide: BorderSide.none),
      ),
    );
  }
}

/// Accepts an edit only if the whole new text still matches [pattern]; otherwise keeps the old value.
/// (`FilteringTextInputFormatter.allow` is not used because it filters per match and would wipe the field when the
/// pattern is anchored.)
class _NumberInputFormatter extends TextInputFormatter {
  const _NumberInputFormatter(this.pattern, {required this.commaAsDecimal});

  final RegExp pattern;
  final bool commaAsDecimal;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = commaAsDecimal ? newValue.text.replaceAll(',', '.') : newValue.text;
    if (!pattern.hasMatch(text)) return oldValue;
    // Same length, so the selection stays valid.
    return text == newValue.text ? newValue : newValue.copyWith(text: text);
  }
}
