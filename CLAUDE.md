# Ensemble: notes for Claude

Native SwiftUI **macOS** music app (macOS 14+, Swift 5 mode). Black and blue, Spotify-style UI. The project is generated from `project.yml` with XcodeGen. Never hand-edit or commit `.xcodeproj`, `Ensemble/Info.plist` or `Ensemble/Ensemble.entitlements`. Change `project.yml` instead.

This Linux workspace cannot compile Swift. After any change, push to GitHub and read the `Build` Actions run. Fix any compile errors it reports. Do not tell the user a change works until CI is green.

## Layout
- `Ensemble/EnsembleApp.swift`: app entry, menu commands, Settings scene
- `Ensemble/Theme.swift`: ten color palettes (`Palette`), `ThemeStore` (selected theme, saved in UserDefaults, picked from the Theme menu), `Theme` colors (`blue` = main accent, `cyan` = lighter accent), glass panel, button styles
- `Ensemble/Models/Models.swift`: `Song`, `Playlist`, `UploadRecord`, `Paths`
- `Ensemble/Services/LibraryStore.swift`: import, drag-drop handling, editing, playlists, cover art, JSON persistence
- `Ensemble/Services/PlayerService.swift`: AVPlayer queue, shuffle/repeat, keyboard shortcuts (NSEvent monitor; ignores sheets, panels, text fields)
- `Ensemble/Services/BPMDetector.swift`: tempo estimate
- `Ensemble/Services/NameGenerator.swift`: creative names (Claude API if a key is saved in Keychain, otherwise offline)
- `Ensemble/Services/CoverArt.swift`: crop/convert to 3000x3000 JPEG plus thumbnail
- `Ensemble/Services/SampleFinder.swift`: ShazamKit windowed scan, WhoSampled and Google link builders
- `Ensemble/Services/UploadService.swift`: `Platform` (BeatStars, Traktrain, Airbit, DistroKid; URLs live here), linked-account state, `WebSession` (WKWebView that answers file pickers with the song or cover)
- `Ensemble/Views/`: SwiftUI screens (`RootView`, `LibraryView`, `PlayerBar`, `UploadView`, `SamplesView`, `SettingsView`, `Components`)
- `scripts/install.sh`, `scripts/update.sh`: build and install to /Applications plus Desktop alias
- `.github/workflows/`: `build.yml` (every push), `release.yml` (tags `v*`)

## Things to remember
- Library order: new songs and songs added to a playlist go to the top. Old libraries are migrated once (`orderVersion`). `Song` fields added later must be optional so old `library.json` files still decode.
- Original name, BPM and time are read-only in the list; creative name and Notes (`userNotes`) are editable. `uploadSummary` is the automatic "Uploaded to" text.
- The four upload sites have no public upload API. Uploads are semi-automatic: an in-app browser opens the upload form and supplies the file; the user presses Publish and "Mark uploaded". If an official API appears, add it behind `Platform`.
- WhoSampled has no public API, so it is opened as a search link. Sample detection is ShazamKit; it needs an internet connection and may need Shazam enabled for the app's bundle ID if matching errors appear.
- The user wants a custom app icon (`Ensemble/Resources/Assets.xcassets/AppIcon.appiconset`, source `icon-1024.png`).

## Shipping a change
1. Edit the Swift files or `project.yml`.
2. Commit and push to `main`; wait for CI.
3. For a downloadable build: bump `MARKETING_VERSION` in `project.yml`, push, then tag `vX.Y.Z`.
4. Users update by running `Update Ensemble.command` or `scripts/update.sh`.
