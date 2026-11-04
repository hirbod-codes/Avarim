// Tunable settings of the music search feature.

/// How long to wait after the last keystroke before searching.
const kSearchInputDebounceDuration = Duration(seconds: 2);

/// How many results are requested per page of a search.
const kSearchResultsPageSize = 20;

/// First page number your API expects (change to 0 if it is zero-based).
const kFirstPageNumber = 1;

/// Page size used when fetching ALL the audios of an album / playlist to put them in the player queue.
const kQueueAudioIdsFetchPageSize = 50;

/// Ask "Delete this audio?" before actually deleting. Set to false to delete on the first press.
const kShouldConfirmBeforeDelete = true;

const kArtistDetailsRoutePath = '/artist';
const kEditArtistRoutePath = '/artist/edit';
const kEditAlbumRoutePath = '/album/edit';
const kEditAudioRoutePath = '/audio/edit';
