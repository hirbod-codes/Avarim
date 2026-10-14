// cover_art_section.dart
//
// An audio's cover art: GET / PUT /api/audio/coverArt/:audioId
// (all the behaviour lives in the shared ImageSection).

import 'package:avarim/pages/common/image_section.dart';
import 'package:flutter/material.dart';

String coverArtPath(String audioId) => '/api/audio/coverArt/$audioId';

class CoverArtSection extends StatelessWidget {
  const CoverArtSection({super.key, required this.audioId});

  final String audioId;

  @override
  Widget build(BuildContext context) {
    return ImageSection(path: coverArtPath(audioId), title: 'Cover art', hint: 'Shown next to this audio in lists and in the player.');
  }
}
