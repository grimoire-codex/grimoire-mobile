# Grimoire Mobile

A phone-first iOS and Android app for a self-hosted [Grimoire](https://github.com/hunter-read/grimoire)
server. Browse your TTRPG library, read books, search inside them, and download PDFs to read
with no connection.

There is no hosted service: the app always connects to a Grimoire you run yourself.

## What it does

- **Sign in to your own server** with a username and password, an API key, or single sign-on
  (OIDC) through your phone's browser, the way the Audiobookshelf app does.
- **Browse** game systems, categories and books, with covers, a Continue reading shelf and
  Recently added.
- **Read** with pinch and double-tap zoom, tap or swipe to turn pages, a page scrubber, the
  table of contents and your Grimoire bookmarks.
- **Search** titles, metadata and the full text of indexed books, then jump straight to the page.
- **Read offline.** Download a PDF and the phone renders its pages itself.

## How pages are rendered

While the server is reachable, Grimoire renders each page (`/api/books/:id/page/:n`) at
the phone screen's width, exactly as it does for the web reader, and the app keeps those
renders on disk.

A downloaded PDF is the fallback. When the server can't be reached, the reader opens the
downloaded copy with PDFium (via [`pdfrx`](https://pub.dev/packages/pdfrx)) and renders it
on the phone, mirroring what the server does to stay fast:

| Server (PyMuPDF) | Phone (PDFium) |
|---|---|
| Renders at the requested `width`, not full size | Renders at the screen's pixel width, rounded up to a 200 px step |
| Content-addressed page cache | Flutter image cache keyed by file, page and width |
| A page that is already rendering is awaited, not re-rendered | Same: requests for the same page share one render |
| The web reader preloads nearby pages | Preloads the next two pages and the previous one at low priority |
| Tiles for sharp zoom | Re-renders at the zoomed width once you pinch past 1.25x |

If the connection drops mid-book, the reader switches to the downloaded copy on the same
page. **Settings → Render downloads on this device** makes the phone render downloaded books
even while online.

## Server requirements

Everything except OIDC sign-in works with an unmodified Grimoire server.

OIDC from the app needs a Grimoire version with mobile sign-in (`/api/auth/openid/mobile-token`
and `oidc_mobile_enabled` in `/api/auth/config`). On an older server the app hides the SSO
button and suggests an API key instead. See Grimoire's `docs/oidc.md` → *Mobile app sign-in*.
Your identity provider needs no extra redirect URI: it still returns to Grimoire's own callback,
and Grimoire then hands off to `grimoire://oauth`.

## Development

Requires Flutter 3.47+ (Dart 3.13).

```bash
flutter pub get
flutter run                 # on a connected device or simulator
flutter analyze             # lint (CI enforces this)
flutter test                # unit and widget tests (CI enforces this)
flutter build apk --debug   # Android
flutter build ios --simulator   # iOS (needs Xcode and CocoaPods)
```

See [`docs/architecture.md`](docs/architecture.md) for how the app is put together and
[`docs/roadmap.md`](docs/roadmap.md) for what is planned next.

## License

GPL-3.0, the same as Grimoire. See [`LICENSE`](LICENSE).
