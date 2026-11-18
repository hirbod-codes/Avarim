import 'package:avarim/api/models/artist.dart';
import 'package:avarim/app_config.dart';
import 'package:avarim/components/core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../music_search_config.dart';
import '../authenticated_thumbnail.dart';
import '../popups/entity_popups.dart';
import 'item_actions.dart';

/// A list row for an [Artist]: tap opens its page; in edit mode it has edit / delete buttons.
class ArtistListItem extends ConsumerStatefulWidget {
  const ArtistListItem({super.key, required this.artist, this.onTap, this.isEditMode = false, this.onDeleted});

  final Artist artist;

  /// Called on tap, before the artist page opens.
  final VoidCallback? onTap;

  /// Shows edit / delete buttons.
  final bool isEditMode;

  /// Called with the artist's id once it was deleted (so the list can drop it).
  final ValueChanged<String>? onDeleted;

  @override
  ConsumerState<ArtistListItem> createState() => _ArtistListItemState();
}

class _ArtistListItemState extends ConsumerState<ArtistListItem> {
  bool _isDeleting = false;

  void _openArtistPage() {
    widget.onTap?.call();
    context.push(Uri(path: kArtistDetailsRoutePath, queryParameters: {'artistId': widget.artist.id}).toString());
  }

  Future<void> _delete() async {
    if (!mounted) return;

    setState(() => _isDeleting = true);
    await onDeleteArtist(context, ref, widget.artist, onDeleted: widget.onDeleted);
    if (mounted) setState(() => _isDeleting = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: _openArtistPage,
      leading: AuthenticatedThumbnail(imageUrl: '${AppConfig.apiUrl}/api/artist/avatar/${widget.artist.id}', placeholderIcon: Icons.person, isCircular: true),
      title: SingleLineText(widget.artist.name),
      trailing: widget.isEditMode ? EditDeleteActions(isBusy: _isDeleting, onEdit: () => showEditPopup(widget.artist), onDelete: _delete) : null,
    );
  }
}
