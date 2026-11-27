<img width="1089" height="1058" alt="Screenshot 2026-11-24 at 6 51 54 PM" src="https://github.com/user-attachments/assets/f6fa48c9-77da-418a-a76a-5314ee3ab689" />
# Ensemble

A black-and-blue music app for your Mac. Keep all your songs in one Spotify-style library, organize them into playlists, post them to beat and distribution sites, and check them for samples.

Requires a Mac running macOS 14 (Sonoma) or newer, and the free Xcode app from the Mac App Store.

## Install (one time, uses Terminal once)

**1. Install Xcode.** Open the Mac App Store, search for **Xcode**, install it, then open it once and click **Agree** when it asks about the license. Close it.

**2. Install Homebrew** (skip if you already have it). Paste this into Terminal (Cmd+Space, type "Terminal", press Enter):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**3. Download Ensemble.** Paste this:

```bash
cd ~/Documents && git clone https://github.com/rymacd-projects/Ensemble.git && cd Ensemble
```

**4. Build and install it:**

```bash
bash scripts/install.sh
```

This builds Ensemble, puts it in your **Applications** folder, adds an **Ensemble** shortcut with the icon to your **Desktop**, and opens it. The first build takes a few minutes.

From then on, just double-click Ensemble on your Desktop. You never need Terminal to open it.

> If macOS says a script "cannot be opened", run `chmod +x scripts/*.sh` once and try again.

## Update to the newest version

Double-click **Update Ensemble.command** inside the `Ensemble` folder in your Documents, or paste:

```bash
cd ~/Documents/Ensemble && bash scripts/update.sh
```

## Using Ensemble

### Your Music
- **Add songs:** drag audio files (or whole folders) into the window, or press **Import** (Cmd+O).
- New songs appear at the top. Each song gets: the **original file name** (locked), an **AI-generated creative name** (click to edit), **BPM** and **time** (locked), **date added**, an **Uploaded to** column that fills in with the sites you've posted it to, and a **Notes** column (click to type your own notes).
- **Click a column heading** to sort ascending, and again for descending. Click the arrows icon at the top-left of the list to return to your own order (newest on top).
- **Double-click** a row to play it. Hover over the artwork for a play button.
- **Rearrange:** drag a song up or down the list (grab it anywhere except the two text fields). A blue line shows where it will land, and the empty strip under the last song sends it to the bottom. Right-click and choose **Move** for to top / up / down / to bottom. Drag a song onto a playlist in the sidebar to add it. Reordering is off while the list is sorted or searched.
- **Playlists:** press **+** in the sidebar. Right-click a playlist to rename or delete it.
- **Cover art:** drag a picture onto a song's row, or right-click the artwork and choose **Choose Cover Art…**. Ensemble crops it square and converts it to **3000×3000** (the size Spotify asks for). Right-click again to export it.

### Player bar and keyboard
| Key | Does |
| --- | --- |
| Space | Play / pause |
| Return | Restart the current song |
| Left / Right arrow | Back / forward 5 seconds |

Click or drag the progress bar to jump anywhere. Shuffle, previous, next and repeat (off / all / one) are on the bar. The keys are paused while you're typing in a name field.

### Upload
1. Press **Link** next to a site (BeatStars, Traktrain, Airbit, DistroKid) and sign in on the page that opens. Ensemble never sees your password, it only keeps the signed-in session.
2. Pick songs, then pick one site, several, or **All websites**.
3. Press **Start uploading**. Ensemble opens each site's upload page. When the site asks you to choose a file, Ensemble hands it your song (or your cover art, using the switch at the bottom). You review the details and press the site's own **Publish** button, then press **Mark uploaded** so the song's Notes column records it.

**Why it's semi-automatic:** none of these four sites offers a public upload service for apps, so Ensemble can't post silently in the background. Opening the real upload form and supplying the file is the most reliable way to do it. If a site changes its pages, the upload address is in one place (`Platform` in `Ensemble/Services/UploadService.swift`) and can be updated.

### Sample Finder
Pick a song and press **Listen for samples**. Ensemble plays through the song in short slices, asks **Shazam** what each slice sounds like, and lists anything recognized, with the time it was heard. Each result has **WhoSampled** and **Google** buttons that search for that track. There are also WhoSampled and Google search buttons for your song itself.

Limits to know about:
- WhoSampled doesn't offer a lookup service for apps, so Ensemble opens its search in your browser rather than reading it automatically.
- Shazam recognizes songs in its catalog. Chopped, pitched or layered samples and obscure records are often missed. Treat results as leads, not legal clearance.
- Needs an internet connection.

### Themes
Open the **Theme** menu at the top of the screen and pick one of ten colors (four blues, three reds, three greens). The choice is remembered. The bar at the bottom has soft bars that rise and fall with the music as it plays.

### Creative names
Without any setup, Ensemble invents names offline. For names written by Claude, open **Ensemble > Settings** (Cmd+,) and paste an Anthropic API key. Only the file name, BPM and length are sent, never the audio.

## Automatic updates

Installing Ensemble also turns on a small background updater. Every couple of minutes it checks GitHub. When a new version has been published it builds it quietly, then **closes Ensemble (saving your library first), installs the update and reopens it**. If you weren't using Ensemble, it just installs the update. A notification tells you when it's done.

- Your Mac must be awake and online. If a new version fails to build, nothing changes and you keep the current one.
- It may briefly stop the music when it restarts the app.
- The first time, macOS may say a background item was added. That's the updater.
- Log: `~/Library/Logs/Ensemble-update.log`
- Turn it off: `bash ~/Documents/Ensemble/scripts/disable-auto-update.sh`
- Turn it back on: `bash ~/Documents/Ensemble/scripts/enable-auto-update.sh`

## For developers

Everything is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so the `.xcodeproj` is never committed. Edit code, then:

```bash
xcodegen generate && open Ensemble.xcodeproj
```

Every push to GitHub is built automatically (`.github/workflows/build.yml`). Pushing a tag such as `v1.0.1` publishes `Ensemble.zip` to GitHub Releases:

```bash
git tag v1.0.1 && git push origin v1.0.1
```

Apps downloaded from a Release aren't notarized, so macOS asks you to right-click the app and choose **Open** the first time. Building from source with `install.sh` avoids that.
