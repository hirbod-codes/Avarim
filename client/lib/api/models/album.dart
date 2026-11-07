import 'package:avarim/api/models/with_id.dart';

class Album extends WithId {
  const Album({required super.id, required this.name, this.publishedYear, this.publishedMonth, this.doNotUseFirstAudioCoverArt});

  final String name;
  final String? publishedYear;
  final String? publishedMonth;
  final bool? doNotUseFirstAudioCoverArt;

  factory Album.fromJson(Map<String, dynamic> json) => Album(
    id: json['_id'].toString(),
    name: json['name'] as String,
    publishedYear: json['publishedYear'] as String?,
    publishedMonth: json['publishedMonth'] as String?,
    doNotUseFirstAudioCoverArt: json['doNotUseFirstAudioCoverArt'] as bool?,
  );
}
