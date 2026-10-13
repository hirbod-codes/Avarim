import 'dart:convert';

class Video {
  String id;
  String title;
  int? createdAt;
  int? updatedAt;

  Video({required this.id, required this.title, required this.createdAt, required this.updatedAt});

  Map<String, dynamic> toJson() => ({'id': id, 'title': title, 'createdAt': createdAt, 'updatedAt': updatedAt});

  @override
  String toString() => jsonEncode(toJson());

  factory Video.fromJson(Map<String, dynamic> json) {
    final id = json['_id'];
    final title = json['title'];
    final createdAt = (json['createdAt'] as num?)?.toInt();
    final updatedAt = (json['updatedAt'] as num?)?.toInt();

    return Video(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt);
  }
}
