import 'package:avarim/api/models/with_id.dart';

class Artist extends WithId {
  const Artist({required super.id, required this.name});

  final String name;

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(id: json['_id'].toString(), name: json['name'] as String);
}
