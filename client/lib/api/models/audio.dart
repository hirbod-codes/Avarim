import 'package:avarim/api/models/helpers.dart';
import 'package:avarim/api/models/loudness.dart';
import 'package:avarim/api/models/replay_gain.dart';
import 'package:avarim/api/models/with_id.dart';

/// Mirrors the backend `audio` document (`audioSchema`).
/// Everything except `_id` and `title` is optional so slimmer responses
/// (e.g. the `audioSearchSchema` shape: `_id`, `title`, `lyrics`) still parse.
class Audio extends WithId {
  const Audio({
    required super.id,
    required this.title,
    this.schemaVersion,
    this.totalFilesBytes,
    this.bucketKey,
    this.webBucketKey,
    this.coverArtKey,
    this.deletionQueued,
    this.temporary,
    this.isPrepared,
    this.createdAt,
    this.updatedAt,
    this.tags,
    this.technical,
  });

  final String title;
  final String? schemaVersion;
  final int? totalFilesBytes;

  final String? bucketKey; // avarim/audio/<audioId>
  final String? webBucketKey; // avarim/audio/web/<audioId>
  final String? coverArtKey; // avarim/audio/cover_art/<audioId>

  final bool? deletionQueued;
  final bool? temporary;
  final bool? isPrepared;

  /// Backend sends numbers; assumed to be epoch milliseconds (JS `Date.now()`).
  final DateTime? createdAt;
  final DateTime? updatedAt;

  final AudioTags? tags;
  final AudioTechnical? technical;

  factory Audio.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? v) => v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());

    return Audio(
      id: json['_id'].toString(),
      title: json['title'] as String,
      schemaVersion: json['schemaVersion'] as String?,
      totalFilesBytes: asInt(json['totalFilesBytes']),
      bucketKey: json['bucketKey'] as String?,
      webBucketKey: json['webBucketKey'] as String?,
      coverArtKey: json['coverArtKey'] as String?,
      deletionQueued: json['deletionQueued'] as bool?,
      temporary: json['temporary'] as bool?,
      isPrepared: json['isPrepared'] as bool?,
      createdAt: date(json['createdAt']),
      updatedAt: date(json['updatedAt']),
      tags: json['tags'] == null ? null : AudioTags.fromJson(json['tags'] as Map<String, dynamic>),
      technical: json['technical'] == null ? null : AudioTechnical.fromJson(json['technical'] as Map<String, dynamic>),
    );
  }
}

class AudioTags {
  const AudioTags({
    this.audioTitle,
    this.artists = const [],
    this.albumArtists = const [],
    this.album,
    this.trackNumber,
    this.trackTotal,
    this.discNumber,
    this.discTotal,
    this.year,
    this.releaseDate,
    this.genres = const [],
    this.composers = const [],
    this.lyricists = const [],
    this.producers = const [],
    this.label,
    this.catalogNumber,
    this.isrc = const [],
    this.bpm,
    this.key,
    this.compilation = false,
    this.language,
    this.copyright,
    this.comment,
    this.lyrics,
  });

  /// Title extracted from the audio file (may differ from [Audio.title]).
  final String? audioTitle;
  final List<String> artists;
  final List<String> albumArtists;
  final String? album;
  final int? trackNumber;
  final int? trackTotal;
  final int? discNumber;
  final int? discTotal;
  final int? year;

  /// ISO-8601 partial date: YYYY, YYYY-MM or YYYY-MM-DD.
  final String? releaseDate;
  final List<String> genres;
  final List<String> composers;
  final List<String> lyricists;
  final List<String> producers;
  final String? label;
  final String? catalogNumber;
  final List<String> isrc;
  final double? bpm;
  final String? key;
  final bool compilation;
  final String? language;
  final String? copyright;
  final String? comment;
  final String? lyrics;

  factory AudioTags.fromJson(Map<String, dynamic> json) => AudioTags(
    audioTitle: json['audioTitle'] as String?,
    artists: asStrList(json['artists']),
    albumArtists: asStrList(json['albumArtists']),
    album: json['album'] as String?,
    trackNumber: asInt(json['trackNumber']),
    trackTotal: asInt(json['trackTotal']),
    discNumber: asInt(json['discNumber']),
    discTotal: asInt(json['discTotal']),
    year: asInt(json['year']),
    releaseDate: json['releaseDate'] as String?,
    genres: asStrList(json['genres']),
    composers: asStrList(json['composers']),
    lyricists: asStrList(json['lyricists']),
    producers: asStrList(json['producers']),
    label: json['label'] as String?,
    catalogNumber: json['catalogNumber'] as String?,
    isrc: asStrList(json['isrc']),
    bpm: asDouble(json['bpm']),
    key: json['key'] as String?,
    compilation: json['compilation'] as bool? ?? false,
    language: json['language'] as String?,
    copyright: json['copyright'] as String?,
    comment: json['comment'] as String?,
    lyrics: json['lyrics'] as String?,
  );
}

/// Technical info extracted with ffprobe. The backend marks `sizeBytes`,
/// `sha256` and `audioSha256` as required; they're nullable here so a
/// projected/partial response doesn't crash parsing.
class AudioTechnical {
  const AudioTechnical({
    this.container,
    this.ffprobeFormat,
    this.codec,
    this.codecProfile,
    this.lossless,
    this.durationSec,
    this.bitrate,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    this.channelLayout,
    this.encoder,
    this.sizeBytes,
    this.sha256,
    this.audioSha256,
    this.tagTypes = const [],
    this.replayGain,
    this.loudness,
    this.waveform = const [],
  });

  final String? container;
  final String? ffprobeFormat;
  final String? codec;
  final String? codecProfile;
  final bool? lossless;
  final double? durationSec;
  final double? bitrate;
  final double? sampleRate;
  final int? bitDepth;
  final int? channels;
  final String? channelLayout;
  final String? encoder;
  final int? sizeBytes;
  final String? sha256;
  final String? audioSha256;
  final List<String> tagTypes;
  final ReplayGain? replayGain;
  final Loudness? loudness;
  final List<double> waveform;

  factory AudioTechnical.fromJson(Map<String, dynamic> json) => AudioTechnical(
    container: json['container'] as String?,
    ffprobeFormat: json['ffprobeFormat'] as String?,
    codec: json['codec'] as String?,
    codecProfile: json['codecProfile'] as String?,
    lossless: json['lossless'] as bool?,
    durationSec: asDouble(json['durationSec']),
    bitrate: asDouble(json['bitrate']),
    sampleRate: asDouble(json['sampleRate']),
    bitDepth: asInt(json['bitDepth']),
    channels: asInt(json['channels']),
    channelLayout: json['channelLayout'] as String?,
    encoder: json['encoder'] as String?,
    sizeBytes: asInt(json['sizeBytes']),
    sha256: json['sha256'] as String?,
    audioSha256: json['audioSha256'] as String?,
    tagTypes: asStrList(json['tagTypes']),
    replayGain: json['replayGain'] == null ? null : ReplayGain.fromJson(json['replayGain'] as Map<String, dynamic>),
    loudness: json['loudness'] == null ? null : Loudness.fromJson(json['loudness'] as Map<String, dynamic>),
    waveform: (json['waveform'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? const [],
  );
}
