import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/plan/models/currency_label.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';

class PaymentCurrency {
  final String paymentMethod;
  final Currency currency;

  PaymentCurrency({required this.paymentMethod, required this.currency});
}

class ChoosePaymentCurrency extends ConsumerStatefulWidget {
  final void Function(PaymentCurrency paymentCurrency)? onSelect;

  const ChoosePaymentCurrency({super.key, this.onSelect});

  @override
  ConsumerState<ChoosePaymentCurrency> createState() => _ChoosePaymentCurrencyState();
}

class _ChoosePaymentCurrencyState extends ConsumerState<ChoosePaymentCurrency> {
  Dio get _authDio => ref.read(authDioProvider);

  bool _loadingMethods = true;
  String? _error;
  List<String> _supportedMethods = [];
  List<Currency> _supportedCurrencies = [];
  List<Currency> _displayableCurrencies = [];
  String? _selectedMethod;
  Currency? _selectedCurrency;

  @override
  void initState() {
    super.initState();
    _fetchPaymentMethods();
  }

  Future<void> _fetchPaymentMethods() async {
    try {
      setState(() {
        _loadingMethods = true;
        _error = null;
      });

      final result = await apiCall(() => _authDio.get('/api/subscription/supported_payment_methods'));

      if (!mounted) return;
      talker.info('mounted');

      if (result.isFailure || result.dataOrNull == null) {
        setState(() {
          _loadingMethods = false;
          _error = AppLocalizations.of(context)!.checkout_load_methods_failed;
        });
        return;
      }

      final raw = (result.dataOrNull!['methods'] as List<dynamic>?) ?? [];
      final supportedMethods = raw.cast<String>();
      final supportedCurrencies = Currency.values.where((c) {
        switch (c) {
          case Currency.usd:
            return supportedMethods.contains('paypal');
          case Currency.eur:
            return supportedMethods.contains('paypal');
          case Currency.irr:
            return supportedMethods.contains('zibal') || supportedMethods.contains('zarinpal');
          case Currency.btc:
            return supportedMethods.contains('bitcoin');
          case Currency.eth:
            return supportedMethods.contains('bitcoin');
        }
      }).toList();

      final selectedMethod = supportedMethods.isNotEmpty ? supportedMethods.first : null;

      List<Currency> displayableCurrencies = selectedMethod == null ? [] : _resolveDisplayableCurrencies(selectedMethod, supportedCurrencies);

      final selectedCurrency = displayableCurrencies.isNotEmpty ? displayableCurrencies.first : null;

      talker.debug({supportedMethods, supportedCurrencies, selectedMethod, selectedCurrency, displayableCurrencies});

      if (selectedMethod != null && selectedCurrency != null) {
        widget.onSelect?.call(PaymentCurrency(paymentMethod: selectedMethod, currency: selectedCurrency));
      }

      setState(() {
        _loadingMethods = false;
        _supportedMethods = supportedMethods;
        _supportedCurrencies = supportedCurrencies;
        _selectedMethod = selectedMethod;
        _selectedCurrency = selectedCurrency;
        _displayableCurrencies = displayableCurrencies;
      });
    } catch (e) {
      talker.error('caught error in _fetchPaymentMethods method of _ChoosePaymentCurrencyState class', e);
    }
  }

  List<Currency> _resolveDisplayableCurrencies(String method, List<Currency> supportedCurrency) {
    switch (method) {
      case 'paypal':
        return [Currency.usd, Currency.eur];
      case 'zarinpal':
        return [Currency.irr];
      case 'zibal':
        return [Currency.irr];
      case 'bitcoin':
        return [Currency.btc, Currency.eth];
      default:
        throw Exception('Invalid payment method provided');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingMethods) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final l10n = AppLocalizations.of(context)!;

    if (_error != null) {
      return Column(
        children: [
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          TextButton(onPressed: _fetchPaymentMethods, child: Text(l10n.checkout_retry)),
        ],
      );
    }

    if (_selectedMethod == null || _selectedCurrency == null) {
      return Column(
        children: [
          Text(l10n.checkout_no_methods),
          const SizedBox(height: 8),
          TextButton(onPressed: _fetchPaymentMethods, child: Text(l10n.checkout_retry)),
        ],
      );
    }

    return Column(
      children: [
        Center(
          child: SegmentedButton<Currency>(
            segments: _displayableCurrencies.map((c) => ButtonSegment(value: c, label: Text(c.label))).toList(),
            selected: {_selectedCurrency!},
            onSelectionChanged: (selection) {
              final selectedCurrency = selection.first;

              widget.onSelect?.call(PaymentCurrency(paymentMethod: _selectedMethod!, currency: selectedCurrency));

              setState(() {
                _selectedCurrency = selectedCurrency;
              });
            },
            showSelectedIcon: false,
          ),
        ),

        ..._supportedMethods.map(
          (method) => RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(method), // swap for a display-name lookup if you want nicer labels than the raw identifier
            value: method,
            // ignore: deprecated_member_use
            groupValue: _selectedMethod!,
            // ignore: deprecated_member_use
            onChanged: (value) {
              final selectedMethod = value;

              List<Currency> displayableCurrencies = _resolveDisplayableCurrencies(selectedMethod!, _supportedCurrencies);
              final selectedCurrency = displayableCurrencies.first;

              widget.onSelect?.call(PaymentCurrency(paymentMethod: selectedMethod, currency: _selectedCurrency!));

              setState(() {
                _selectedMethod = selectedMethod;
                _displayableCurrencies = displayableCurrencies;
                _selectedCurrency = selectedCurrency;
              });
            },
          ),
        ),
      ],
    );
  }
}
