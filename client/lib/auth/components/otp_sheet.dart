import 'dart:async';

import 'package:avarim/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/action_controller.dart';
import 'otp_code_input.dart';

const _resendCooldown = Duration(seconds: 30);

/// Shows a bottom sheet asking the user for the code just sent to
/// [destination] (a phone number or an email address).
///
/// [onVerify] should call the API to verify the code and return once it
/// succeeds (throwing on failure — the sheet clears the code and lets the
/// user retry without closing; the error itself is shown by the global
/// error interceptor's toast, not by this sheet). [onResend] re-triggers
/// the OTP send.
///
/// Returns `true` if verification succeeded, `false`/`null` if the sheet
/// was dismissed without success.
Future<bool?> showOtpSheet({
  required BuildContext context,
  required String destination,
  required String title,
  required Future<void> Function(String code) onVerify,
  required Future<void> Function() onResend,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _OtpSheetContent(destination: destination, title: title, onVerify: onVerify, onResend: onResend),
  );
}

class _OtpSheetContent extends ConsumerStatefulWidget {
  final String destination;
  final String title;
  final Future<void> Function(String code) onVerify;
  final Future<void> Function() onResend;

  const _OtpSheetContent({required this.destination, required this.title, required this.onVerify, required this.onResend});

  @override
  ConsumerState<_OtpSheetContent> createState() => _OtpSheetContentState();
}

class _OtpSheetContentState extends ConsumerState<_OtpSheetContent> {
  final _otpKey = GlobalKey<OtpCodeInputState>();
  String _code = '';
  Duration _cooldown = _resendCooldown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cooldown.inSeconds <= 1) {
        t.cancel();
        setState(() => _cooldown = Duration.zero);
      } else {
        setState(() => _cooldown -= const Duration(seconds: 1));
      }
    });
  }

  Future<void> _submit() async {
    final code = _code;
    if (code.length != 6) return;

    final controller = ref.read(authActionControllerProvider.notifier);
    await controller.run(() => widget.onVerify(code));

    final state = ref.read(authActionControllerProvider);
    if (state.hasError) {
      _otpKey.currentState?.clear();
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _resend() async {
    final controller = ref.read(authActionControllerProvider.notifier);
    await controller.run(widget.onResend);
    final state = ref.read(authActionControllerProvider);
    if (!state.hasError) _startCooldown();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(authActionControllerProvider);
    final isLoading = actionState.isLoading;

    AppLocalizations l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.otp_sheet_heading(widget.destination), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          OtpCodeInput(key: _otpKey, enabled: !isLoading, onChanged: (value) => setState(() => _code = value), onCompleted: (_) => _submit()),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: isLoading || _code.length != 6 ? null : _submit,
            child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(l10n.verify),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _cooldown == Duration.zero && !isLoading ? _resend : null,
              child: Text(_cooldown == Duration.zero ? l10n.resendCode : l10n.resendCodeIn(_cooldown.inSeconds)),
            ),
          ),
        ],
      ),
    );
  }
}
