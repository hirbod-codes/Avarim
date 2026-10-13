import 'dart:convert';

class LeafPost {
  String id;

  LeafPost({required this.id});
}

enum ContentType { string, richText, imageId, videoId, audioId }

class Content {
  ContentType type;
  List<String> value;

  Content({required this.type, required this.value});

  static ContentType parseContentType(String value) {
    switch (value) {
      case 'string':
        return ContentType.string;
      case 'richText':
        return ContentType.richText;
      case 'imageId':
        return ContentType.imageId;
      case 'videoId':
        return ContentType.videoId;
      case 'audioId':
        return ContentType.audioId;
      default:
        throw ArgumentError('Unknown ContentType: $value');
    }
  }

  static String stringifyContentType(ContentType value) {
    switch (value) {
      case ContentType.string:
        return 'string';
      case ContentType.richText:
        return 'richText';
      case ContentType.imageId:
        return 'imageId';
      case ContentType.videoId:
        return 'videoId';
      case ContentType.audioId:
        return 'audioId';
    }
  }

  Content copyWith({ContentType? type, List<String>? value}) {
    return Content(type: type ?? this.type, value: value ?? [...this.value]);
  }

  Map<String, dynamic> toJson() => ({'type': stringifyContentType(type), 'value': value});

  @override
  String toString() => jsonEncode(toJson());

  factory Content.fromJson(Map<String, dynamic> json) {
    final type = parseContentType(json['type'] as String);
    final value = (json['value'] as List<dynamic>).cast<String>();

    return Content(type: type, value: value);
  }
}

class Leaf {
  late String id;
  late String? userId;
  late String treeNodeId;
  late String title;
  late List<Content> termContents;
  late List<Content> definitionContents;
  late int? createdAt;
  late int? updatedAt;

  Leaf({required this.id, this.userId, required this.treeNodeId, required this.title, required this.termContents, required this.definitionContents, this.createdAt, this.updatedAt});

  Map<String, dynamic> toJson() {
    return {'id': id, 'userId': userId, 'treeNodeId': treeNodeId, 'title': title, 'termContents': termContents.map((m) => m.toJson()).toList(), 'definitionContents': definitionContents.map((m) => m.toJson()).toList(), 'createdAt': createdAt, 'updatedAt': updatedAt};
  }

  Leaf copyWith({String? id, String? title, List<Content>? termContents, List<Content>? definitionContents}) {
    return Leaf(id: id ?? this.id, title: title ?? this.title, termContents: termContents ?? this.termContents.map((m) => m.copyWith()).toList(), definitionContents: definitionContents ?? this.definitionContents.map((m) => m.copyWith()).toList(), userId: userId, treeNodeId: treeNodeId, createdAt: createdAt, updatedAt: updatedAt);
  }

  factory Leaf.fromJson(Map<String, dynamic> json) {
    final id = json['_id'];
    final userId = json['userId'];
    final treeNodeId = json['treeNodeId'];
    final title = json['title'];
    final termContents = (json['termContents'] as List<dynamic>?)?.map((e) => Content.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final definitionContents = (json['definitionContents'] as List<dynamic>?)?.map((e) => Content.fromJson(e as Map<String, dynamic>)).toList() ?? [];
    final createdAt = (json['createdAt'] as num).toInt();
    final updatedAt = (json['updatedAt'] as num).toInt();

    return Leaf(id: id, userId: userId, treeNodeId: treeNodeId, title: title, termContents: termContents, definitionContents: definitionContents, createdAt: createdAt, updatedAt: updatedAt);
  }
}
