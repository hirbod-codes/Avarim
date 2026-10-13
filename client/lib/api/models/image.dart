import 'dart:convert';

class ImageInfo {
  String id;
  String title;
  int? createdAt;
  int? updatedAt;

  ImageInfo({required this.id, required this.title, this.createdAt, this.updatedAt});

  Map<String, dynamic> toJson() => ({'id': id, 'title': title, 'createdAt': createdAt, 'updatedAt': updatedAt});

  @override
  String toString() => jsonEncode(toJson());

  factory ImageInfo.fromJson(Map<String, dynamic> json) {
    final id = json['_id'];
    final title = json['title'];
    final createdAt = (json['metadata']?['createdAt'] as num?)?.toInt();
    final updatedAt = (json['metadata']?['updatedAt'] as num?)?.toInt();

    return ImageInfo(id: id, title: title, createdAt: createdAt, updatedAt: updatedAt);
  }
}
