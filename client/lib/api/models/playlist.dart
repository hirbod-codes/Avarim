// A playlist as returned by GET /api/playlist (same shape as Album / Artist, keyed by `_id`).

import 'package:avarim/api/models/with_id.dart';

class Playlist implements WithId {
  const Playlist({required this.id, required this.name, this.avatarKey});

  @override
  final String id;

  final String name;
  final String? avatarKey;

  factory Playlist.fromJson(Map<String, dynamic> json) =>
      Playlist(id: json['_id'].toString(), name: json['name'] as String, avatarKey: json['avatarKey'] as String?);
}
