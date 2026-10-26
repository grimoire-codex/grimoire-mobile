# Roadmap

## In scope for the app

### Character sheets

**Decided (2026-10-25):** each community sheet ships a phone layout, `<id>.mobile.html` plus
`<id>.mobile.css`, beside its desktop `<id>.html`/`<id>.css`, using more tabs so each tab fits
a phone screen. Grimoire stores them as `mobile_layout_html`/`mobile_styles` and serves the
parsed `mobile_layout_ast`/`mobile_styles_css`. The web app uses them at 640 px wide or less.

The app's **Characters** tab lists your characters and your parties' natively, and opens a
sheet in a web view of Grimoire's own sheet page, so formulas, `on_pick` grants, the content
catalog, validators and the mobile stylesheet all work exactly as on the web. The web view
gets its session from the app over the host bridge (`lib/features/characters/host_bridge.dart`
and Grimoire's `frontend/src/api/host.ts`), because two independent refreshers of one session
would revoke it.

Status:
- [x] App: Characters tab, sheet web view, host bridge
- [x] Grimoire web: host bridge (`feat/mobile-app-host`)
- [ ] Grimoire: `mobile_layout_html`/`mobile_styles` support (`feat/sheet-mobile-layouts`)
- [ ] community-add-ons: index/docs support plus reference layouts for Cairn and Call of
      Cthulhu 7e (`feat/mobile-sheet-layouts`), then the remaining sheets
- [ ] Offline sheets (not possible with the web view; revisit if needed at the table)
- [ ] API-key sessions: the bridge only hands over JWTs, so sheets need a password or SSO
      sign-in

### Token creator

Everything happens on the device except loading frames and saving the result:

- Pick art (photo library, camera, files, or a library token via `/api/tokens/:id/file`),
  then pan, pinch-zoom, rotate and flip.
- Frames from `GET /api/token-frames` and `/api/token-frames/:id/file`. Bundle the three
  built-in frames (PC, NPC, Opponent) and the generic circle and square.
- Composite with Canvas and `PictureRecorder` as `tokenCompositor.js` does. The frame's
  opening is found by a flood fill from the centre over transparent pixels, as in
  `frameMask.js`.
- Output at 140, 256, 512 or 1024 px: save to Photos or Files, share, or send to a campaign
  (`POST /api/campaigns/:id/members/:member_id/art|token`, `POST /api/campaigns/:id/images`).

### Smaller follow-ups

- Offline EPUB and CBZ/CBR (comics are plain archives of images, so this is easy).
- Background downloads (`URLSession` background tasks on iOS, WorkManager on Android).
- Full-text search within downloaded PDFs while offline.
- Text selection and copy from pages, using `/api/books/:id/page/:n/words` online and PDFium
  text offline.
- Two-page spreads in landscape on tablets.
- Favourites, campaigns (wiki, schedule) and the audio player.
- App icon and splash screen.

## Not in the app

- The map editor stays web-only.
- Admin screens (users, settings, scans, files) stay web-only.
