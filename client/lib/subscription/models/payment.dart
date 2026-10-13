import 'package:avarim/plan/models/currency_label.dart';
import 'package:avarim/subscription/models/payment_method.dart';

class Payment {
  final PaymentMethod method;
  final Currency currency;
  final double amount;

  const Payment({required this.method, required this.currency, required this.amount});

  factory Payment.fromJson(Map<String, dynamic> json) =>
      Payment(method: toPaymentMethod(json['method'] as String), currency: Currency.toCurrency(json['currency'] as String), amount: json['amount']);

  Map<String, dynamic> toJson() => {'method': method.name, 'currency': currency.name, 'amount': amount};
}
