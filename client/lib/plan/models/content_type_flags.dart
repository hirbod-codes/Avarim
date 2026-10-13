/// Mirrors `allowedContentTypes` from `privilegesSchema`.
class ContentTypeFlags {
  final bool string;
  final bool richText;
  final bool image;
  final bool audio;
  final bool video;

  const ContentTypeFlags({required this.string, required this.richText, required this.image, required this.audio, required this.video});

  factory ContentTypeFlags.fromJson(Map<String, dynamic> json) => ContentTypeFlags(
    string: json['string'] as bool,
    richText: json['richText'] as bool,
    image: json['image'] as bool,
    audio: json['audio'] as bool,
    video: json['video'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'string': string.toString(),
    'richText': richText.toString(),
    'image': image.toString(),
    'audio': audio.toString(),
    'video': video.toString(),
  };

  bool isAllowed(String key) {
    switch (key) {
      case 'string':
        return string;
      case 'richText':
        return richText;
      case 'image':
        return image;
      case 'audio':
        return audio;
      case 'video':
        return video;
      default:
        return false;
    }
  }
}
