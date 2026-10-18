// read_only_details.dart
//
// Card listing every field of a backend document that isn't editable on the page
// (ids, keys, dates, sizes, the "technical" block, ...). Shared by the edit pages.
// Nested maps listed in `nestedSections` become collapsible sections instead of one long row.

import 'package:flutter/material.dart';

class ReadOnlyDetails extends StatelessWidget {
  const ReadOnlyDetails({
    super.key,
    required this.data,
    required this.hiddenKeys,
    this.title = 'Details (read-only)',
    this.nestedSections = const {'technical': 'Technical details'},
  });

  /// The document returned by the backend.
  final Map<String, dynamic> data;

  /// Top-level keys that are NOT shown here (because they are editable elsewhere, or internal).
  final Set<String> hiddenKeys;

  final String title;

  /// Keys whose value is a nested map that gets its own collapsible section (key -> section title).
  /// `waveform` entries are skipped (a long list of numbers).
  final Map<String, String> nestedSections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final general = <MapEntry<String, String>>[];
    final sections = <String, List<MapEntry<String, String>>>{};

    data.forEach((key, value) {
      if (hiddenKeys.contains(key) || key.startsWith('__')) return;

      final sectionTitle = nestedSections[key];
      if (sectionTitle != null && value is Map) {
        final rows = sections.putIfAbsent(sectionTitle, () => []);
        value.forEach((nk, nv) {
          if (nk == 'waveform') return; // long list of numbers, not useful as text
          rows.add(MapEntry(_humanizeKey('$nk'), _formatValue('$nk', nv)));
        });
        return;
      }
      general.add(MapEntry(_humanizeKey(key), _formatValue(key, value)));
    });

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(title, style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [for (final e in general) _ReadOnlyRow(label: e.key, value: e.value)],
            ),
          ),
          for (final section in sections.entries)
            if (section.value.isNotEmpty)
              ExpansionTile(
                title: Text(section.key),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [for (final e in section.value) _ReadOnlyRow(label: e.key, value: e.value)],
              ),
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

String _humanizeKey(String key) {
  if (key == '_id') return 'ID';
  final spaced = key.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}').replaceAll('_', ' ').trim();
  if (spaced.isEmpty) return key;
  final lower = spaced.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

String _formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return i == 0 ? '$bytes B' : '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
}

String _formatValue(String key, Object? v) {
  if (v == null) return '—';

  if (v is num) {
    // Timestamps are assumed to be epoch milliseconds.
    if (key == 'createdAt' || key == 'updatedAt') {
      return DateTime.fromMillisecondsSinceEpoch(v.toInt()).toLocal().toString().split('.').first;
    }
    if (key == 'sizeBytes' || key == 'totalFilesBytes') return _formatBytes(v.toInt());
    if (key == 'durationSec') {
      final s = v.round();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }
    if (key == 'sampleRate') return '${v.round()} Hz';
    return v.toString();
  }

  if (v is bool) return v ? 'Yes' : 'No';
  if (v is List) return v.isEmpty ? '—' : v.map((e) => _formatValue('', e)).join(', ');
  if (v is Map) {
    if (v.isEmpty) return '—';
    return v.entries.map((e) => '${_humanizeKey('${e.key}')}: ${_formatValue('${e.key}', e.value)}').join(' · ');
  }

  final s = v.toString();
  return s.isEmpty ? '—' : s;
}
