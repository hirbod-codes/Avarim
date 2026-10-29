import 'package:avarim/api/models/with_id.dart';

class Album extends WithId {
  const Album({required super.id, required this.name});

  final String name;

  factory Album.fromJson(Map<String, dynamic> json) => Album(id: json['_id'].toString(), name: json['name'] as String);
}
