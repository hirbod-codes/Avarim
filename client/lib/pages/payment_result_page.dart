import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _CheckState { loading, success, error }

class PaymentResultPage extends ConsumerStatefulWidget {
  /// 'success' | 'error' — as passed back in the redirect's query string.
  final String status;

  /// The uuid identifying this payment, also from the redirect's query string.
  final String data;

  const PaymentResultPage({super.key, required this.status, required this.data});

  @override
  ConsumerState<PaymentResultPage> createState() => _PaymentResultPageState();
}

class _PaymentResultPageState extends ConsumerState<PaymentResultPage> {
  Dio get _authDio => ref.read(authDioProvider);

  _CheckState _state = _CheckState.loading;

  @override
  void initState() {
    super.initState();
    _checkPayment();
  }

  Future<void> _checkPayment() async {
    if (widget.status != 'success' || widget.data.isEmpty) {
      setState(() => _state = _CheckState.error);
      return;
    }

    final result = await apiCall(() => _authDio.get('/api/subscription/zibal/verify/check', queryParameters: {'uuid': widget.data}));

    if (!mounted) return;

    setState(() => _state = result.isSuccess ? _CheckState.success : _CheckState.error);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(context),
              const SizedBox(height: 16),
              Text(_title(l10n), style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              if (_state != _CheckState.loading) ...[
                const SizedBox(height: 8),
                Text(_message(l10n), style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: () => context.go('/'), child: Text(l10n.payment_result_continue)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    switch (_state) {
      case _CheckState.loading:
        return const SizedBox(height: 48, width: 48, child: CircularProgressIndicator());
      case _CheckState.success:
        return const Icon(Icons.check_circle, color: Colors.green, size: 64);
      case _CheckState.error:
        return Icon(Icons.error, color: Theme.of(context).colorScheme.error, size: 64);
    }
  }

  String _title(AppLocalizations l10n) {
    switch (_state) {
      case _CheckState.loading:
        return l10n.payment_result_checking;
      case _CheckState.success:
        return l10n.payment_result_success_title;
      case _CheckState.error:
        return l10n.payment_result_error_title;
    }
  }

  String _message(AppLocalizations l10n) {
    switch (_state) {
      case _CheckState.loading:
        return '';
      case _CheckState.success:
        return l10n.payment_result_success_message;
      case _CheckState.error:
        return l10n.payment_result_error_message;
    }
  }
}
