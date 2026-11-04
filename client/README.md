# Avarim

## To develop

### Run after change in video_player_provider.dart file run

```cmd
dart run build_runner build
```

or:

```cmd
dart run build_runner watch --delete-conflicting-outputs
```

### To use another mirror(CMD)

```cmd
setx PUB_HOSTED_URL "https://pub.flutter-io.cn"
setx FLUTTER_STORAGE_BASE_URL "https://storage.flutter-io.cn"
```

to rollback:

```cmd
reg delete "HKCU\Environment" /F /V PUB_HOSTED_URL
reg delete "HKCU\Environment" /F /V FLUTTER_STORAGE_BASE_URL
```

### To build

```cmd
flutter run -d windows --dart-define=API_URL=https://api.example.com --dart-define=ENV=prod
flutter run -d windows --dart-define=API_URL=https://localhost:8081 --dart-define=ENV=dev
flutter run -d web-server --web-port=5000 --dart-define=API_URL=http://localhost:8081 --dart-define=ENV=dev

flutter run -d web-server --web-port=5000  --dart-define=API_URL=https://avarim.ir:1404 --dart-define=ENV=dev
```

### Use nginx to redirect requests to backend(because of browsers CORS)

#### On windows

1. backend must first run mkcert.exe to generate `localhost+2.pem` and `localhost+2-key.pem`
2. nginx serves backend and https

download nginx and run:

```cmd
C:\nginx\nginx.exe -p C:\nginx\ -c <absolute\path\to\nginx.dev.conf>
```

for instance:

```cmd
C:\nginx\nginx.exe -p C:\nginx\ -c C:\projects\Avarim\client\nginx.dev.conf
```

To list or kill nginx processes

```cmd
tasklist | findstr nginx

taskkill /F /PID <pid>
```

### Localization

any update to localization .arb files needs a running this command: `flutter gen-l10n`

### for icons

run `dart run flutter_launcher_icons`

## workflow

Paths are relative to `client/lib/`. This covers every file I created or changed (and the ones I removed).
Nothing here was compiled or run by me: run `flutter analyze` first, then test the flows in "Check list" at the end.

Contents

1. The two ideas behind the changes
2. Files, by area (API layer, shared widgets, edit pages, browsing pages, player)
3. Removed files
4. Files outside `client/lib`
5. Backend routes the client uses
6. Check list

---

## 1. The two ideas behind the changes

**Relationships are rows, not fields.** An audio is no longer stored with its artists / album. Everything lives in the
`artistAlbumAudio` collection: a row is `{ audioId, artistId?, albumId? }` and both `artistId` and `albumId` are optional
(missing = none). So an audio can be on an album with no artist, with an artist and no album (one of the artist's
"singles"), with both, or with none, and an album can have many artists. The client reads them through
`/api/relationship/...` and edits them with `POST` / `DELETE /api/relationship`. Filter rule of the server's DELETE:
`null` = "any" (not filtered), an omitted field = "none" (the row must have no value there).

**Playing is not done by widgets.** One headless `PlaybackController` owns the audio engine and the queue sequencing;
the dock only shows the engine and sends it commands. This is what makes the next track start while the window is
minimized (Flutter draws no frames then, so nothing built by widgets can run).

```txt
AudioPlayerService (queue: ids, index, session, autoPlay)
        | queue changes
        v
PlaybackController ---- opens the track in ---> AppAudioPlayer (one engine for the app)
   | ended -> AudioPlayerService.next()            MediaKitAudioPlayer (+ MpvEqualizer)   non-web
   | feeds                                         WebAudioPlayer                          web
   v
SystemMediaSession (audio_service) -> notification / lock screen / media keys / SMTC / MPRIS

Dock widgets (AudioContainer -> AudioPlayerScreen, mini bar, queue)  =  show the engine + send commands
```

---

## 2. Files

### 2.1 API layer

#### `api/models/audio_link.dart` (new)

- **Responsibility:** one pair of an audio's relationships: an artist and / or an album, both optional.
- **API:** `AudioLink({Artist? artist, Album? album})`, `key` (`"<artistId>|<albumId>"`), `==` / `hashCode` by `key`.
- **Use:** build and compare pairs (`current.contains(link)`); the edit audio page lists them.

#### `api/controllers/audio_controller.dart` (changed)

- **Responsibility:** the audio document itself.
- **API (`audioControllerProvider`):** `get(audioId)` -> `GET /api/audio/info`, `getSignedToken(audioId)` ->
  `GET /api/audio/singed_token` (web streaming), `delete(audioId)` -> `DELETE /api/audio/:id` (admin; `true` = ok, a
  failure is toasted by the global interceptor).
- **Changed:** removed `getByTitle` (titles are not unique, lookups are by id) and the artist / album link methods
  (they live in `RelationshipController`).

#### `api/controllers/relationship_controller.dart` (new)

- **Responsibility:** read and edit the artist-album-audio relationships.
- **API (`relationshipControllerProvider`):**
  - reads, all pages fetched, throw on failure: `artistsOfAudio(audioId)`, `albumsOfAudio(audioId)`,
    `artistsOfAudioAlbum(audioId, albumId)`, `artistsOfAudioWithoutAlbum(audioId)`,
    `albumsOfAudioWithoutArtist(audioId)`, `artistsOfAlbum(albumId)`, `linksOfAudio(audioId)` (every pair of the audio);
  - writes (admin, `true` = ok): `create({audioId, artistId?, albumId?})`, `remove({audioId, artistId?, albumId?})`
    (absent fields are left out of the body on purpose: omitted = "none"), `removeLink({audioId, link, current})`
    (`remove` + read the pairs again + re-create any other pair the server removed by mistake).
- **Use:** `await ref.read(relationshipControllerProvider).create(audioId: id, artistId: a.id)`. The server does not
  check that the ids exist: only pass ids of records that do.

#### `api/controllers/library_controller.dart` (new)

- **Responsibility:** artists and albums as records: search (for autocompletes), look up, create.
- **API (`libraryControllerProvider`):** `searchArtists(query, {page, pageSize})`, `searchAlbums(...)` (empty list on
  failure), `artistById(id)`, `artistByName(name)`, `createArtist(name)` (the route answers without the new artist, so
  it is looked up by name), `createAlbum({name})` (the route answers `{ albumId }`; an album has no artist of its own).
  Lookups are silent (no toast); a failed create is toasted.

#### `api/providers/audio_links.dart` (new)

- **Responsibility:** cached lookups every screen shares, plus label helpers.
- **API:** `audioArtistsProvider(audioId)`, `audioAlbumsProvider(audioId)`, `albumArtistsProvider(albumId)`,
  `artistByIdProvider(artistId)` (kept 5 minutes; a failure is logged and not kept), `audioLinksProvider(audioId)`
  (the pairs, not kept), `artistsLabel(list)` / `albumsLabel(list)` ("A, B" or `null`).
- **Use:** `final label = artistsLabel(ref.watch(audioArtistsProvider(id)).value);`. After changing relationships:
  `ref.invalidate(audioLinksProvider(id))` (and the artists / albums ones).

### 2.2 Shared widgets

#### `pages/common/link_autocomplete.dart` (new)

- **Responsibility:** a text field that suggests existing items while typing and can offer to create a new one.
- **API:** `LinkAutocomplete<T extends WithId>(label, hint, search: (query) => Future<List<T>>, labelOf, onPick,
  onCreate?, createLabel, optionSubtitle?, alwaysOfferCreate, excludeIds, enabled)`. Search is debounced (300 ms); the
  field is cleared after a pick; "Create ..." is shown when `onCreate` is given and no exact match exists (or
  `alwaysOfferCreate`).
- **Use:** see `audio_links_section.dart`.

#### `components/contents/audio_row_actions.dart` (new)

- **Responsibility:** the two icon buttons at the end of an audio row.
- **API:** `AudioRowActions(audioId, initialPlaylistName)`: "Add to queue" (appends, current track keeps playing) and
  "Add to playlist" (`AudioPlaylistMenu`: add to a playlist, or save as a new one).
- **Use:** as the `trailing` of an audio row (search results, the artist's singles).

### 2.3 Edit pages

#### `pages/edit_audio/audio_links_section.dart` (new)

- **Responsibility:** the "Artists & albums" part of the edit audio page: the audio's pairs as rows.
- **API:** `AudioLinksSection(audioId)`.
- **What it does:** lists the pairs (`Artist` + `Album`, "No artist" / "No album" when empty) with a remove button
  (confirmation, then `removeLink`). Below, two autocompletes (artist, album, both optional, each with "Create ...")
  build a pair; **Add** sends `POST /api/relationship`. Changes are saved right away, the lists reload afterwards. A
  duplicate pair is refused client-side.
- **Use:** already placed in `edit_audio_page.dart` under the cover art.

#### `pages/edit_audio/edit_audio_page.dart` (changed)

Inserts `AudioLinksSection` after the cover art section; header comment updated.

#### `pages/edit_audio/edit_audio_form.dart` (changed)

Removed the title availability check (titles are not unique); the artists and album tag fields are gone (they are
relationships now).

#### `pages/edit_audio/edit_audio_notifier.dart` (changed)

`save()` only sends the title (`PATCH /title`), lyrics (`PATCH /lyrics`) and the other tags (`PATCH /tag`). It no
longer saves artists / album.

#### `pages/edit_audio/edit_audio_api.dart` (changed)

Removed `isTitleUnique`, `updateArtists`, `updateAlbum` and their constants (those routes are gone).

#### `pages/edit_audio/audio_tag_specs.dart` (changed)

Removed the `artists` and `album` tag specs.

#### `pages/edit_album/edit_album_page.dart` (changed)

Adds the "Danger zone" section below the form. (A round-2 "album owner" section was removed again: albums have no
single artist any more.)

#### `pages/edit_album/edit_album_api.dart` (changed)

Create is `POST /api/album?name=...` (answers `{ albumId }`), rename is `PATCH /api/album/name { albumId, albumName }`.

#### `pages/edit_album/delete_album_audios_section.dart` (new)

- **Responsibility:** "Delete all audios of this album", one by one.
- **API:** `DeleteAlbumAudiosSection(albumId, albumName)`.
- **What it does:** confirmation dialog; loads every audio id of the album
  (`GET /api/relationship/album/audio`); then `DELETE /api/audio/:id` for each, with a progress bar and Cancel; stops at
  the first failure; a toast says how many were deleted. The audios are deleted everywhere, not only from the album.

#### `pages/edit_artist/edit_artist_api.dart` (changed)

Create is `POST /api/artist?name=...` followed by a lookup by name (the route does not return the new artist), rename
is `PATCH /api/artist/name { artistId, artistName }`.

### 2.4 Browsing pages

#### `pages/search/search_page.dart` (changed)

- **Responsibility:** search and browse (tabs, paging, edit mode, queue buttons).
- **API:** `SearchPage`; `SearchTab` now has five tabs: `artists`, `albums`, `audios`, **`noArtist`**
  (`GET /api/relationship/audio/no-artist`: audios no artist is linked to, same audio documents as the Audios tab),
  `playlists`. Notifier: `refresh(tab)`, `loadMore(tab)`, `addToQueue(item, play:)`, `deleteAudio(id)`,
  **`deleteCatalogItem(item)`** (artist or album).
- **Changed:**
  - albums are queued / loaded by `albumId` (`/api/relationship/album/audio`);
  - audio rows show their artists (looked up per audio) and have the two `AudioRowActions` buttons; album rows show
    their artists (names repeat);
  - **delete now works for artists and albums** (before, the button had no handler and was disabled): confirmation, then
    `DELETE /api/artist/:id` / `DELETE /api/album/:id`; an artist that still has albums or audios is refused and the
    message says so; an album delete keeps its audios;
  - after editing an audio, the "No artist" tab is refreshed too (only if it was opened).
- **Use:** the "No artist" tab is how you find audios that still need an artist: open it, tap the pencil, edit.

#### `pages/search/album_playlist_menu.dart` (changed)

- **Responsibility:** saving audios to playlists.
- **API:** `AlbumPlaylistMenu(album)` (an album's audios), **`AudioPlaylistMenu(audioIds: () => ids)`** (any list, "Add to
  a playlist" / "Save as a new playlist"), **`SaveAsPlaylistButton(audioIds: () => ids)`** (one button, always a new
  playlist: the queue header uses it), `PlaylistPickerDialog`, `NewPlaylistDialog`, and `AlbumPlaylistActions`
  (`addToPlaylist`, `addIdsToPlaylist`, `saveAsNewPlaylist`, `saveIdsAsNewPlaylist`).
- **Changed:** album audios by id; `POST /api/playlist { name }` returns `{ playlistId }`; audios are added with
  `POST /api/playlist/audio { playlistId, audioIds }` in chunks of 200; audios already in the playlist are skipped.

#### `pages/artist_page.dart` (changed)

- **Responsibility:** an artist's profile: albums grid, play all, and the singles.
- **API:** `ArtistPage(artistId, artistName)`; `ArtistPageApi.albums / audios / singles / albumAudios` (all by id).
- **Changed:** ids instead of names; a **Singles** section (the artist's audios that are on no album,
  `/api/relationship/artist/audio/singles`) with `AudioRowActions` on every row; every album card has an "Add to queue"
  button next to "Play".

### 2.5 Player

#### `components/global/playback_controller.dart` (new)

- **Responsibility:** plays the queue without any widget (see section 1).
- **API:** `PlaybackController.instance`, `start(ProviderContainer)` (call once at startup),
  `player` (the shared `AppAudioPlayer`, created on first use, released when the queue is closed).
- **What it does:** follows `AudioPlayerService.queue`; when the current track changes it reads the access token
  (and the signed token on web), builds the stream URL, opens it in the engine, applies the equalizer, and plays it if
  the queue says so; when the engine reports `ended` it calls `AudioPlayerService.next()`; it attaches the track to
  `SystemMediaSession` and fills in the title and artists a moment later. A load overtaken by a newer one is dropped.

#### `components/global/audio_player_service.dart` (changed)

- **Responsibility:** the global queue + dock UI, callable without a `BuildContext`.
- **API:** `AudioPlayerService.play / add / playNext / remove / move / skipTo / next / previous / close / restore`,
  `setMinimized`, `setQueueVisible`, `queue` (`AudioQueueState`: `ids`, `index`, `minimized`, `autoPlay`, `session`,
  `currentId`, `hasNext`, `hasPrevious`).
- **Changed:** artists / albums in the mini bar and queue come from the lookups; the minimized dock has a **seek bar** on
  its top edge (`kDockSeekHeight`, tap or drag to seek, the handle grows on mouse hover / drag); the queue header has the
  "Save the queue as a playlist" button; the dock shares the controller's engine (`sharedAudioPlayerProvider`) and builds
  `AudioContainer(managed: true)`.

#### `components/global/system_media_session.dart` (new)

- **Responsibility:** the OS media controls through `audio_service` (Android / iOS / macOS built in, Windows
  `audio_service_win`, Linux `audio_service_mpris`); also audio focus (`audio_session`): pauses on a call or when
  headphones are unplugged.
- **API:** `SystemMediaSession.init()` (at startup, not on web), `attach(track, controls, states) -> token`,
  `update(token, track, controls)`, `detach(token)`; `SessionTrack(id, title, artist, artUrl, artHeaders)`,
  `SessionControls(play, pause, seek, next?, previous?)` (a null next / previous hides that button).
- **Use:** `PlaybackController` does it; a stand-alone `AudioPlayerScreen` does it for its own track.

#### `components/contents/audio_container.dart` (changed)

- **Responsibility:** loads the audio (title) and the artist label, then builds `AudioPlayerScreen`.
- **API:** `AudioContainer(..., managed: bool)`. **`managed: true`** (the dock): the track is opened and advanced by
  `PlaybackController`, so no stream URL / signed token is built here.

#### `components/contents/players/audio/audio_player_screen.dart` (changed)

- **Responsibility:** the full player (cover, seek / waveform, controls, speed, equalizer, info panels).
- **API:** `AudioPlayerScreen(..., managed: bool)`; `kCompactPlayerWidth = 600`.
- **Changed:** **below 600 dp the main controls show previous / next instead of -10 / +10 seconds**; with
  `managed: true` it does not open the track, listen for the end or attach to the OS session; the title and artist shown
  are the ones passed in (`widget.title`, `widget.artist`), never the engine's.

#### `components/contents/players/audio/audio_player_provider.dart` (changed)

- **Responsibility:** the commands the UI sends to the engine (`AudioPlayerCommands`: `play`, `pause`, `seek`,
  `setVolume`, `setSpeed`, `skipForward`, `skipBackward`, `open`, `stateStream`, `currentState`, `equalizer`).
- **Changed:** **`sharedAudioPlayerProvider`**: when it is set (the dock's scope) the commands use that engine and
  neither create nor dispose their own; when it is null they create their own, as before.
- **Note:** `AudioPlayerCommands` is a generated provider: `dart run build_runner build` refreshes its hash (not required
  to run).

#### `components/contents/players/audio/audio_player_factory.dart` (changed)

`createAudioPlayer()`: `WebAudioPlayer` on web, `MediaKitAudioPlayer` everywhere else. The `kUseWebAudioEngine` fallback
is gone.

#### `components/contents/players/audio/web_audio_player_stub.dart` (changed)

Placeholder `WebAudioPlayer` for non-web builds (extends `MediaKitAudioPlayer`, never created).

#### `components/contents/players/audio/media_kit_audio_player.dart` (new)

- **Responsibility:** the audio engine of every non-web platform: libmpv through `media_kit`.
- **API:** `MediaKitAudioPlayer implements AppAudioPlayer`: `open(url, {headers, title, artist, albumArtUrl})`, `play`,
  `pause`, `togglePlayPause`, `seek`, `setVolume(0..1)`, `setSpeed(0.25..4)`, `skipForward`, `skipBackward`, `dispose`,
  `state`, `stateStream`, `equalizer`.
- **What it does:** maps media_kit's streams to `AudioPlayerState` (`loading`, `playing`, `paused`, `buffering`, `ended`,
  `error`); on Android / iOS it activates the audio session before playing.

#### `components/contents/players/audio/mpv_equalizer.dart` (new)

- **Responsibility:** the equalizer of that engine.
- **API:** `MpvEqualizer implements AppEqualizer`: `bands()` (10 octave bands, 31 Hz-16 kHz, +-12 dB, same as web),
  `setEnabled`, `setBandGain(index, db)`, `available`.
- **What it does:** builds an mpv `af` filter chain (`lavfi=[equalizer=...]`, only the bands that aren't flat) and sets it
  after a short debounce. If libmpv refuses it, `available` becomes false.

#### `components/contents/players/audio/equalizer_settings.dart` (changed)

Comment only: every engine now has the same 10 bands. The saved gains are per band index, so old 5-band Android settings
land on the first five bands (reset the sliders once).

#### `components/contents/players/audio/audio_info_panels.dart` (changed)

The "tags" panel is always available and starts with **Artists** and **Albums** rows (from the lookups, they are not tags
any more).

#### `main.dart` (changed)

Removed the `just_audio_media_kit` init; non-web: `MediaKit.ensureInitialized()` then `SystemMediaSession.init()`;
before `runApp`: `PlaybackController.instance.start(container)`.

---

## 3. Removed files

- `components/contents/players/audio/just_audio_player.dart` (the engine is `media_kit_audio_player.dart` now).
- `pages/edit_album/album_owner_section.dart` (only if you applied round 2; albums have no single artist any more).
- Packages: `just_audio`, `just_audio_media_kit` out; `audio_service`, `audio_session`, `audio_service_win`,
  `audio_service_mpris` in (see `ROUND3_SETUP.md`).

## 4. Files outside `client/lib`

- `ROUND3_SETUP.md`: pub commands and the Android / iOS / macOS / Windows / Linux setup for the engine and OS controls.
- `BACKEND_no_artist_route.md`: the backend route behind the "No artist" tab (schema, repository method, route).
- `MANIFEST.md`: which files are new / changed / unchanged, and how to compare with your copy.
- `migrate-artist-album-audio-compass.js` (paste into Compass' shell: `migrate()` dry run, `migrate(true)` writes):
  converts the old `{artistName, albumName, audioTitle}` documents to `{artistId, albumId, audioId}`, one document per
  audio when a title is shared by several audios, and skips rows that match nothing. This is the current one;
  `migrate-artist-album-audio.js` (mongosh `--file`, `APPLY=1`) is the first version of it, without the shared-title rule.

## 5. Backend routes the client uses

| Area | Route |
|---|---|
| Read relationships | `GET /api/relationship/audio/artist`, `/audio/album`, `/audio/artist/album`, `/audio/album/artist`, `/album/artist`, `/album/audio`, `/artist/album`, `/artist/audio`, `/artist/audio/singles` (`?page&pageSize` + ids) |
| No-artist tab | `GET /api/relationship/audio/no-artist?page&pageSize&search` (see `BACKEND_no_artist_route.md`) |
| Edit relationships (admin) | `POST /api/relationship { audioId, artistId?, albumId? }`, `DELETE /api/relationship { audioId, artistId?, albumId? }` |
| Artists / albums | `GET /api/artist`, `GET /api/album` (`?search`), `GET /api/artist/info`, `POST /api/artist?name`, `POST /api/album?name`, `PATCH /api/artist/name`, `PATCH /api/album/name`, `DELETE /api/artist/:id`, `DELETE /api/album/:id` |
| Audio | `GET /api/audio/info`, `GET /api/audio/singed_token` (web), `PATCH /api/audio/title`, `/lyrics`, `/tag`, `DELETE /api/audio/:id` |
| Playlists | `GET /api/playlist`, `POST /api/playlist { name }` -> `{ playlistId }`, `GET /api/playlist/audio`, `POST /api/playlist/audio { playlistId, audioIds }` |

## 6. Check list

- Edit an audio: add / remove artist-only, album-only and artist+album pairs; create a new artist and a new album from
  the autocomplete.
- Search: the "No artist" tab; delete an album; delete an artist with and without albums / audios (the second is refused).
- Player: next track starts with the window minimized (Windows) and with the screen off (mobile); media keys and the
  notification / lock screen work; the equalizer changes the sound; seek bar on the minimized dock; previous / next on
  narrow screens; save the queue as a playlist.
