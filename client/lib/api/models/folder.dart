import 'dart:convert';

class Folder {
  late String id;
  late String title;
  late String? userId;
  late String? parentId;
  late int? createdAt;
  late int? updatedAt;

  Folder({required this.id, required this.title, this.userId, this.parentId, this.createdAt, this.updatedAt});

  Map<String, dynamic> toJson() => ({'id': id, 'title': title, 'createdAt': createdAt, 'updatedAt': updatedAt});

  @override
  String toString() => jsonEncode(toJson());

  factory Folder.fromJson(Map<String, dynamic> json) {
    final id = json['_id'];
    final userId = json['userId'];
    final title = json['title'];
    final parentId = json['parentId'];
    final createdAt = (json['createdAt'] as num).toInt();
    final updatedAt = (json['updatedAt'] as num).toInt();

    return Folder(id: id, title: title, userId: userId, parentId: parentId, createdAt: createdAt, updatedAt: updatedAt);
  }

  Folder copyWith({String? id, String? title, String? userId, String? parentId, int? createdAt, int? updatedAt}) {
    return Folder(id: id ?? this.id, title: title ?? this.title, userId: userId ?? this.userId, parentId: parentId ?? this.parentId, createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt);
  }
}
