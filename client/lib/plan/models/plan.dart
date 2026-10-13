import 'price.dart';
import 'privileges.dart';

class Plan {
  final String id;
  final String title;
  final Price price;
  final Privileges privileges;

  const Plan({required this.id, required this.title, required this.price, required this.privileges});

  factory Plan.fromJson(Map<String, dynamic> json) => Plan(
    id: json['_id'] as String,
    title: json['title'] as String,
    price: Price.fromJson(json['price'] as Map<String, dynamic>),
    privileges: Privileges.fromJson(json['privileges'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {'_id': id, 'title': title, 'price': price.toJson(), 'privileges': privileges.toJson()};
}
