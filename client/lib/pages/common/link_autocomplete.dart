// link_autocomplete.dart
//
// A text field that suggests the existing items matching what was typed (debounced search) and, when
// [onCreate] is given, offers to create a new one ("Create ..."). Picking an entry clears the field.
// Used to pick the artist / album of an audio's relationship (audio_links_section.dart).

import 'package:avarim/api/models/with_id.dart';
import 'package:flutter/material.dart';

/// Wait this long after the last keystroke before searching.
const _kSearchDebounce = Duration(milliseconds: 300);

/// The extra "Create ..." entry at the end of the suggestions.
class _CreateOption {
  const _CreateOption(this.name);

  final String name;
}

/// See the file header.
class LinkAutocomplete<T extends WithId> extends StatefulWidget {
  const LinkAutocomplete({
    required this.label,
    required this.hint,
    required this.search,
    required this.labelOf,
    required this.onPick,
    this.onCreate,
    this.createLabel = 'Create',
    this.optionSubtitle,
    this.alwaysOfferCreate = false,
    this.excludeIds = const <String>{},
    this.enabled = true,
  });

  final String label;
  final String hint;

  /// Existing items matching the typed text.
  final Future<List<T>> Function(String query) search;
  final String Function(T item) labelOf;
  final Future<void> Function(T item) onPick;

  /// null: no "Create ..." entry.
  final Future<void> Function(String name)? onCreate;
  final String createLabel;

  /// A second line under a suggestion.
  final Widget? Function(T item)? optionSubtitle;

  /// Offer to create even when an item with exactly that name exists (for names that aren't unique).
  final bool alwaysOfferCreate;

  /// Items that are already linked: they aren't suggested again.
  final Set<String> excludeIds;
  final bool enabled;

  @override
  State<LinkAutocomplete<T>> createState() => LinkAutocompleteState<T>();
}

class LinkAutocompleteState<T extends WithId> extends State<LinkAutocomplete<T>> {
  int _ticket = 0; // answers of outdated searches are dropped
  TextEditingController? _controller;

  Future<Iterable<Object>> _options(TextEditingValue value) async {
    final query = value.text.trim();
    final ticket = ++_ticket;
    if (query.isEmpty) return const <Object>[];

    await Future<void>.delayed(_kSearchDebounce);
    if (ticket != _ticket) return const <Object>[];

    final found = await widget.search(query);
    if (ticket != _ticket) return const <Object>[];

    final available = found.where((e) => !widget.excludeIds.contains(e.id)).toList();
    final exact = found.any((e) => widget.labelOf(e).toLowerCase() == query.toLowerCase());
    final offerCreate = widget.onCreate != null && (widget.alwaysOfferCreate || !exact);
    return <Object>[...available, if (offerCreate) _CreateOption(query)];
  }

  Future<void> _selected(Object option) async {
    final controller = _controller;
    // the field shows the picked name for a moment: clear it once the frame is done
    WidgetsBinding.instance.addPostFrameCallback((_) => controller?.clear());

    if (option is _CreateOption) {
      await widget.onCreate?.call(option.name);
    } else {
      await widget.onPick(option as T);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Object>(
      optionsBuilder: _options,
      displayStringForOption: (o) => o is _CreateOption ? o.name : widget.labelOf(o as T),
      onSelected: _selected,
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        _controller = controller;
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(labelText: widget.label, hintText: widget.hint, border: const OutlineInputBorder(), isDense: true, prefixIcon: const Icon(Icons.search)),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 480),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final o = list[i];
                  if (o is _CreateOption) {
                    return ListTile(dense: true, leading: const Icon(Icons.add_circle_outline), title: Text('${widget.createLabel} "${o.name}"'), onTap: () => onSelected(o));
                  }
                  final item = o as T;
                  return ListTile(
                    dense: true,
                    title: Text(widget.labelOf(item), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: widget.optionSubtitle?.call(item),
                    onTap: () => onSelected(o),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
