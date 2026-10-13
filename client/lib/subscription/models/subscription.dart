import 'package:avarim/plan/models/privileges.dart';

import 'payment.dart';
import 'status.dart';

class Subscription {
  final String id;
  final String planTitle;
  final Privileges privileges;
  final Status status;
  final int currentPeriodEnd;
  final Payment payment;

  const Subscription({
    required this.id,
    required this.planTitle,
    required this.payment,
    required this.privileges,
    required this.status,
    required this.currentPeriodEnd,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
    id: json['_id'] as String,
    status: toStatus(json['status'] as String),
    planTitle: json['planTitle'] as String,
    payment: Payment.fromJson(json['payment'] as Map<String, dynamic>),
    privileges: Privileges.fromJson(json['privileges'] as Map<String, dynamic>),
    currentPeriodEnd: json['currentPeriodEnd'] as int,
  );

  Map<String, dynamic> toJson() => {
    '_id': id,
    'status': status.name,
    'planTitle': planTitle,
    'payment': payment.toJson(),
    'privileges': privileges.toJson(),
    'currentPeriodEnd': currentPeriodEnd,
  };
}
