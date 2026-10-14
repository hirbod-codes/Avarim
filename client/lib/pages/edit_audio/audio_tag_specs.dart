// audio_tag_specs.dart
//
// Describes the editable tag fields (mirrors the backend `audioTags` schema):
// the form is generated from [kTagGroups], so adding a tag is one line here.

enum TagKind { text, multiline, integer, decimal, list, flag }

class TagSpec {
  const TagSpec(
    this.key,
    this.label,
    this.kind, {
    this.hint,
    this.min,
    this.max,
    this.maxLength = 2000,
    this.pattern,
    this.patternMessage,
    this.maxItems = 50,
    this.normalize,
  });

  final String key;
  final String label;
  final TagKind kind;
  final String? hint;
  final num? min;
  final num? max;

  /// Max length of the text (or of each list item).
  final int maxLength;

  /// Regex source the text (or each list item) must match.
  final String? pattern;
  final String? patternMessage;
  final int maxItems;

  /// Applied to list items before validation (e.g. ISRC upper-casing).
  final String Function(String)? normalize;
}

class TagGroup {
  const TagGroup(this.title, this.fields);
  final String title;
  final List<TagSpec> fields;
}

String normalizeIsrc(String v) => v.replaceAll('-', '').replaceAll(' ', '').toUpperCase();

const kTagGroups = [
  TagGroup('Track info', [
    TagSpec('audioTitle', 'Title in file tags', TagKind.text),
    TagSpec('artists', 'Artists', TagKind.list),
    TagSpec('album', 'Album', TagKind.text),
    TagSpec('genres', 'Genres', TagKind.list),
    TagSpec('year', 'Year', TagKind.integer, min: 1000, max: 9999),
    TagSpec(
      'releaseDate',
      'Release date',
      TagKind.text,
      hint: 'YYYY, YYYY-MM or YYYY-MM-DD',
      pattern: r'^\d{4}(-\d{2}(-\d{2})?)?$',
      patternMessage: 'Use YYYY, YYYY-MM or YYYY-MM-DD',
    ),
  ]),
  TagGroup('Numbering', [
    TagSpec('trackNumber', 'Track number', TagKind.integer, min: 1),
    TagSpec('trackTotal', 'Track total', TagKind.integer, min: 1),
    TagSpec('discNumber', 'Disc number', TagKind.integer, min: 1),
    TagSpec('discTotal', 'Disc total', TagKind.integer, min: 1),
    TagSpec('compilation', 'Compilation', TagKind.flag),
  ]),
  TagGroup('Credits & release', [
    TagSpec('composers', 'Composers', TagKind.list),
    TagSpec('lyricists', 'Lyricists', TagKind.list),
    TagSpec('producers', 'Producers', TagKind.list),
    TagSpec('label', 'Label', TagKind.text),
    TagSpec('catalogNumber', 'Catalog number', TagKind.text),
    TagSpec('copyright', 'Copyright', TagKind.text),
    TagSpec('language', 'Language', TagKind.text),
  ]),
  TagGroup('Other', [
    TagSpec('bpm', 'BPM', TagKind.decimal, min: 0.01, max: 400),
    TagSpec('key', 'Musical key', TagKind.text),
    TagSpec(
      'isrc',
      'ISRC',
      TagKind.list,
      maxItems: 10,
      pattern: r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$',
      patternMessage: 'Invalid ISRC (e.g. USRC17607839)',
      normalize: normalizeIsrc,
    ),
    TagSpec('comment', 'Comment', TagKind.multiline, maxLength: 20000),
    TagSpec('lyrics', 'Lyrics', TagKind.multiline, maxLength: 200000),
  ]),
];

final kAllTagSpecs = [for (final g in kTagGroups) ...g.fields];
