import 'dart:math';

import 'package:avarim/api/api_call.dart';
import 'package:avarim/api/dio/dio_providers.dart';
import 'package:avarim/components/button.dart';
import 'package:avarim/components/checkout/choose_payment_method_currency.dart';
import 'package:avarim/plan/models/currency_label.dart';
import 'package:avarim/plan/models/plan.dart'; // for Currency and Plan
import 'package:avarim/components/global/notification_service.dart';
import 'package:avarim/l10n/app_localizations.dart';
import 'package:avarim/pages/plan/currency_formatter.dart';
import 'package:avarim/subscription/models/subscription.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avarim/lib/talker.dart';
import 'package:url_launcher/url_launcher.dart';

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

Future<void> showCheckoutDialog(BuildContext context, {required Plan plan, Subscription? subscription}) {
  return showDialog(
    context: context,
    builder: (_) => CheckoutDialog(plan: plan, subscription: subscription),
  );
}

class CheckoutDialog extends ConsumerStatefulWidget {
  final Plan plan;
  final Subscription? subscription;

  const CheckoutDialog({super.key, required this.plan, this.subscription});

  @override
  ConsumerState<CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends ConsumerState<CheckoutDialog> {
  Dio get _authDio => ref.read(authDioProvider);

  bool _submitting = false;
  String? _selectedMethod;

  static const double _defaultDurationDays = 30;
  static const double _defaultAdditionalStorageGb = 0;

  late final TextEditingController _durationController;
  late final TextEditingController _additionalStorageController;

  double _durationDays = _defaultDurationDays;
  double _additionalStorageGb = _defaultAdditionalStorageGb;

  String? _durationError;
  String? _additionalStorageError;

  Currency? _selectedCurrency;

  double? _totalPrice;

  @override
  void initState() {
    super.initState();

    setState(() {
      _durationDays = widget.subscription == null
          ? _defaultDurationDays
          : ((widget.subscription!.currentPeriodEnd - DateTime.now().millisecondsSinceEpoch) / (1000 * 60 * 60 * 24));
      _durationController = TextEditingController(text: _durationDays.toStringAsFixed(2));

      _additionalStorageGb = widget.subscription == null
          ? _defaultAdditionalStorageGb
          : ((max(widget.subscription!.privileges.storageBytes - widget.plan.privileges.storageBytes, widget.plan.privileges.storageBytes)) /
                (1024 * 1024 * 1024));
      _additionalStorageController = TextEditingController(text: _additionalStorageGb.toStringAsFixed(2));
    });
  }

  @override
  void dispose() {
    _durationController.dispose();
    _additionalStorageController.dispose();
    super.dispose();
  }

  bool _isDurationValid() {
    final nowTS = DateTime.now().millisecondsSinceEpoch;
    final subscriptionDueTSMS = nowTS + (_durationDays * 24 * 60 * 60 * 1000);
    talker.debug({'subscriptionDueTSMS': subscriptionDueTSMS});

    if (widget.subscription == null) return _durationDays >= 3;

    return (widget.subscription!.currentPeriodEnd - subscriptionDueTSMS).abs() >= (3 * 24 * 60 * 60 * 1000);
  }

  bool _isStorageValid() {
    final bytes = (_additionalStorageGb * 1024 * 1024 * 1024);
    if (widget.subscription == null) return _additionalStorageGb >= 10;

    return (widget.subscription!.privileges.storageBytes - (widget.plan.privileges.storageBytes + bytes)).abs() >= (10 * 1024 * 1024 * 1024);
  }

  bool _isPayable() {
    bool isUpgrading = false;
    if (widget.subscription != null) isUpgrading = true;

    talker.debug({
      'plan': widget.plan.toJson(),
      'subscription': widget.subscription?.toJson(),
      '_durationDays': _durationDays,
      '_additionalStorageGb': _additionalStorageGb,
      '_submitting': _submitting,
      '_selectedMethod': _selectedMethod,
      '_durationError': _durationError,
      '_additionalStorageError': _additionalStorageError,
      '_totalPrice': _totalPrice,
    });

    if (_selectedMethod == null || _durationError != null || _additionalStorageError != null || _durationDays == 0) {
      return false;
    }

    talker.debug({
      'planTitle': widget.plan.title == widget.subscription?.planTitle,
      'subscriptionDueTSMS': _isDurationValid(),
      'storageBytes': _isStorageValid(),
    });

    if (isUpgrading && (widget.plan.title == widget.subscription?.planTitle && !_isDurationValid() && !_isStorageValid())) {
      return false;
    }

    return true;
  }

  Future<void> _pay() async {
    final l10n = AppLocalizations.of(context)!;

    if (_submitting || !_isPayable()) return;

    final nowTS = DateTime.now().millisecondsSinceEpoch;
    final subscriptionDueTSMS = nowTS + (_durationDays * 24 * 60 * 60 * 1000);

    setState(() => _submitting = true);

    try {
      final result = await apiCall(
        () => _authDio.post(
          '/api/subscription',
          data: {
            'planTitle': widget.plan.title,
            'paymentMethod': _selectedMethod,
            'subscriptionDueTSMS': subscriptionDueTSMS,
            'extraStorageBytes': _additionalStorageGb * 1024 * 1024 * 1024,
          },
        ),
      );

      if (!mounted) return;

      if (result.isFailure || result.dataOrNull == null) {
        setState(() => _submitting = false);
        NotificationService.showError(context: context, message: l10n.checkout_pay_failed);
        return;
      }

      final redirectUrl = result.dataOrNull!?['redirectUrl'] as String?;
      if (redirectUrl == null) {
        setState(() => _submitting = false);
        NotificationService.showError(context: context, message: l10n.checkout_pay_failed);
        return;
      }

      final uri = Uri.parse(redirectUrl);
      var launched = false;
      try {
        launched = await launchUrl(
          uri,
          webOnlyWindowName: kIsWeb ? '_blank' : null,
          mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        );
      } catch (_) {
        launched = false;
      }

      if (!launched) {
        NotificationService.showError(message: l10n.checkout_pay_failed);
        return;
      }

      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      talker.error('caught error in _pay method of _CheckoutDialogState', err);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _calculateTotalPrice(String selectedMethod, Currency selectedCurrency) async {
    final l10n = AppLocalizations.of(context)!;

    if (_submitting || !_isPayable()) return;

    final nowTS = DateTime.now().millisecondsSinceEpoch;
    final subscriptionDueTSMS = nowTS + (_durationDays * 24 * 60 * 60 * 1000);

    setState(() => _submitting = true);

    try {
      final result = await apiCall(
        () => _authDio.get(
          '/api/subscription/calculate?planTitle=${widget.plan.title}&paymentMethod=$selectedMethod&subscriptionDueTSMS=$subscriptionDueTSMS&extraStorageBytes=${_additionalStorageGb * 1024 * 1024 * 1024}',
        ),
      );

      if (!mounted) return;

      if (result.isFailure || result.dataOrNull == null) {
        NotificationService.showError(context: context, message: l10n.checkout_pay_failed);
        return;
      }

      talker.debug({'data': result.dataOrNull});

      final totalPrice = result.dataOrNull?['totalPrice'] as double?;
      if (totalPrice == null) {
        NotificationService.showError(context: context, message: l10n.checkout_pay_failed);
        return;
      }

      final c = result.dataOrNull?['currency'] as String?;
      final currency = c == null ? null : Currency.toCurrency(c);
      talker.debug({currency, selectedCurrency});
      if (currency != selectedCurrency) {
        NotificationService.showError(context: context, message: l10n.checkout_pay_failed);
        return;
      }

      setState(() {
        _totalPrice = totalPrice;
      });
    } catch (err) {
      talker.error('caught error in _calculateTotalPrice method of _CheckoutDialogState', err);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final l10n = AppLocalizations.of(context)!;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.plan.title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(l10n.checkout_title, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),

                  if (widget.subscription != null && !_isPayable())
                    Container(
                      padding: EdgeInsets.all(8.0),
                      decoration: BoxDecoration(color: theme.colorScheme.error, borderRadius: BorderRadius.circular(12)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.checkout_upgrade_requirement_title, style: TextStyle(color: theme.colorScheme.onError)),
                          Text(l10n.checkout_upgrade_duration_requirement, style: TextStyle(color: theme.colorScheme.onError)),
                          Text(l10n.checkout_upgrade_storage_requirement, style: TextStyle(color: theme.colorScheme.onError)),
                        ],
                      ),
                    ),
                  if (widget.subscription != null && !_isPayable()) const SizedBox(height: 30),

                  _buildDurationPicker(l10n),
                  const SizedBox(height: 20),

                  _buildAdditionalStorageField(l10n),
                  const SizedBox(height: 20),

                  Text(l10n.checkout_payment_method, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _buildMethodsList(context, l10n),

                  const SizedBox(height: 20),
                  _buildPriceRow(context, l10n),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: Text(l10n.checkout_cancel)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: !_submitting && _isPayable() ? _pay : null,
                          child: _submitting
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(l10n.checkout_pay),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationPicker(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.checkout_duration_days, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextFormField(
          controller: _durationController,
          enabled: !_submitting,
          keyboardType: TextInputType.text,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), suffixText: l10n.checkout_days_suffix, errorText: _durationError),
          onChanged: (value) async {
            double? parsed = double.tryParse(value);
            if (parsed != null) {
              parsed = (parsed * 100).truncateToDouble() / 100;
              _durationDays = parsed;
            }

            if (mounted) {
              setState(() {
                _totalPrice = null;
                if (parsed == null || parsed < 1) {
                  _durationError = l10n.checkout_duration_invalid;
                } else {
                  _durationError = null;
                  _durationDays = parsed;
                }
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildAdditionalStorageField(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.checkout_additional_storage, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextFormField(
          controller: _additionalStorageController,
          enabled: !_submitting,
          keyboardType: TextInputType.text,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[0-9.]*$'))],
          decoration: InputDecoration(isDense: true, border: const OutlineInputBorder(), suffixText: 'GB', errorText: _additionalStorageError),
          onChanged: (value) async {
            // Empty field is treated as 0 rather than invalid, since
            // most users will leave this blank/default.
            if (value.isEmpty) {
              setState(() {
                _additionalStorageError = null;
                _additionalStorageGb = _defaultAdditionalStorageGb;
              });
              return;
            }

            final parsed = double.tryParse(value);
            if (parsed != null) {
              _additionalStorageGb = parsed;
            }

            if (mounted) {
              setState(() {
                _totalPrice = null;
                if (parsed == null || parsed < 0) {
                  _additionalStorageError = l10n.checkout_storage_invalid;
                } else {
                  _additionalStorageError = null;
                  _additionalStorageGb = parsed;
                }
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildMethodsList(BuildContext context, AppLocalizations l10n) {
    return ChoosePaymentCurrency(
      onSelect: (paymentCurrency) async {
        await _calculateTotalPrice(paymentCurrency.paymentMethod, paymentCurrency.currency);
        if (mounted) {
          setState(() {
            _selectedMethod = paymentCurrency.paymentMethod;
            _selectedCurrency = paymentCurrency.currency;
          });
        }
      },
    );
  }

  Widget _buildPriceRow(BuildContext context, AppLocalizations l10n) {
    final locale = Localizations.localeOf(context).languageCode;
    final total = _totalPrice;
    final currency = _selectedCurrency;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.checkout_total, style: Theme.of(context).textTheme.titleMedium),
            Text(
              (total == null || currency == null) ? '—' : CurrencyFormatter.format(total, currency, locale: locale),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Button(
          type: ButtonType.elevated,
          label: l10n.calculate_price,
          onPressed: _submitting || !_isPayable()
              ? null
              : () async {
                  await _calculateTotalPrice(_selectedMethod!, _selectedCurrency!);
                },
        ),
        if (total != null && total < 0) Text(l10n.checkout_free_purchase_message),
      ],
    );
  }
}
