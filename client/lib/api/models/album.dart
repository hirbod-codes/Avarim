import 'package:avarim/api/models/with_id.dart';

class Album extends WithId {
  const Album({required super.id, required this.name, this.artistId});

  final String name;

  /// The artist that owns the album. null when it has none: an album belongs to zero or one artist, and
  /// album names are only unique together with their artist.
  final String? artistId;

  factory Album.fromJson(Map<String, dynamic> json) => Album(id: json['_id'].toString(), name: json['name'] as String, artistId: json['artistId']?.toString());
}
