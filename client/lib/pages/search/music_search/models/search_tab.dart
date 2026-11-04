/// The tabs of the search page. The selected tab decides which endpoint is searched.
enum SearchTab {
  artists('Artists', '/api/artist'),
  albums('Albums', '/api/album'),
  audios('Audios', '/api/audio'),

  /// Lists the audios no artist is linked to (so they can be found and given one).
  audiosWithoutArtist('No artist', '/api/audio/no_artist'),

  audiosWithoutAlbum('Singles', '/api/audio/no_album'),

  playlists('Playlists', '/api/playlist');

  const SearchTab(this.displayLabel, this.endpointPath);

  final String displayLabel;
  final String endpointPath;
}
