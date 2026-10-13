import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Six-box OTP entry field. Calls [onCompleted] as soon as all boxes are
/// filled (including on paste), and [onChanged] on every keystroke so the
/// parent can e.g. disable the submit button until the code is complete.
class OtpCodeInput extends StatefulWidget {
  final int length;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;

  const OtpCodeInput({super.key, this.length = 6, this.onChanged, this.onCompleted, this.enabled = true});

  @override
  State<OtpCodeInput> createState() => OtpCodeInputState();
}

class OtpCodeInputState extends State<OtpCodeInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get code => _controllers.map((c) => c.text).join();

  /// Clears every box and refocuses the first one — call this after a
  /// failed verification attempt so the user can retype.
  void clear() {
    for (final c in _controllers) {
      c.clear();
    }
    _focusNodes.first.requestFocus();
    widget.onChanged?.call('');
  }

  void _handleChange(int index, String value) {
    // Handles a paste landing in a single box, e.g. the OS suggests the
    // whole SMS code and drops it into whichever box has focus.
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < widget.length; i++) {
        _controllers[i].text = i < digits.length ? digits[i] : '';
      }
      final lastFilled = digits.length.clamp(0, widget.length) - 1;
      if (lastFilled >= 0) {
        _focusNodes[lastFilled.clamp(0, widget.length - 1)].requestFocus();
      }
    } else if (value.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    widget.onChanged?.call(code);
    if (code.length == widget.length && !code.contains(RegExp(r'\D'))) {
      widget.onCompleted?.call(code);
    }
  }

  void _handleBackspace(int index) {
    if (_controllers[index].text.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      widget.onChanged?.call(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(widget.length, (index) {
          return SizedBox(
            width: 44,
            child: KeyboardListener(
              focusNode: FocusNode(skipTraversal: true),
              onKeyEvent: (event) {
                if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
                  _handleBackspace(index);
                }
              },
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: index == 0 ? widget.length : 1, // box 0 also accepts a full paste
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: const InputDecoration(counterText: ''),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) => _handleChange(index, value),
              ),
            ),
          );
        }),
      ),
    );
  }
}
