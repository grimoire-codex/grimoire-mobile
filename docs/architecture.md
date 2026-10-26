# Architecture

```
lib/
├── main.dart                 # loads prefs, session and dirs, then runs the app
├── app/                      # theme (Grimoire's palette) and go_router setup
├── core/                     # no UI
│   ├── api.dart              # GrimoireApi: Dio client, auth, refresh-and-retry
│   ├── session.dart          # Session + SessionStore (keychain / keystore)
│   ├── auth.dart             # authProvider (signed-in session), apiProvider
│   ├── reachability.dart     # is the server answering right now?
│   ├── pkce.dart             # PKCE pair for OIDC
│   ├── disk_cache.dart       # LRU byte cache for page renders and covers
│   ├── storage.dart          # where files live
│   ├── settings.dart         # user settings (SharedPreferences)
│   └── models.dart           # Book, GameSystem, TocEntry, ...
├── features/
│   ├── login/                # server, password, API key, OIDC
│   ├── library/              # home, system and book screens
│   ├── reader/               # page sources, renderers, reader UI
│   ├── search/
│   ├── characters/           # character list + sheet web view + host bridge
│   ├── downloads/            # DownloadManager + screen
│   └── settings/
└── widgets/                  # covers, book tiles, offline banner
```

State is [Riverpod](https://riverpod.dev) 3 (no code generation). Navigation is go_router
with a five-tab `StatefulShellRoute` (Library, Search, Characters, Downloads, Settings). The book page and the reader push over the tabs.

## Talking to Grimoire

The app uses Grimoire's existing REST API, unchanged, apart from OIDC sign-in.

- **Auth.** A password sign-in returns an access token and sets the `grimoire_refresh`
  cookie. The app keeps both in secure storage. On a `401` it replays the cookie to
  `POST /api/auth/refresh` and retries, sharing one refresh across concurrent requests,
  because refresh tokens are single-use and two parallel exchanges would revoke the session.
  A network failure during refresh is not treated as a sign-out.
- **API keys** go in `X-API-Key` and never refresh.
- **OIDC** opens `/api/auth/openid/login?redirect_uri=grimoire://oauth&code_challenge=…`
  in an `ASWebAuthenticationSession` (iOS) or Custom Tab (Android). Grimoire redirects back
  with a one-time code, which the app exchanges with its PKCE verifier at
  `/api/auth/openid/mobile-token`.

## Reading: online first, offline fallback

`features/reader/`:

- `page_source.dart`: `chooseSource()` decides server or device. `ServerPageSource` and
  `DevicePageSource` hand the reader an `ImageProvider` per page and width.
- `page_images.dart`: `ServerPageImage` fetches `/api/books/:id/page/:n?width=&v=` through
  the authenticated client and caches bytes on disk under `book/contentToken/width/page`.
  `LocalPageImage` renders through `LocalPdf`. Both are keyed by value, so Flutter's
  `ImageCache` dedupes in-flight renders and keeps recent pages decoded.
- `local_pdf.dart`: PDFium via pdfrx, rendering at the shown width and at high priority for
  the visible page, normal for prefetch.
- `reader_controller.dart`: owns the open book. It falls back to the download when
  reachability drops or a server page fails with a network error, and lets the reader switch
  source by hand.
- `reader_page.dart`: one page. InteractiveViewer for zoom, plus a sharper render after
  pinching past 1.25x, with `gaplessPlayback` so the old image stays until the new one lands.

Reading positions are stored on the device (`progress.dart`), as the web reader stores them
in the browser.

## Downloads

`DownloadManager` writes `downloads/<bookId>/book.pdf` (via a `.part` file) plus
`cover.webp`, and records each finished download, with its book metadata and table of
contents, in `downloads/manifest.json`. Downloads remember which server they came from, and
another server's downloads are hidden rather than deleted. A book whose server
`content_token` no longer matches the download offers an update.

Only PDFs download for offline use today. EPUB and comic archives still read online through
the server's renderer.

## Character sheets

Sheets are drawn by Grimoire's own web renderer in a `webview_flutter` web view
(`features/characters/sheet_screen.dart`), so a sheet's `mobile.html`/`mobile.css`, its formulas
and its pick grants behave exactly as on the web. The app exposes a JavaScript channel,
`GrimoireHostChannel`. Grimoire's web client sees it and asks the app for access tokens instead
of refreshing with the cookie, and hides its own navigation. The app answers through
`HostTokenBroker`, which refreshes the app's session when the web view reports an expired
token, and sets the `grimoire_session` cookie so portraits load. If the loaded page doesn't set
`window.__GRIMOIRE_HOST_AWARE__`, the server predates the bridge, and the app offers to open
the sheet in the browser instead.
