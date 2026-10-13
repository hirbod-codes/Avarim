import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/components/checkout/choose_payment_method_currency.dart';
import 'package:avarim/plan/models/currency_label.dart';
import 'package:avarim/plan/models/plan.dart'; // for Currency and Plan
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/pages/plan/currency_formatter.dart';
import 'package:avarim/plan/models/price.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SubscriptionDuration { month, year }

Currency currencyForPaymentMethod(String method) {
  switch (method) {
    case 'zarinpal':
      return Currency.irr;
    case 'zibal':
      return Currency.irr;
    case 'stripe':
      return Currency.usd;
    case 'paypal':
      return Currency.usd;
    default:
      throw ArgumentError('Unknown payment method: $method');
  }
}

Future<void> showCheckoutDialog(BuildContext context, {required Plan plan}) {
  return showDialog(
    context: context,
    builder: (_) => AddStorageDialog(plan: plan),
  );
}

class AddStorageDialog extends ConsumerStatefulWidget {
  final Plan plan;

  const AddStorageDialog({super.key, required this.plan});

  @override
  ConsumerState<AddStorageDialog> createState() => _AddStorageDialogState();
}

class _AddStorageDialogState extends ConsumerState<AddStorageDialog> {
  Dio get _authDio => ref.read(authDioProvider);

  String? _error;
  bool _isRedirectingToPayment = false;
  bool _loadingStoragePrice = true;
  Price? _storagePrice;
  int? maxGb;
  int? minGb;
  int stepGb = 1;
  int? _selectedGb;
  Currency? _currency;
  String? _paymentMethod;

  @override
  void initState() {
    super.initState();
    _fetchStoragePrice();
  }

  void _fetchStoragePrice() {
    setState(() {
      _loadingStoragePrice = true;
    });
    try {
      //
    } finally {
      setState(() {
        _loadingStoragePrice = true;
      });
    }
  }

  void _setGb(int gb) {
    setState(() => _selectedGb = gb.clamp(minGb!, maxGb!));
  }

  double totalFor(Currency currency, int gb) => (_storagePrice![currency.name]!) * gb;

  Future<void> _confirm() async {
    if (_currency == null || _paymentMethod == null || _selectedGb == null || _currency == null) return;

    setState(() {
      _isRedirectingToPayment = true;
    });

    await apiCall(
      () => _authDio.post(
        '/api/subscription/storage',
        data: {'storage': _selectedGb!, 'calculatedPrice': totalFor(_currency!, _selectedGb!), 'currency': _currency!.name},
      ),
    );

    if (mounted) {
      setState(() {
        _isRedirectingToPayment = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingStoragePrice) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final l10n = AppLocalizations.of(context)!;

    if (_error != null || _storagePrice == null || maxGb == null || minGb == null || _currency == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_error ?? l10n.uncaughtError, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 8),
            TextButton(onPressed: _fetchStoragePrice, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    _selectedGb ??= minGb;

    final locale = Localizations.localeOf(context).languageCode;
    final presets = [5, 10, 50, 100, 250].where((g) => g >= minGb! && g <= maxGb!).toList();
    final divisions = ((maxGb! - minGb!) / stepGb).round().clamp(1, 1000);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ChoosePaymentCurrency(
                  onSelect: (paymentCurrency) {
                    setState(() {
                      _currency = paymentCurrency.currency;
                      _paymentMethod = paymentCurrency.paymentMethod;
                    });
                  },
                ),
              ),
              Text('Add more storage', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Choose how much extra storage you need.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),

              Center(
                child: SegmentedButton<Currency>(
                  segments: Currency.values.map((c) => ButtonSegment(value: c, label: Text(c.label))).toList(),
                  selected: {_currency!},
                  onSelectionChanged: (selection) => setState(() => _currency = selection.first),
                  showSelectedIcon: false,
                ),
              ),
              if (presets.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: presets.map((g) => ChoiceChip(label: Text('$g GB'), selected: _selectedGb == g, onSelected: (_) => _setGb(g))).toList(),
                ),
              const SizedBox(height: 12),

              Row(
                children: [
                  IconButton(onPressed: () => _setGb(_selectedGb! - stepGb), icon: const Icon(Icons.remove_circle_outline)),
                  Expanded(
                    child: Slider(
                      min: minGb!.toDouble(),
                      max: maxGb!.toDouble(),
                      divisions: divisions,
                      value: _selectedGb!.toDouble(),
                      label: '$_selectedGb GB',
                      onChanged: (v) => _setGb(v.round()),
                    ),
                  ),
                  IconButton(onPressed: () => _setGb(_selectedGb! + stepGb), icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
              Center(child: Text('$_selectedGb GB', style: Theme.of(context).textTheme.titleLarge)),

              const SizedBox(height: 16),
              Text('Estimated monthly cost', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('${_currency!.name.toUpperCase()}: ${CurrencyFormatter.format(totalFor(_currency!, _selectedGb!), _currency!, locale: locale)}'),
                ],
              ),
              const SizedBox(height: 4),

              const SizedBox(height: 20),
              Button(
                type: ButtonType.outlined,
                isLoading: _isRedirectingToPayment,
                onPressed: _currency == null || _paymentMethod == null ? null : _confirm,
                label: l10n.continue_to_payment,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
