import 'dart:async';

import 'package:avarim/auth/token_storage.dart';
import 'package:avarim/lib/talker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A square (or circular) thumbnail fetched from [imageUrl] with the user's access token.
/// A [placeholderIcon] is shown while the token loads, when there is no URL, and when the image fails to load.
class AuthenticatedThumbnail extends ConsumerStatefulWidget {
  const AuthenticatedThumbnail({super.key, required this.imageUrl, required this.placeholderIcon, this.isCircular = false});

  final String? imageUrl;
  final IconData placeholderIcon;
  final bool isCircular;

  @override
  ConsumerState<AuthenticatedThumbnail> createState() => _AuthenticatedThumbnailState();
}

class _AuthenticatedThumbnailState extends ConsumerState<AuthenticatedThumbnail> {
  static const double _thumbnailSize = 48;
  static const double _squareCornerRadius = 8;

  String? _accessToken;
  bool _isLoadingAccessToken = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAccessToken());
  }

  Future<void> _loadAccessToken() async {
    try {
      final tokenStorage = ref.read(tokenStorageProvider);
      final accessToken = await tokenStorage.getAccessToken();
      if (!mounted) return;

      setState(() {
        _accessToken = accessToken;
        _isLoadingAccessToken = false;
      });
    } catch (error, stackTrace) {
      talker.error('caught error while trying to fetch image', error, stackTrace);
      if (!mounted) return;

      setState(() {
        _isLoadingAccessToken = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final borderRadius = BorderRadius.circular(widget.isCircular ? _thumbnailSize / 2 : _squareCornerRadius);
    final placeholder = Container(
      width: _thumbnailSize,
      height: _thumbnailSize,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(widget.placeholderIcon),
    );

    if (_isLoadingAccessToken) return ClipRRect(borderRadius: borderRadius, child: placeholder);

    final image = widget.imageUrl == null
        ? placeholder
        : Image.network(
            widget.imageUrl!,
            width: _thumbnailSize,
            height: _thumbnailSize,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => placeholder,
            headers: {'Authorization': 'Bearer $_accessToken'},
          );

    return ClipRRect(borderRadius: borderRadius, child: image);
  }
}
