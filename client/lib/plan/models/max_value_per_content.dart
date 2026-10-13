class MaxValuePerContent {
  final int string;
  final int richText;
  final int image;
  final int audio;
  final int video;

  MaxValuePerContent({required this.string, required this.richText, required this.image, required this.audio, required this.video});

  factory MaxValuePerContent.fromJson(Map<String, dynamic> json) => MaxValuePerContent(
    string: json['string'] as int,
    richText: json['richText'] as int,
    image: json['image'] as int,
    audio: json['audio'] as int,
    video: json['video'] as int,
  );

  Map<String, dynamic> toJson() => {'string': string, 'richText': richText, 'image': image, 'audio': audio, 'video': video};
}
