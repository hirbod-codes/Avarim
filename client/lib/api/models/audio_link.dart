import 'package:avarim/api/models/album.dart';
import 'package:avarim/api/models/artist.dart';

/// One relationship of an audio: an artist and / or an album, both optional. An audio can be linked to an
/// artist without an album, to an album without an artist, or to both together.
class AudioLink {
  const AudioLink({this.artist, this.album});

  final Artist? artist;
  final Album? album;

  /// Same pair <=> same key.
  String get key => '${artist?.id ?? ''}|${album?.id ?? ''}';

  @override
  bool operator ==(Object other) => other is AudioLink && other.key == key;

  @override
  int get hashCode => key.hashCode;
}
